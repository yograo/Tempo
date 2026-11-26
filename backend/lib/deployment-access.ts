export const BOOTSTRAP_QUALIFIER = "tempofb";
export const BOOTSTRAP_STACK_NAME = "TempoCDKToolkit";
export const BOUNDARY_POLICY_NAME = "TempoFeedbackDeploymentBoundary";

/** This is both the deployer's permission policy and the ceiling on created roles. */
export function deploymentPolicy(account: string, region: string) {
  if (!/^\d{12}$/.test(account)) throw new Error("Use a 12-digit AWS account ID.");
  if (!/^us-(?:east|west)-[12]$/.test(region)) throw new Error("Use a supported US commercial region, such as us-east-2. For an AWS project, use its assigned region.");
  const arn = (service: string, resource: string) => `arn:aws:${service}:${region}:${account}:${resource}`;
  const boundary = `arn:aws:iam::${account}:policy/${BOUNDARY_POLICY_NAME}`;
  const appRoles = `arn:aws:iam::${account}:role/TempoFeatureRequests-*`;
  const bootstrapRoles = `arn:aws:iam::${account}:role/cdk-${BOOTSTRAP_QUALIFIER}-*-${account}-${region}`;
  const bucket = `arn:aws:s3:::cdk-${BOOTSTRAP_QUALIFIER}-assets-${account}-${region}`;
  const allow = (Action: string[], Resource: string[], Condition?: object) => ({ Effect: "Allow", Action, Resource, ...(Condition ? { Condition } : {}) });
  const policy = {
    Version: "2012-10-17",
    Statement: [
      allow(["cloudformation:*"], [arn("cloudformation", `stack/${BOOTSTRAP_STACK_NAME}/*`), arn("cloudformation", "stack/TempoFeatureRequests-*/*")]),
      allow(["cloudformation:ValidateTemplate", "cloudformation:GetTemplateSummary", "dynamodb:ListTables", "logs:DescribeLogGroups", "ecr:GetAuthorizationToken", "sts:GetCallerIdentity"], ["*"]),
      allow(["s3:*"], [bucket, `${bucket}/*`]),
      allow(["ecr:*"], [arn("ecr", `repository/cdk-${BOOTSTRAP_QUALIFIER}-container-assets-${account}-${region}`)]),
      allow(["ssm:GetParameter", "ssm:GetParameters", "ssm:PutParameter", "ssm:DeleteParameter", "ssm:AddTagsToResource", "ssm:RemoveTagsFromResource"], [arn("ssm", `parameter/cdk-bootstrap/${BOOTSTRAP_QUALIFIER}/version`)]),
      allow(["lambda:*"], [arn("lambda", "function:TempoFeatureRequests-*")]),
      allow(["dynamodb:*"], [arn("dynamodb", "table/TempoFeatureRequests-*")]),
      allow(["logs:*"], [arn("logs", "log-group:TempoFeatureRequests-*")]),
      allow(["cloudwatch:PutMetricAlarm", "cloudwatch:DeleteAlarms", "cloudwatch:DescribeAlarms", "cloudwatch:TagResource", "cloudwatch:UntagResource", "cloudwatch:ListTagsForResource"], [arn("cloudwatch", "alarm:TempoFeatureRequests-*")]),
      // HTTP API IDs are assigned by AWS, so these control-plane permissions
      // cover HTTP APIs and API Gateway tags in this region.
      allow(["apigateway:GET", "apigateway:POST", "apigateway:PUT", "apigateway:PATCH", "apigateway:DELETE"], [`arn:aws:apigateway:${region}::/apis`, `arn:aws:apigateway:${region}::/apis/*`, `arn:aws:apigateway:${region}::/tags/*`]),
      // CreateStage with tags also checks this named action on the stages
      // collection, even when the HTTP-method permissions above are allowed.
      // Observed in CloudFormation's CreateStage AccessDenied response.
      allow(["apigateway:TagResource"], [`arn:aws:apigateway:${region}::/apis/*/stages`]),
      allow(["iam:CreateRole", "iam:PutRolePermissionsBoundary"], [appRoles, bootstrapRoles], { StringEquals: { "iam:PermissionsBoundary": boundary } }),
      allow(["iam:GetRole", "iam:GetRolePolicy", "iam:ListRolePolicies", "iam:ListAttachedRolePolicies", "iam:ListRoleTags", "iam:PutRolePolicy", "iam:DeleteRolePolicy", "iam:DeleteRole", "iam:UpdateRole", "iam:UpdateAssumeRolePolicy", "iam:TagRole", "iam:UntagRole"], [appRoles, bootstrapRoles]),
      allow(["iam:AttachRolePolicy", "iam:DetachRolePolicy"], [appRoles, bootstrapRoles], { ArnEquals: { "iam:PolicyARN": [boundary, "arn:aws:iam::aws:policy/ReadOnlyAccess", "arn:aws:iam::aws:policy/AWSCloudFormationReadOnlyAccess", "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"] } }),
      allow(["iam:CreatePolicy", "iam:CreatePolicyVersion", "iam:SetDefaultPolicyVersion", "iam:DeletePolicyVersion", "iam:DeletePolicy", "iam:GetPolicy", "iam:GetPolicyVersion", "iam:ListPolicyVersions", "iam:ListPolicyTags", "iam:ListEntitiesForPolicy", "iam:TagPolicy", "iam:UntagPolicy"], [`arn:aws:iam::${account}:policy/TempoFeatureRequests-*`]),
      allow(["iam:GetPolicy", "iam:GetPolicyVersion", "iam:ListPolicyVersions"], [boundary]),
      allow(["iam:PassRole"], [appRoles, `arn:aws:iam::${account}:role/cdk-${BOOTSTRAP_QUALIFIER}-cfn-exec-role-${account}-${region}`], { StringEquals: { "iam:PassedToService": ["lambda.amazonaws.com", "cloudformation.amazonaws.com"] } }),
      allow(["sts:AssumeRole", "sts:TagSession", "sts:SetSourceIdentity"], [bootstrapRoles]),
    ],
  };
  if (JSON.stringify(policy).length > 6144) throw new Error("Policy exceeds the IAM managed-policy size limit.");
  return policy;
}

export function scopedBootstrap(template: any) {
  const result = structuredClone(template);
  if (!result.Resources?.CloudFormationExecutionRole || !result.Resources?.StagingBucket || !result.Parameters?.BootstrapVariant) {
    throw new Error("Unexpected CDK bootstrap template; review it before updating the customization.");
  }
  const boundary = { "Fn::Sub": `arn:\${AWS::Partition}:iam::\${AWS::AccountId}:policy/${BOUNDARY_POLICY_NAME}` };
  for (const resource of Object.values(result.Resources) as any[]) {
    if (resource.Type === "AWS::IAM::Role") resource.Properties.PermissionsBoundary = boundary;
  }
  result.Resources.CloudFormationExecutionRole.Properties.ManagedPolicyArns = [boundary];
  result.Parameters.BootstrapVariant.Default = "Tempo: bounded deployment v1";
  result.Parameters.Qualifier.Default = BOOTSTRAP_QUALIFIER;
  result.Parameters.Qualifier.AllowedValues = [BOOTSTRAP_QUALIFIER];
  result.Parameters.InputPermissionsBoundary.Default = BOUNDARY_POLICY_NAME;
  result.Parameters.InputPermissionsBoundary.AllowedValues = [BOUNDARY_POLICY_NAME];
  result.Parameters.UseExamplePermissionsBoundary.AllowedValues = ["false"];
  result.Parameters.FileAssetsBucketKmsKeyId.Default = "AWS_MANAGED_KEY";
  result.Parameters.FileAssetsBucketKmsKeyId.AllowedValues = ["AWS_MANAGED_KEY"];
  // S3-managed encryption avoids creating an account-level KMS key or granting
  // broad KMS permissions. The asset bucket remains private and versioned.
  result.Resources.StagingBucket.Properties.BucketEncryption = {
    ServerSideEncryptionConfiguration: [{ ServerSideEncryptionByDefault: { SSEAlgorithm: "AES256" } }],
  };
  return result;
}
