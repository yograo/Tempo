# Tempo feature-request API

A public submission endpoint for Tempo users, with a required reply email, backed by API Gateway HTTP API, a Node.js 24 Lambda, and DynamoDB. This folder is independent of the iOS app.

## API contract

`POST /v1/feature-requests` with `Content-Type: application/json`:

```json
{
  "requestId": "49e327d4-630d-4f58-8de9-65a34e4d03ad",
  "title": "Repeat exercise blocks",
  "description": "Please let me repeat a group of exercises five times.",
  "appVersion": "1.0",
  "email": "you@example.com"
}
```

Generate a random UUID v4 **once per submission** and reuse it when retrying. Swift's `UUID().uuidString` is accepted and normalized to lowercase. A successful write or retry returns the same `202 Accepted` receipt:

```json
{
  "requestId": "49e327d4-630d-4f58-8de9-65a34e4d03ad",
  "status": "received"
}
```

No request text or previously stored data is returned. Reusing an ID with different text preserves the first submission; a new idea needs a new ID.

| Field | Rules |
| --- | --- |
| `requestId` | Required random UUID v4; case-insensitive |
| `title` | Required single line, 3–120 Unicode characters after trimming |
| `description` | Required, 10–4000 Unicode characters after trimming; newlines and tabs allowed |
| `appVersion` | Required numeric version, such as `1`, `1.0`, or `1.2.3`; at most 32 characters |
| `email` | Required reply address; missing and blank values are rejected. At most 254 characters, a local part of at most 64 characters, and domain labels of at most 63. Common ASCII mailboxes and plus addressing are supported; only the domain is lowercased. |

Email is required for new submissions; older stored records may not have it.

Unknown fields are rejected. The complete UTF-8 body must be at most 24 KiB; compressed bodies are unsupported. The server adds `createdAt` (UTC ISO 8601) and `status: "new"`.

| HTTP status | Client behavior |
| --- | --- |
| `202` | Submission received; clear the draft |
| `400` | Fix invalid JSON or fields; retain the draft |
| `413` | Reduce the body size |
| `415` | Use uncompressed UTF-8 JSON |
| `429` | Back off and retry with the same ID |
| `503` or network timeout | Retry with the same ID; Lambda responses include `Retry-After: 5` |

Application errors have the shape `{"error":{"code":"invalid_request","message":"..."}}`. Gateway-generated errors, including throttling and unknown routes, can use AWS's `{"message":"..."}` shape. Clients should use the HTTP status rather than rely on one error shape.

There are **no public GET, list, update, or delete routes**, no client login, and no API key to embed in the app. The public endpoint can be called by anyone; it does not attest that a submission came from an installed copy of Tempo. The reply email is stored privately with its request and is never echoed in the response or logged. No device IDs, IP addresses, or user-agent strings are stored with submissions. Users can still voluntarily put personal information in their free-text requests. Email ownership and deliverability are not verified; the address is for manual replies about that request, not a subscription. This API does not send email.

## Build and test

Requires Node.js 24 and npm. Building, testing, and synthesizing the CloudFormation template don't require AWS credentials:

```sh
cd backend
npm ci
npm run check
```

The check builds the Lambda with its pinned AWS SDK dependency, tests validation, retries, error handling and data privacy, tests the synthesized AWS permissions, and synthesizes the deployment. The bundler uses WebAssembly so development doesn't depend on a platform-specific native executable.

`npm audit --omit=dev` audits dependencies shipped in Lambda. CDK currently bundles a version of `minimatch` affected by a build-time glob denial-of-service advisory; it is not included in the Lambda bundle, and this project uses fixed, repository-controlled asset paths. Avoid force-downgrading CDK to npm audit's suggested incompatible version. No custom AWS SDK logger is configured; application errors are logged only as the static marker `feature_request_write_failed`.

## Deploy to your AWS account

Keep credentials in your AWS CLI setup; never put them in this repository. Root-account access keys are unnecessary. An administrator must first create and attach the scoped deployment policy described below; the deployment user cannot grant itself permissions.

For AWS's new project-based experience, first check **AWS Settings → Projects → your project → Overview → Additional Info → Region**. Use that assigned region for the CLI profile, policy generation, and deployment. US-based projects normally use `us-east-2` (Ohio); the example below uses that region. These accounts have AWS-managed organization policies that can reject deployment in other regions even when IAM allows it. The services used by this API are supported in the new experience; enabling advanced features is not required just to deploy them in the assigned region. See [AWS project regions](https://docs.aws.amazon.com/accounts/latest/reference/project-regions.html) and [supported services](https://docs.aws.amazon.com/accounts/latest/reference/supported-services-sign-up-new.html).

```sh
export AWS_PROFILE=tempo
export AWS_REGION=us-east-2
aws sts get-caller-identity

cd backend
npm ci
npm run build

TEMPO_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
npm run prepare-access -- "$TEMPO_ACCOUNT_ID" "$AWS_REGION"
```

The last command only writes local files; it does not change AWS permissions. In the AWS console, signed in as an account administrator:

1. Open **IAM → Policies → Create policy → JSON** and paste `backend/cdk.out/deployment-policy.json`.
2. Name the policy **TempoFeedbackDeploymentBoundary** exactly, then create it.
3. Open **IAM → Users → your deployment user → Permissions → Add permissions → Attach policies directly**. Select **TempoFeedbackDeploymentBoundary** and add it as a permission policy.

If initial setup used the wrong region and nothing has been deployed yet, regenerate the files for the assigned region. Open **IAM → Policies → TempoFeedbackDeploymentBoundary → Edit → JSON**, replace the contents with the regenerated policy, and save it as the default version. The existing user attachment continues to apply; no new policy or access keys are needed.

This policy grants deployment and owner review permissions for Tempo's stacks, tables, functions, logs, alarms, IAM roles/policies, and dedicated CDK asset resources. HTTP API and API Gateway tag management covers the selected region because API IDs are assigned by AWS; some validation, authentication, and listing operations require `Resource: "*"`. It is not an account administrator policy. It does not grant IAM user management, removal of role boundaries, or modification of the boundary policy itself. Existing permissions on the deployment user are left unchanged.

The policy also acts as a permissions ceiling on **all** newly created bootstrap roles and the Lambda runtime role. The runtime's actual permissions remain only DynamoDB conditional writes and logging. The generated bootstrap template replaces CDK's default administrator execution policy and uses S3-managed encryption for the private artifact bucket.

Tagged HTTP API stage creation checks `apigateway:TagResource` on `/apis/API_ID/stages` in addition to the usual API Gateway HTTP-method permissions. The generated policy includes this grant for stage collections in the selected region. This additional check was observed during deployment; granting only `apigateway:POST` and `apigateway:PATCH` did not satisfy it.

After the administrator attaches the policy, use the dedicated Tempo bootstrap:

```sh
TEMPO_BOUNDARY_ARN="arn:aws:iam::${TEMPO_ACCOUNT_ID}:policy/TempoFeedbackDeploymentBoundary"
npm run cdk -- bootstrap "aws://${TEMPO_ACCOUNT_ID}/${AWS_REGION}" \
  --template cdk.out/tempo-bootstrap.json \
  --qualifier tempofb \
  --custom-permissions-boundary TempoFeedbackDeploymentBoundary \
  --cloudformation-execution-policies "$TEMPO_BOUNDARY_ARN" \
  --bootstrap-kms-key-id AWS_MANAGED_KEY

# Review the new resources and IAM changes before deployment.
npm run cdk -- diff -c stage=prod
npm run cdk -- deploy -c stage=prod --outputs-file cdk-outputs.prod.json
```

`stage` must be `dev` or `prod`; it defaults to `dev`. Each stage gets a separate stack, table, function, and URL. There is no custom domain, VPC, NAT gateway, server, or account/auth service to operate. Output files and CDK build artifacts are git-ignored.

The `npm run cdk` command selects **TempoCDKToolkit**, with qualifier **tempofb**, so other applications' CDK bootstrap stacks are untouched. Use the generated custom bootstrap template rather than the stock CDK template; the generated variant requires the boundary on every role. `prepare-access` currently supports US commercial regions. The dedicated bootstrap creates a private file bucket and the standard, initially empty CDK container repository; this API uses only file assets.

The deployment outputs include:

- `SubmissionUrl`: the URL for the iOS app's POST request.
- `ApiUrl`: the API's base URL.
- `RequestsTableName`: the private DynamoDB table to review.
- `OwnerReaderPolicyArn`: a read-only IAM policy that is **not attached automatically**.
- `LambdaRoleArn`: the runtime role, for permission verification.

After deployment, test the live endpoint:

```sh
npm run smoke -- 'https://API_ID.execute-api.REGION.amazonaws.com/v1/feature-requests'
```

Each run intentionally writes **one labeled test request**, retries it with changed text and email, checks validation, and checks that GET doesn't expose data. Using your AWS identity, verify that the reported request ID has the original title and email in DynamoDB. The test row can be deleted through your authorized AWS identity afterwards; the API cannot delete it.

## Private owner review

Sign in to your AWS account and open **DynamoDB → Tables → the output table name → Explore table items**. If your identity needs permission, attach the output `OwnerReaderPolicyArn` only to your personal IAM identity. It grants table listing plus `DescribeTable`, `GetItem`, `Query`, and `Scan` on this table. Existing AWS account administrators retain their normal access.

The Lambda runtime role has only `dynamodb:PutItem` on this table, plus Lambda logging permissions. An IAM `dynamodb:ReturnValues = NONE` condition also prevents it from reading old items through a write or conditional-write failure. The handler explicitly requests no old values. The role has no DynamoDB read, update, or delete actions. An infrastructure test asserts this boundary. This follows [AWS's documented condition for restricting returned values](https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/transaction-apis-iam.html).

API access logging is disabled, and application logs contain no request bodies, SDK exceptions, or client metadata. Lambda logs expire after 30 days. The CloudWatch `SubmissionFailures` alarm becomes visible in the console when the API returns five server errors within five minutes; attach an alarm action if you want notifications. No email/SNS subscriptions are created automatically.

## Operations and costs

The API starts at **1 request/second with a burst of 5**. DynamoDB uses on-demand billing with maximum read/write throughput of 25 units/second, and Lambda has a five-second timeout. These are capacity controls, not a hard spending cap. Set an AWS Billing budget notification for your desired monthly amount before a public release; an AWS budget alerts rather than automatically stopping charges.

DynamoDB point-in-time recovery and deletion protection are enabled. Stack deletion retains the table and its requests; retained storage/backups can continue to incur charges. Deleting stored user requests is an owner action in AWS, not a public API capability. Keep the table until you explicitly decide to remove its data.
