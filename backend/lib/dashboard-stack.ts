import { fileURLToPath } from "node:url";
import { CfnOutput, DefaultStackSynthesizer, Duration, PermissionsBoundary, RemovalPolicy, Stack, type IStackSynthesizer, type StackProps } from "aws-cdk-lib";
import * as apigateway from "aws-cdk-lib/aws-apigatewayv2";
import { HttpJwtAuthorizer } from "aws-cdk-lib/aws-apigatewayv2-authorizers";
import { HttpLambdaIntegration } from "aws-cdk-lib/aws-apigatewayv2-integrations";
import * as cognito from "aws-cdk-lib/aws-cognito";
import * as iam from "aws-cdk-lib/aws-iam";
import * as lambda from "aws-cdk-lib/aws-lambda";
import * as logs from "aws-cdk-lib/aws-logs";
import type { Construct } from "constructs";
import { BOOTSTRAP_QUALIFIER, BOUNDARY_POLICY_NAME } from "./deployment-access.js";
import { OWNER_GROUP } from "../src/admin.js";

interface DashboardProps extends StackProps { tableName: string; stage: "dev" | "prod" }
export class DashboardStack extends Stack {
  constructor(scope: Construct, id: string, props: DashboardProps) {
    super(scope, id, { ...props,
      synthesizer: new DefaultStackSynthesizer({ qualifier: BOOTSTRAP_QUALIFIER }) as IStackSynthesizer,
      permissionsBoundary: PermissionsBoundary.fromName(BOUNDARY_POLICY_NAME),
    });
    // Imported by name: no exports, modifications, or replacement of the app stack.
    const tableArn = this.formatArn({ service: "dynamodb", resource: "table", resourceName: props.tableName });
    const api = new apigateway.HttpApi(this, "AdminApi", { description: "Tempo private owner dashboard", createDefaultStage: true });
    const apiStage = api.defaultStage!.node.defaultChild as apigateway.CfnStage;
    apiStage.defaultRouteSettings = { throttlingRateLimit: 5, throttlingBurstLimit: 15 };
    const pool = new cognito.UserPool(this, "Owners", {
      userPoolName: `TempoFeatureRequests-${props.stage}-owners`,
      selfSignUpEnabled: false, signInAliases: { username: true },
      mfa: cognito.Mfa.REQUIRED, mfaSecondFactor: { sms: false, otp: true },
      accountRecovery: cognito.AccountRecovery.NONE,
      passwordPolicy: { minLength: 14, requireLowercase: true, requireUppercase: true, requireDigits: true, requireSymbols: true, tempPasswordValidity: Duration.days(1) },
      removalPolicy: RemovalPolicy.RETAIN,
      deletionProtection: true,
    });
    // This tag is also the deployment policy's scope for pool management.
    const cfnPool = pool.node.defaultChild as cognito.CfnUserPool;
    cfnPool.userPoolTagsRaw = { Application: "TempoFeatureRequests" };
    new cognito.CfnUserPoolGroup(this, "OwnerGroup", { userPoolId: pool.userPoolId, groupName: OWNER_GROUP, description: "Only the Tempo owner belongs to this group." });
    const domain = pool.addDomain("Login", { cognitoDomain: { domainPrefix: `tempo-owner-${this.account}-${props.stage}` } });
    const client = pool.addClient("Dashboard", {
      generateSecret: false, preventUserExistenceErrors: true, enableTokenRevocation: true,
      authFlows: { userSrp: false, userPassword: false, custom: false },
      oAuth: { flows: { authorizationCodeGrant: true, implicitCodeGrant: false }, scopes: [cognito.OAuthScope.OPENID],
        callbackUrls: [`${api.apiEndpoint}/`], logoutUrls: [`${api.apiEndpoint}/`] },
      supportedIdentityProviders: [cognito.UserPoolClientIdentityProvider.COGNITO],
      accessTokenValidity: Duration.minutes(10), idTokenValidity: Duration.minutes(10), refreshTokenValidity: Duration.hours(1),
    });
    const functionProps = (name: string, artifact: string) => ({
      runtime: lambda.Runtime.NODEJS_24_X, architecture: lambda.Architecture.ARM_64, handler: "index.handler",
      code: lambda.Code.fromAsset(fileURLToPath(new URL(`../${artifact}/`, import.meta.url))),
      memorySize: 128, timeout: Duration.seconds(10),
      logGroup: new logs.LogGroup(this, `${name}Logs`, { retention: logs.RetentionDays.ONE_MONTH, removalPolicy: RemovalPolicy.DESTROY }),
    });
    const admin = new lambda.Function(this, "Admin", { ...functionProps("Admin", "admin-lambda"),
      environment: { REQUESTS_TABLE_NAME: props.tableName }, description: "Owner-group authenticated review and status updates; no request creation or deletion." });
    admin.addToRolePolicy(new iam.PolicyStatement({ actions: ["dynamodb:Scan", "dynamodb:UpdateItem"], resources: [tableArn] }));
    const authorizer = new HttpJwtAuthorizer("OwnerJwt", pool.userPoolProviderUrl, { jwtAudience: [client.userPoolClientId] });
    const integration = new HttpLambdaIntegration("AdminIntegration", admin);
    api.addRoutes({ path: "/admin/requests", methods: [apigateway.HttpMethod.GET], integration, authorizer, authorizationScopes: ["openid"] });
    api.addRoutes({ path: "/admin/requests/{requestId}", methods: [apigateway.HttpMethod.PATCH], integration, authorizer, authorizationScopes: ["openid"] });
    // Separate function with NO DynamoDB/Cognito permissions serves public assets.
    const site = new lambda.Function(this, "Website", { ...functionProps("Website", "site-lambda"),
      environment: { AUTH_ORIGIN: domain.baseUrl(), CLIENT_ID: client.userPoolClientId }, description: "Static owner dashboard shell. No access to request data or user administration." });
    const siteIntegration = new HttpLambdaIntegration("WebsiteIntegration", site);
    for (const path of ["/", "/app.js", "/auth.js", "/model.js", "/style.css", "/config.json"]) {
      api.addRoutes({ path, methods: [apigateway.HttpMethod.GET], integration: siteIntegration });
    }
    new CfnOutput(this, "DashboardUrl", { value: `${api.apiEndpoint}/` });
    new CfnOutput(this, "UserPoolId", { value: pool.userPoolId });
    new CfnOutput(this, "UserPoolClientId", { value: client.userPoolClientId });
    new CfnOutput(this, "AuthOrigin", { value: domain.baseUrl() });
    new CfnOutput(this, "OwnerGroupName", { value: OWNER_GROUP });
  }
}
