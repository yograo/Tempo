import { fileURLToPath } from "node:url";
import { CfnOutput, DefaultStackSynthesizer, Duration, PermissionsBoundary, RemovalPolicy, Stack, type IStackSynthesizer, type StackProps } from "aws-cdk-lib";
import { BOOTSTRAP_QUALIFIER, BOUNDARY_POLICY_NAME } from "./deployment-access.js";
import * as apigateway from "aws-cdk-lib/aws-apigatewayv2";
import { HttpLambdaIntegration } from "aws-cdk-lib/aws-apigatewayv2-integrations";
import * as cloudwatch from "aws-cdk-lib/aws-cloudwatch";
import * as dynamodb from "aws-cdk-lib/aws-dynamodb";
import * as iam from "aws-cdk-lib/aws-iam";
import * as lambda from "aws-cdk-lib/aws-lambda";
import * as logs from "aws-cdk-lib/aws-logs";
import type { Construct } from "constructs";

export class FeedbackStack extends Stack {
  constructor(scope: Construct, id: string, props: StackProps = {}) {
    super(scope, id, {
      ...props,
      // CDK's optional qualifier types disagree under exactOptionalPropertyTypes;
      // this instance always has an explicit qualifier.
      synthesizer: new DefaultStackSynthesizer({ qualifier: BOOTSTRAP_QUALIFIER }) as IStackSynthesizer,
      permissionsBoundary: PermissionsBoundary.fromName(BOUNDARY_POLICY_NAME),
    });

    const table = new dynamodb.Table(this, "Requests", {
      partitionKey: { name: "requestId", type: dynamodb.AttributeType.STRING },
      billingMode: dynamodb.BillingMode.PAY_PER_REQUEST,
      maxReadRequestUnits: 25,
      maxWriteRequestUnits: 25,
      encryption: dynamodb.TableEncryption.DEFAULT,
      pointInTimeRecoverySpecification: { pointInTimeRecoveryEnabled: true },
      deletionProtection: true,
      removalPolicy: RemovalPolicy.RETAIN,
    });
    const logGroup = new logs.LogGroup(this, "SubmissionLogs", {
      retention: logs.RetentionDays.ONE_MONTH,
      removalPolicy: RemovalPolicy.DESTROY,
    });
    const submit = new lambda.Function(this, "SubmitRequest", {
      runtime: lambda.Runtime.NODEJS_24_X,
      architecture: lambda.Architecture.ARM_64,
      handler: "index.handler",
      // The compiled infrastructure lives in dist/lib; the bundle is dist/lambda.
      code: lambda.Code.fromAsset(fileURLToPath(new URL("../lambda/", import.meta.url))),
      memorySize: 128,
      timeout: Duration.seconds(5),
      logGroup,
      environment: { REQUESTS_TABLE_NAME: table.tableName },
      description: "Validates and writes feature requests. Cannot read, query, scan, update, or delete requests.",
    });
    submit.addToRolePolicy(new iam.PolicyStatement({
      actions: ["dynamodb:PutItem"],
      resources: [table.tableArn],
      // PutItem could otherwise read an old item through ReturnValues, despite
      // having no GetItem permission. This also covers conditional-write failures.
      conditions: { StringEqualsIfExists: { "dynamodb:ReturnValues": "NONE" } },
    }));

    const api = new apigateway.HttpApi(this, "Api", {
      description: "Tempo public, write-only feature-request API",
      createDefaultStage: true,
      // Native iOS clients don't need CORS. No public read routes or default route.
    });
    api.addRoutes({
      path: "/v1/feature-requests",
      methods: [apigateway.HttpMethod.POST],
      integration: new HttpLambdaIntegration("SubmitIntegration", submit),
    });
    const stage = api.defaultStage!.node.defaultChild as apigateway.CfnStage;
    stage.defaultRouteSettings = { throttlingRateLimit: 1, throttlingBurstLimit: 5 };

    const reader = new iam.ManagedPolicy(this, "OwnerReaderPolicy", {
      description: "Attach only to the owner's IAM identity to review Tempo feature requests. Not attached to the API role.",
      statements: [
        new iam.PolicyStatement({
          actions: ["dynamodb:DescribeTable", "dynamodb:GetItem", "dynamodb:Query", "dynamodb:Scan"],
          resources: [table.tableArn],
        }),
        new iam.PolicyStatement({ actions: ["dynamodb:ListTables"], resources: ["*"] }),
      ],
    });

    new cloudwatch.Alarm(this, "SubmissionFailures", {
      alarmDescription: "Tempo API has returned 5 or more server errors in 5 minutes. No request text is logged.",
      metric: new cloudwatch.Metric({
        namespace: "AWS/ApiGateway", metricName: "5xx", dimensionsMap: { ApiId: api.apiId },
        statistic: "Sum", period: Duration.minutes(5),
      }),
      threshold: 5,
      evaluationPeriods: 1,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
    });

    new CfnOutput(this, "SubmissionUrl", { value: `${api.apiEndpoint}/v1/feature-requests` });
    new CfnOutput(this, "ApiUrl", { value: api.apiEndpoint });
    new CfnOutput(this, "RequestsTableName", { value: table.tableName });
    new CfnOutput(this, "OwnerReaderPolicyArn", { value: reader.managedPolicyArn });
    new CfnOutput(this, "LambdaRoleArn", { value: submit.role!.roleArn });
  }
}
