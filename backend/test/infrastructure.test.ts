import assert from "node:assert/strict";
import { test } from "node:test";
import { App } from "aws-cdk-lib";
import { Match, Template } from "aws-cdk-lib/assertions";
import { FeedbackStack } from "../lib/feedback-stack.js";
import { BOUNDARY_POLICY_NAME, BOOTSTRAP_QUALIFIER } from "../lib/deployment-access.js";

const app = new App();
const stack = new FeedbackStack(app, "TempoFeedbackTest");
const template = Template.fromStack(stack);

test("the application uses the isolated bootstrap and applies a boundary to its runtime role", () => {
  const roles = Object.values(template.findResources("AWS::IAM::Role"));
  assert.ok(roles.length > 0);
  for (const role of roles) assert.ok(JSON.stringify(role.Properties.PermissionsBoundary).includes(BOUNDARY_POLICY_NAME));
  assert.equal(template.toJSON().Parameters.BootstrapVersion.Default, `/cdk-bootstrap/${BOOTSTRAP_QUALIFIER}/version`);
});

test("the public API has exactly one route: POST /v1/feature-requests", () => {
  template.resourceCountIs("AWS::ApiGatewayV2::Route", 1);
  template.hasResourceProperties("AWS::ApiGatewayV2::Route", {
    RouteKey: "POST /v1/feature-requests", AuthorizationType: "NONE",
  });
  template.hasResourceProperties("AWS::ApiGatewayV2::Api", { ProtocolType: "HTTP", CorsConfiguration: Match.absent() });
  template.resourceCountIs("AWS::Lambda::Url", 0);
});

test("the Lambda's DynamoDB permission is PutItem on this table only", () => {
  const tables = Object.keys(template.findResources("AWS::DynamoDB::Table"));
  const functions = Object.values(template.findResources("AWS::Lambda::Function"));
  assert.equal(tables.length, 1);
  assert.equal(functions.length, 1);
  const roleId = functions[0]!.Properties.Role["Fn::GetAtt"][0];
  const policies = Object.values(template.findResources("AWS::IAM::Policy"))
    .filter((policy) => policy.Properties.Roles?.some((role: { Ref: string }) => role.Ref === roleId));
  const statements = policies.flatMap((policy) => policy.Properties.PolicyDocument.Statement);
  const databaseGrants = statements.filter((statement) => [statement.Action].flat().some((action: string) => action.startsWith("dynamodb:")));
  assert.equal(databaseGrants.length, 1);
  assert.deepEqual([databaseGrants[0].Action].flat(), ["dynamodb:PutItem"]);
  assert.deepEqual(databaseGrants[0].Resource, { "Fn::GetAtt": [tables[0], "Arn"] });
  assert.equal(databaseGrants[0].Effect, "Allow");
  assert.deepEqual(databaseGrants[0].Condition, { StringEqualsIfExists: { "dynamodb:ReturnValues": "NONE" } });
});

test("the reader policy is separate and isn't granted to the app, Lambda, or arbitrary users", () => {
  template.resourceCountIs("AWS::IAM::ManagedPolicy", 1);
  template.hasResourceProperties("AWS::IAM::ManagedPolicy", {
    Roles: Match.absent(), Users: Match.absent(), Groups: Match.absent(),
    PolicyDocument: { Statement: Match.arrayWith([Match.objectLike({
      Action: ["dynamodb:DescribeTable", "dynamodb:GetItem", "dynamodb:Query", "dynamodb:Scan"], Effect: "Allow",
    })]) },
  });
});

test("requests are retained, deletion protected, backed up, and throughput bounded", () => {
  template.hasResource("AWS::DynamoDB::Table", {
    DeletionPolicy: "Retain", UpdateReplacePolicy: "Retain",
    Properties: Match.objectLike({
      BillingMode: "PAY_PER_REQUEST", DeletionProtectionEnabled: true,
      PointInTimeRecoverySpecification: { PointInTimeRecoveryEnabled: true },
      OnDemandThroughput: { MaxReadRequestUnits: 25, MaxWriteRequestUnits: 25 },
      KeySchema: [{ AttributeName: "requestId", KeyType: "HASH" }],
    }),
  });
});

test("requests are throttled and the API doesn't log payloads or client metadata", () => {
  template.hasResourceProperties("AWS::ApiGatewayV2::Stage", {
    DefaultRouteSettings: { ThrottlingBurstLimit: 5, ThrottlingRateLimit: 1 },
    AccessLogSettings: Match.absent(),
  });
  template.hasResourceProperties("AWS::Logs::LogGroup", { RetentionInDays: 30 });
  template.hasResourceProperties("AWS::CloudWatch::Alarm", { MetricName: "5xx", Threshold: 5 });
});

test("Lambda has bounded execution and no static AWS credentials", () => {
  template.hasResourceProperties("AWS::Lambda::Function", {
    Runtime: "nodejs24.x", Architectures: ["arm64"], Timeout: 5, MemorySize: 128,
    Environment: { Variables: { REQUESTS_TABLE_NAME: Match.anyValue() } },
  });
});
