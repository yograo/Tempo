import assert from "node:assert/strict";
import { test } from "node:test";
import { App } from "aws-cdk-lib";
import { Template, Match } from "aws-cdk-lib/assertions";
import { DashboardStack } from "../lib/dashboard-stack.js";
const stack = new DashboardStack(new App(), "TempoFeatureRequests-test-Dashboard", { tableName: "TempoFeatureRequests-test-existing", stage: "dev" });
const template = Template.fromStack(stack);
test("dashboard imports the existing table and creates no replacement data resources", () => {
  template.resourceCountIs("AWS::DynamoDB::Table", 0);
  template.resourceCountIs("AWS::Lambda::Function", 2);
  template.resourceCountIs("AWS::ApiGatewayV2::Api", 1);
});
test("closed Cognito pool requires authenticator MFA and retains identity data", () => {
  template.hasResource("AWS::Cognito::UserPool", { DeletionPolicy: "Retain", Properties: Match.objectLike({
    AdminCreateUserConfig: { AllowAdminCreateUserOnly: true }, MfaConfiguration: "ON", EnabledMfas: ["SOFTWARE_TOKEN_MFA"], DeletionProtection: "ACTIVE",
    AccountRecoverySetting: { RecoveryMechanisms: [{ Name: "admin_only", Priority: 1 }] },
  }) });
  template.hasResourceProperties("AWS::Cognito::UserPoolGroup", { GroupName: "TempoOwners" });
  template.hasResourceProperties("AWS::Cognito::UserPoolClient", { GenerateSecret: false, AllowedOAuthFlows: ["code"], AllowedOAuthScopes: ["openid"], EnableTokenRevocation: true, AccessTokenValidity: 10 });
});
test("every admin route requires the pool JWT and OAuth access-token scope", () => {
  const routes = Object.values(template.findResources("AWS::ApiGatewayV2::Route")) as any[];
  const admin = routes.filter((r) => r.Properties.RouteKey.includes("/admin/"));
  assert.equal(admin.length, 2);
  for (const route of admin) { assert.equal(route.Properties.AuthorizationType, "JWT"); assert.deepEqual(route.Properties.AuthorizationScopes, ["openid"]); assert.ok(route.Properties.AuthorizerId); }
  for (const route of routes.filter((r) => !r.Properties.RouteKey.includes("/admin/"))) assert.equal(route.Properties.AuthorizationType, "NONE");
  template.hasResourceProperties("AWS::ApiGatewayV2::Authorizer", { AuthorizerType: "JWT", IdentitySource: ["$request.header.Authorization"] });
});
test("only the admin function can scan and update, and both runtime roles have a boundary", () => {
  const statements = Object.values(template.findResources("AWS::IAM::Policy")).flatMap((r: any) => r.Properties.PolicyDocument.Statement);
  const data = statements.filter((s: any) => JSON.stringify(s.Action).includes("dynamodb:"));
  assert.equal(data.length, 1); assert.deepEqual(data[0].Action, ["dynamodb:Scan", "dynamodb:UpdateItem"]);
  assert.ok(JSON.stringify(data[0].Resource).includes("table/TempoFeatureRequests-test-existing"));
  for (const role of Object.values(template.findResources("AWS::IAM::Role")) as any[]) assert.ok(JSON.stringify(role.Properties.PermissionsBoundary).includes("TempoFeedbackDeploymentBoundary"));
  const all = JSON.stringify(statements); assert.equal(all.includes("cognito-idp:"), false); assert.equal(all.includes("dynamodb:DeleteItem"), false);
});
