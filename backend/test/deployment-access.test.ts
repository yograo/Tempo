import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { test } from "node:test";
import { deploymentPolicy, scopedBootstrap, BOUNDARY_POLICY_NAME, BOOTSTRAP_QUALIFIER } from "../lib/deployment-access.js";

const account = "123456789012";
const region = "us-west-2";
const boundary = `arn:aws:iam::${account}:policy/${BOUNDARY_POLICY_NAME}`;
const policy = deploymentPolicy(account, region);

test("deployment policy fits IAM limits and restricts mutation grants to project resources", () => {
  assert.ok(JSON.stringify(policy).length <= 6144);
  const unrestricted = policy.Statement.filter((s) => s.Resource.includes("*"));
  assert.equal(unrestricted.length, 3);
  assert.deepEqual(unrestricted[0]!.Action, ["cloudformation:ValidateTemplate", "cloudformation:GetTemplateSummary", "dynamodb:ListTables", "logs:DescribeLogGroups", "ecr:GetAuthorizationToken", "sts:GetCallerIdentity"]);
  assert.equal(policy.Statement.some((s) => s.Action.includes("*")), false);
  assert.equal(JSON.stringify(policy).includes("AdministratorAccess"), false);
});

test("new roles require the immutable boundary, and the deployer cannot grant user permissions", () => {
  const creator = policy.Statement.find((s) => s.Action.includes("iam:CreateRole"))!;
  assert.deepEqual(creator.Condition, { StringEquals: { "iam:PermissionsBoundary": boundary } });
  const actions = policy.Statement.flatMap((s) => s.Action);
  for (const forbidden of ["iam:DeleteRolePermissionsBoundary", "iam:PutUserPolicy", "iam:AttachUserPolicy", "iam:CreateUser", "iam:*"]) {
    assert.equal(actions.includes(forbidden), false, forbidden);
  }
  const modifiers = policy.Statement.filter((s) => s.Action.some((a) => ["iam:CreatePolicyVersion", "iam:SetDefaultPolicyVersion", "iam:DeletePolicy"].includes(a)));
  for (const modifier of modifiers) assert.deepEqual(modifier.Resource, [`arn:aws:iam::${account}:policy/TempoFeatureRequests-*`]);
  assert.equal(boundary.includes("policy/TempoFeatureRequests-"), false);
});

test("tagged HTTP API stage creation has its additional permission in the selected region", () => {
  const ohioPolicy = deploymentPolicy(account, "us-east-2");
  const stageTagging = ohioPolicy.Statement.find((s) => s.Action.includes("apigateway:TagResource"));
  assert.ok(stageTagging, "CreateStage checks TagResource in addition to its HTTP-method permission");
  assert.deepEqual(stageTagging.Resource, ["arn:aws:apigateway:us-east-2::/apis/*/stages"]);
  assert.equal(JSON.stringify(ohioPolicy).includes("us-west-2"), false);
});

test("the bootstrap puts the boundary on every role and never grants AdministratorAccess", () => {
  const original = JSON.parse(execFileSync(process.execPath,
    ["node_modules/aws-cdk/bin/cdk", "bootstrap", "--show-template", "--json"], { encoding: "utf8", stdio: ["ignore", "pipe", "ignore"] }));
  const scoped = scopedBootstrap(original);
  const roles = Object.values(scoped.Resources).filter((r: any) => r.Type === "AWS::IAM::Role") as any[];
  assert.ok(roles.length >= 5);
  const expected = { "Fn::Sub": `arn:\${AWS::Partition}:iam::\${AWS::AccountId}:policy/${BOUNDARY_POLICY_NAME}` };
  for (const role of roles) assert.deepEqual(role.Properties.PermissionsBoundary, expected);
  assert.deepEqual(scoped.Resources.CloudFormationExecutionRole.Properties.ManagedPolicyArns, [expected]);
  assert.equal(JSON.stringify(scoped.Resources).includes("policy/AdministratorAccess"), false);
  assert.deepEqual(scoped.Parameters.Qualifier.AllowedValues, [BOOTSTRAP_QUALIFIER]);
  assert.deepEqual(scoped.Parameters.InputPermissionsBoundary.AllowedValues, [BOUNDARY_POLICY_NAME]);
  assert.deepEqual(scoped.Parameters.FileAssetsBucketKmsKeyId.AllowedValues, ["AWS_MANAGED_KEY"]);
  assert.equal(scoped.Resources.StagingBucket.Properties.BucketEncryption.ServerSideEncryptionConfiguration[0].ServerSideEncryptionByDefault.SSEAlgorithm, "AES256");
});

test("policy generation rejects malformed account and unsupported region inputs", () => {
  assert.throws(() => deploymentPolicy("*", region));
  assert.throws(() => deploymentPolicy(account, "us-west-2:*"));
  assert.throws(() => scopedBootstrap({ Resources: {} }));
});


test("Cognito creation is tagged and pool administration is limited to Tempo in the chosen region", () => {
  const create = policy.Statement.find((s) => s.Action.includes("cognito-idp:CreateUserPool"))!;
  assert.deepEqual(create.Condition, { StringEquals: { "aws:RequestTag/Application": "TempoFeatureRequests", "aws:RequestedRegion": region } });
  const manage = policy.Statement.find((s) => s.Action.includes("cognito-idp:UpdateUserPool"))!;
  assert.deepEqual(manage.Resource, [`arn:aws:cognito-idp:${region}:${account}:userpool/*`]);
  assert.deepEqual(manage.Condition, { StringEquals: { "aws:ResourceTag/Application": "TempoFeatureRequests" } });
});
