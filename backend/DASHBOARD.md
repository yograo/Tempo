# Tempo owner dashboard

A private website for reviewing the existing feature-request table: search loaded requests, filter by status, read request details, update a status, and open a reply draft in your email app. Statuses are **New**, **Planned**, **In progress**, **Implemented**, and **Declined**. There is no automatic email sending or deletion control.

[Desktop preview with synthetic requests](../design/owner-dashboard.png).

Implementation verification: 93 automated tests pass; desktop rendering, search, and a status save were checked against the local preview. Managed Chrome then blocked the preview URL, so additional browser checks (including mobile and live Cognito) remain pending. No dashboard resources have been deployed yet.

## Architecture and access

The optional `TempoFeatureRequests-STAGE-Dashboard` stack contains:

- A separate API Gateway HTTP API with HTTPS website and admin routes on the same origin.
- A website Lambda serving the small HTML/CSS/JavaScript app and public OAuth configuration. This role has no request-data or Cognito permissions. No S3 website, CloudFront distribution, custom domain, or third-party frontend dependency is required.
- A Cognito user pool with self-registration disabled, administrator-only recovery, required TOTP authenticator MFA, and a public OAuth client using authorization code + S256 PKCE. The pool and its identities are retained on deletion; deletion protection is enabled.
- An admin Lambda with only `Scan` and `UpdateItem` data permissions on the explicitly named existing requests table. API Gateway verifies the token's issuer, audience/client ID, expiry and `openid` scope. The handler also requires an access token and exact `TempoOwners` group membership from trusted gateway claims. A valid login without this group cannot read data.

The stack imports the table by name. It makes no table changes and has no dependency on or changes to the public submission stack. Ordinary backend commands continue to synthesize only the submission stack unless `dashboardTable` is explicitly provided.

All roles use the existing deployment permissions boundary. The original public submission Lambda keeps its conditional, write-only `PutItem` grant. AWS administrators and identities with existing IAM table access retain that access; the dashboard is not isolation from your AWS account administrators.

The website and admin responses use `Cache-Control: no-store`; no customer data or tokens are stored in browser persistent storage. A one-time PKCE verifier/state transaction is kept in session storage until callback processing. The short-lived access token stays in memory for at most ten minutes; refresh and ID tokens are discarded. Reloading requires signing in again (Cognito can reuse its login session). Sign-out clears local data and ends the Cognito browser session. API Gateway validates JWTs offline: sign-out, group removal, disabling a user or Cognito token revocation does **not** instantly invalidate an already-issued access token; allow up to ten minutes for expiry. For urgent containment, disable the admin routes/Lambda as an AWS administrator.

Customer text is rendered with `textContent`, never HTML. A strict Content Security Policy, no-referrer policy, frame blocking and MIME protections are served with every asset. There are no cross-origin admin API grants, cookie-based API sessions, analytics, or payload/access logs. Application failures log only `feature_request_admin_failed`.

## Pagination and edits

`GET /admin/requests` returns `{items, nextCursor?}`. Each call scans at most 50 items / 1 MiB, with an optional UUID `cursor`. A scan has no global date ordering. Search, sorting and counts apply only to pages loaded in the browser; the UI says when more pages exist. `Load more` requests the next page. `Refresh` starts again. Even a strongly consistent scan is not a point-in-time snapshot across pages, so concurrent new submissions may require another refresh. This is suitable for a small owner inbox. For substantially larger volume, design an indexed server-side query/search path before increasing limits.

`PATCH /admin/requests/UUID` accepts only:

```json
{"status":"planned","revision":0}
```

Legacy rows without `revision` are interpreted as revision zero. An atomic conditional update checks that the item exists and its revision matches, changes only `status`, `revision`, and server-generated `updatedAt`, and returns the updated request. A conflict returns `409`; refresh before editing again. Retrying an uncertain update can produce a conflict if the first attempt succeeded. Original title, description, email, timestamp and app version remain unchanged. The app's existing idempotent submission retry still preserves the original record, including admin status changes.

Older rows without email display a no-email message. Current submissions still require email. Reply links open a local email draft and encode the mailbox/subject; they do not send, verify email ownership, or mark a request as replied.

## Local checks and preview

```sh
cd backend
npm ci
npm run check
npm audit --omit=dev
npm run preview:dashboard
# Open http://127.0.0.1:4173
```

The preview binds only to loopback and uses eight synthetic requests in memory. It does not load AWS credentials or contact production. Preview changes last until the preview server stops and are shared by its local tabs. The deployed website never enables preview mode. To preview the signed-out screen, stop the preview and run `TEMPO_PREVIEW_LOGIN=1 npm run preview:dashboard`; that fake Cognito configuration is for layout testing only.

Tests cover unauthorized and non-owner rejection, access-token type, request validation, bounded pagination, legacy rows, conditional update conflicts, PKCE state validation, token exchange, safe reply links, deployable bundles, and infrastructure permissions. Use a browser with sample data to verify search, pagination, status changes, empty/error/conflict states, and desktop/mobile layout. Do not take screenshots of real customer requests.

## Deploy in Ohio

The deployment policy needs Cognito permissions in addition to the existing services. Generate the concrete policy locally first:

```sh
export AWS_PROFILE=tempo
export AWS_REGION=us-east-2
export AWS_EC2_METADATA_DISABLED=true
cd backend
npm run build
TEMPO_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
npm run prepare-access -- "$TEMPO_ACCOUNT_ID" "$AWS_REGION"
cp cdk.out/deployment-policy.json cdk.out/dashboard-deployment-policy-us-east-2.json
```

As account owner, open **IAM → Policies → TempoFeedbackDeploymentBoundary → Edit → JSON**. Replace the JSON with the freshly generated `cdk.out/dashboard-deployment-policy-us-east-2.json`, review, and save it as the **default version**. The new grants allow creation of Cognito pools with the Tempo application tag, pool/client/domain/group administration restricted to Tempo-tagged pools in the chosen account and region, and regional domain-description reads. Existing permissions and role boundaries remain in place. The deployer cannot update this policy itself. No re-bootstrap or AWS Organizations change is needed.

Then resolve the live table rather than guessing a physical name and deploy only the dashboard stack:

```sh
TEMPO_REQUESTS_TABLE=$(aws cloudformation describe-stacks \
  --stack-name TempoFeatureRequests-prod \
  --query 'Stacks[0].Outputs[?OutputKey==`RequestsTableName`].OutputValue | [0]' \
  --output text)

npm run cdk -- diff TempoFeatureRequests-prod-Dashboard \
  -c stage=prod -c dashboardTable="$TEMPO_REQUESTS_TABLE" --method=template

npm run cdk -- deploy TempoFeatureRequests-prod-Dashboard \
  -c stage=prod -c dashboardTable="$TEMPO_REQUESTS_TABLE" \
  --outputs-file cdk-outputs.dashboard.prod.json
```

Review the diff first: it should create dashboard/auth resources, with **no DynamoDB table resource or replacement**. Deployment outputs are `DashboardUrl`, `UserPoolId`, `UserPoolClientId`, `AuthOrigin`, and `OwnerGroupName`. Use `DashboardUrl` directly; the Cognito callback/logout URL is the exact HTTPS origin followed by `/`. Secrets are not needed in website configuration. The output file is ignored by Git. Deployment is separate from merging a PR.

## Create your owner login

Once the stack has deployed, use your account administrator's **AWS Console → Cognito → User pools → TempoFeatureRequests-prod-owners** in Ohio:

1. Under **Users**, create a username (for example `owner`). Choose **Do not send an invitation** and set a temporary password privately. Email and phone attributes are unnecessary for this username/TOTP setup. Do not paste the password into chat, command history, or files in the repository.
2. Under **Groups → TempoOwners**, add only your owner user. Merely creating a user does not authorize request access.
3. Open the output `DashboardUrl`, choose **Sign in to Tempo**, enter the username and temporary password, set a permanent password, and enroll your authenticator app when Cognito prompts for TOTP MFA.
4. Confirm that the dashboard opens and that a synthetic request can be loaded and updated. Leave real customer data out of screenshots and diagnostics.

There are no automatic invitations or self-service password-recovery emails. If you lose your password/authenticator, use an AWS administrator to recover the Cognito account. Do not enable public signup to fix an owner-access problem.

## Production acceptance checks

After deployment, verify the website/configuration load over HTTPS and anonymous `GET /admin/requests` and `PATCH /admin/requests/UUID` return `401` without data. Verify a signed-in user outside `TempoOwners` receives `403`, and an owner can list and update a labeled synthetic request. Confirm a stale revision gives `409` and the original submitted fields stay intact. The original submission endpoint must still reject reads. Do not claim live authentication or deployment succeeded based solely on local mocks or a synthesized template.

This dashboard adds pay-per-request API/Lambda charges and Cognito active-user charges under the account's applicable plan. There are no always-on servers. API throttling is 5 requests/second with burst 15, shared by the site and admin routes; these are not a hard spending limit. Monitor actual usage before expanding access.
