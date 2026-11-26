# Tempo: guide for coding agents

Last reviewed: 2026-11-26. This file covers the iOS app and its deployed feature-request backend. Keep it current when changing architecture, API contracts, or deployment procedures. Use the checked-out source and live stack outputs to verify details that may have changed.

## Start here

- Repository: https://github.com/yograo/Tempo. Use `main` as the baseline for new work.
- Read [README.md](README.md) for app behavior and [backend/README.md](backend/README.md) for the complete API contract and AWS setup.
- Check `git status --short --branch` and `git worktree list` before editing. Development used separate app and backend worktrees; an old feature branch may contain only one part of the project. Preserve unrelated local changes.
- On the original development machine, `gh` defaults to a different GitHub host. Use `GH_HOST=github.com gh ...` for this repository.
- A GitHub merge, an AWS deployment, and an app installation are separate operations. Verify and report each one's actual state. Merging a PR does not deploy AWS or install the app.
- Do not put credentials, provisioning profiles, private keys, device identifiers, customer requests, or real email addresses in commits or logs. Read credentials through the existing local tools, never by printing credential files.

## Product behavior to preserve

Tempo is a native SwiftUI exercise timer for iPhone and iPad, targeting iOS 17+. Workouts, routines, and history work offline without an account. Feature requests use the network. The app currently has no third-party Swift dependencies.

- Routines contain exercise and rest intervals, support activity icons, and persist locally. New steps reuse the previous duration for their kind. Canceling an edit must not change those defaults.
- A workout starts with six seconds of preparation. Restart includes preparation again. The first exercise keeps its full duration.
- The workout screen uses landscape; returning to the library restores portrait. The timer keeps the screen awake while active.
- Spoken cues are on by default, can be disabled in Workout settings, and fall back to tones. Muting also silences scheduled workout alerts.
- The timer continues across backgrounding and locking by reconciling deadlines when execution resumes. Do not replace this with decrementing a counter every second or silent audio to keep the process alive.
- History records finished and early-ended workouts, actual active workout time, and skipped intervals. Active time includes rest but excludes preparation, pauses, and skipped time. Completion is recorded once, including recovery after termination.
- **Help shape Tempo** is the first section in **Workout settings**, above Audio. It opens **Request a feature**.
- The request form requires a title, details, and a reply email. Email was explicitly requested as mandatory; do not make it optional without a new product decision.
- Email is used for replies about the request. Ownership is not verified. Sending email is currently manual; there is no newsletter, SES integration, or automatic notification service.

### Lock Screen limitations

The Live Activity shows the overall workout countdown, not a potentially stale interval. Pause and skip controls remain in the app. At zero, reopening Tempo finalizes the display and saves history.

Local notifications provide interval and completion alerts while the app is suspended. Users enable them before starting a workout. Notification sounds obey silent mode, Focus, and notification settings; foreground cues use media volume. Notifications are not precision alarms. For long routines, schedule the next 63 interval alerts plus completion and refresh when the app reopens. Live Activities have an eight-hour system limit. Simulator checks do not establish physical-device notification audio or haptic behavior.

## Source map

| Location | Responsibility |
| --- | --- |
| `Tempo/Core/Routine.swift`, `RoutineFileStore.swift` | Routine models, validation, atomic JSON persistence |
| `Tempo/Core/WorkoutTimeline.swift`, `WorkoutCues.swift` | Deterministic timer, deadline reconciliation, cue scheduling |
| `Tempo/Core/WorkoutHistory.swift` | History records, active checkpoint, deduplication, persistence |
| `Tempo/App/RoutineStore.swift`, `WorkoutStore.swift` | Observable stores and workout lifecycle |
| `Tempo/Timer/` | Controller, local alerts, Live Activity orchestration |
| `Tempo/Audio/` | Tone playback, foreground speech, generated speech files for alerts |
| `Shared/TempoActivityAttributes.swift`, `TempoActivity/` | Shared ActivityKit data and widget extension |
| `Tempo/Core/FeatureRequest*.swift` | Request validation, HTTP client, durable composer, draft storage |
| `Tempo/App/FeatureRequestSetup.swift` | Production wiring and debug-only UI-test sender |
| `Tempo/UI/` | SwiftUI screens and shared styling in `Theme.swift` |
| `scripts/generate_project.py` | Xcode project, app icon, and WAV generation |
| `Tests/TempoCoreTests/`, `TempoUITests/` | Core and simulator UI tests |
| `backend/src/submit.ts`, `storage.ts`, `handler.ts` | Server validation, conditional DynamoDB writes, Lambda wiring |
| `backend/lib/feedback-stack.ts` | CDK API, Lambda, table, runtime permissions, alarm |
| `backend/dashboard/`, `backend/src/site-handler.ts` | Owner website, PKCE sign-in, local-only synthetic preview |
| `backend/src/admin*.ts`, `backend/lib/dashboard-stack.ts` | Authenticated admin API and isolated dashboard/auth stack |
| `backend/lib/deployment-access.ts` | Scoped deployer policy and customized CDK bootstrap |
| `backend/scripts/` | WASM bundling, access-file generation, live smoke test |
| `.github/workflows/backend.yml` | Backend CI: install, checks, runtime dependency audit |

### Local data and request retry behavior

Production routines are in Application Support at `Tempo/routines.json`. History and the active workout checkpoint share `Tempo/history.json`. Preserve existing formats and identifiers when migrating data. Never silently replace an unreadable save with empty data.

The request draft is `Tempo/feature-request-draft.json`. It is excluded from backup and uses iOS file protection. Before the first network call, the composer saves the exact payload and a random UUID v4. While a submission is pending or uncertain, fields stay locked and retries reuse that saved payload and ID, even after relaunch or an app update. A matching `202` receipt clears the draft. Discard removes the local copy and does not retract anything already received by the backend.

If saving the pending payload fails, do not send. If the saved draft cannot be decoded, preserve it until the user explicitly discards it. Do not regenerate an ID for an uncertain retry, edit a pending payload in place, or show success without checking the receipt's ID and status.

## Building and checking the app

Use Xcode with a current iOS SDK and Swift 6 tooling for the package tests. The latest verified development build was version **1.1**, build **2**. Change shared build settings in the generator so the app and extension stay consistent.

```sh
# Run from the repository root.
swift test --disable-swift-testing

# Regenerate after adding/removing Swift files or changing generated project settings.
python3 scripts/generate_project.py

xcrun simctl list devices available
xcodebuild -project Tempo.xcodeproj -scheme Tempo \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -derivedDataPath build CODE_SIGNING_ALLOWED=NO build

# Target the affected tests; choose an available simulator on this machine.
xcodebuild -project Tempo.xcodeproj -scheme Tempo \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -derivedDataPath build CODE_SIGNING_ALLOWED=NO \
  -only-testing:TempoUITests/FeatureRequestUITests test
```

The generator uses only Python's standard library. Generated Xcode project files and resources are committed. Inspect the diff after generation; avoid unrelated resource changes.

UI tests use `-ui-testing`, isolated routine/history files, and a debug-only fake request sender. They must not upload requests to the live API. `-preserve-routines` preserves test routines/history and `-preserve-feature-request` preserves the test draft across relaunch. `-feature-request-fail-once` simulates an uncertain submission. Never pass test-reset flags when launching the user's normal phone installation.

For UI edits, inspect actual simulator screenshots, not just compilation results. Tests attach screenshots to the `.xcresult` bundle; export with `xcrun xcresulttool export attachments --path <result> --output-path <directory>`. Keep useful design captures under `design/`. The details input is a multiline `TextField`. Use accessibility identifiers and dismiss the keyboard between fields when UI-test taps would otherwise hit the keyboard.

Last verified baseline: **44 core tests**, the form validation/success and relaunch/retry UI checks, and a spoken-cue/history regression check passed. The full historical UI suite was not rerun for every small edit. Run checks appropriate to the change and report their scope accurately.

### Installing on a physical device

List devices and use the currently attached device ID rather than copying an old one:

```sh
xcrun devicectl list devices
security find-identity -v -p codesigning

# Set TEMPO_DEVICE_ID and TEMPO_TEAM_ID from the intended device and signing team.
xcodebuild -project Tempo.xcodeproj -scheme Tempo -configuration Debug \
  -destination "platform=iOS,id=$TEMPO_DEVICE_ID" \
  -derivedDataPath /tmp/tempo-device-build DEVELOPMENT_TEAM="$TEMPO_TEAM_ID" build

xcrun devicectl device install app --device "$TEMPO_DEVICE_ID" \
  /tmp/tempo-device-build/Build/Products/Debug-iphoneos/Tempo.app
xcrun devicectl device process launch --device "$TEMPO_DEVICE_ID" com.yograo.tempo
```

Bundle identifiers are `com.yograo.tempo` and `com.yograo.tempo.activity`. Configure the intended Apple team for both targets. The original machine had an organization development identity available; that is not evidence of a personal Tempo developer membership. Do not hardcode its signing identity or silently change teams for distribution/App Attest. Preserve the user's existing app data when updating.

## Backend contract and security

The public submission route is `POST /v1/feature-requests`, using HTTPS and JSON. All five input fields are required:

| Field | Validation |
| --- | --- |
| `requestId` | UUID v4, normalized lowercase; one ID per submission |
| `title` | Trimmed, single line, 3–120 Unicode code points |
| `description` | Trimmed, 10–4,000 Unicode code points; permits line breaks and tabs |
| `appVersion` | Numeric version such as `1.1` or `1.1.2`, at most 32 characters |
| `email` | Common ASCII address, at most 254 characters; local part at most 64, domain labels at most 63; plus addressing allowed, only domain lowercased |

Swift validation counts `unicodeScalars`, corresponding to the server's `Array.from(text).length`; Swift grapheme count is different. The body limit is 24 KiB. Reject unknown fields, malformed JSON/Unicode, unsupported encodings, and invalid emails. Add `createdAt` and `status: "new"` on the server, not from client input. Older stored records can lack email; current submissions cannot.

A new submission or duplicate retry returns only `202 {"requestId":"...","status":"received"}`. Never return an old request or email to a caller. See [backend/README.md](backend/README.md) for error statuses.

- The API currently has **no user authentication**: API Gateway authorization is `NONE`. Email is not an authenticated identity. The endpoint cannot prove that a caller is Tempo.
- There are no public reads, edits, or deletes. Owner review uses AWS IAM. Authorized account administrators and deployment identities may also have access; this is not cryptographic isolation from AWS administrators.
- The Lambda's data permission is `dynamodb:PutItem` on its own table, with `dynamodb:ReturnValues = NONE`. This also restricts old values from conditional failures. Preserve both that IAM condition and the handler's conditional `attribute_not_exists` write. `PutItem` alone is not an immutability guarantee if the handler were compromised.
- Do not log request content, email, client headers, IPs, or SDK exceptions. Application write failures use a static marker. API access logs are disabled; Lambda logs expire after 30 days.
- DynamoDB encryption, point-in-time recovery, retention on stack deletion, and deletion protection are enabled. Preserve user data. Do not remove a retained table merely to unblock deployment; inspect its provenance and contents first and resolve any real-data deletion with the owner.
- The API's global throttle is approximately 1 request/second with burst 5. Table maximum read/write request units are 25 each; Lambda has 128 MiB and a five-second timeout. These are not a hard spending cap or comprehensive abuse prevention.
- The iOS client uses an ephemeral session, has no embedded AWS credentials/shared API key, and refuses redirects. Keep request contents out of networking logs and caches.

### Owner dashboard

See [backend/DASHBOARD.md](backend/DASHBOARD.md) for setup and operation. The new `TempoFeatureRequests-STAGE-Dashboard` stack is enabled only with `-c dashboardTable=EXISTING_TABLE_NAME`; select this stack explicitly when deploying it. It imports the table by name and must never replace the production submission stack/table. The dashboard deployed successfully in Ohio on 2026-11-26 at https://yvofsdc4wb.execute-api.us-east-2.amazonaws.com/. The reviewed Cognito policy is applied (default version v5). The owner account is confirmed and enabled, and its `TempoOwners` membership was verified. The first login was denied because the group was empty; membership is now assigned, and the owner must sign in again to obtain a token with that group. Successful dashboard access after this change remains to be confirmed. Live anonymous/invalid-token checks passed, and IAM-invoked deployed-handler tests passed for group rejection, listing, status updates and stale edits; the temporary sample row was removed.

The website is served by a separate Lambda/HTTP API. Its role has no data access. Cognito uses a closed username pool, required authenticator TOTP MFA, authorization-code PKCE, and administrator-only recovery. Only access tokens with exact `TempoOwners` membership may invoke admin storage; API Gateway verifies JWT issuer/client/expiry and the `openid` scope. Owner accounts must be created deliberately with invitations suppressed; do not send emails or retrieve owner credentials. The owner enrolls MFA manually.

Admin permissions are only `Scan`/`UpdateItem` on the existing table. Reads are bounded to 50 rows/1 MiB per page; the client filters/sorts/counts loaded rows and explicitly marks partial results. Scan pagination is not a point-in-time snapshot. Status changes allow `new`, `planned`, `in_progress`, `implemented`, `declined`, compare the current revision atomically (missing revision = 0), and update only status/revision/updatedAt. A `409` requires refresh. Preserve submitted text/email and support older records without email. There is no dashboard delete route or automatic email sending.

Access tokens and request data stay in browser memory; only the one-time PKCE transaction is placed in session storage. Tokens expire after ten minutes. Offline JWT validation means revocation, sign-out or group changes can take up to that expiry to remove API access. The site uses no-store responses, strict CSP, text-only rendering of customer content, no third-party scripts and no payload/access logging. Never screenshot real requests. `npm run preview:dashboard` serves synthetic data only on `127.0.0.1:4173`; the deployed config always disables preview mode.

The generated deployment policy adds Cognito creation gated by the Tempo tag and management of tagged pools in the assigned account/region. Updating the boundary is an owner action, not an agent credential escalation. Use a freshly named generated policy file, and verify the saved default policy version. Do not re-bootstrap for this update.

### Discussed but not implemented

Apple App Attest, per-install quotas, iOS user login, verified email ownership, and automatic email replies are not implemented. The optional owner web dashboard is implemented separately; verify its deployment state before claiming it is live. Do not report them as existing protections. App Attest requires client and server verification work, a deliberate Apple signing-team choice, and physical-device testing. TestFlight/App Store attestation uses production even when development used the sandbox. Merely adding an entitlement does not protect this API.

## Building and checking the backend

Node.js **24** is required. Use the pinned lockfile and the public npm registry configured in `backend/.npmrc`.

```sh
cd backend
npm ci
npm run check
npm audit --omit=dev
```

`check` compiles TypeScript, bundles Lambda, runs tests, and synthesizes CDK. The last verified baseline is **93 tests**. Tests cover validation, required email, conditional writes, cold-start loading of the bundle, and infrastructure permissions.

The bundler is `esbuild-wasm`: native esbuild was killed on the original machine. Lambda is a bundled CommonJS artifact with its own `dist/lambda/package.json`; retain the cold-start test. CDK has a documented build-only `minimatch` advisory, absent from the Lambda bundle. Do not blindly run `npm audit fix --force`: the suggested downgrade previously broke CDK. Respect any configured dependency release-age delay rather than overriding it. npm may also warn about the pinned Smithy version’s custom-logger redaction bug; this backend has no custom AWS SDK logger. Reassess dependency upgrades separately and do not introduce request logging.

## AWS operations

The deployed environment uses the local CLI profile **`tempo`** and **`us-east-2` (Ohio)**. The original account uses AWS's new project-based experience, which assigns a region and manages organization policies. Deploying in `us-west-2` was denied by an SCP. Check **AWS Settings → Projects → project → Overview → Additional Info → Region** before changing regions. Enabling advanced features is not needed for the existing backend; it is irreversible and removes project spend limits.

| Resource | Identifier |
| --- | --- |
| API stack | `TempoFeatureRequests-prod` |
| Dedicated bootstrap stack | `TempoCDKToolkit` |
| Bootstrap qualifier | `tempofb` |
| Managed deployment/boundary policy | `TempoFeedbackDeploymentBoundary` |
| Bootstrap version parameter | `/cdk-bootstrap/tempofb/version` |
| Public submission URL | `https://b9rd3v0sc5.execute-api.us-east-2.amazonaws.com/v1/feature-requests` |

The URL is public, not a secret. Verify it against stack outputs before changing clients. `FeatureRequestClient.endpoint` contains the app's URL. Physical table/role names are generated; obtain them from CloudFormation rather than inventing names or relying on an old failed deployment.

```sh
export AWS_PROFILE=tempo
export AWS_REGION=us-east-2
export AWS_EC2_METADATA_DISABLED=true
aws sts get-caller-identity
aws cloudformation describe-stacks --stack-name TempoFeatureRequests-prod \
  --query 'Stacks[0].Outputs' --output json
```

Do not print AWS credential files or paste access keys into chat. Account IDs can be derived from STS; do not embed them in generic configuration. Output files, generated access policies, `cdk.out`, `dist`, and environment files are git-ignored.

### Existing deployment updates

The dedicated bootstrap is already deployed. Do not bootstrap the default `CDKToolkit` as part of ordinary updates.

```sh
# From backend/, with the AWS environment above.
npm run build
npm run cdk -- diff -c stage=prod --method=template
npm run cdk -- deploy -c stage=prod --outputs-file cdk-outputs.prod.json
```

Review resource replacements and IAM changes before applying a deployment. A request-schema change should normally update Lambda code, not replace the requests table. `stage` defaults to `dev`; specify `-c stage=prod` for the existing production API. Merging or pushing does not auto-deploy.

`npm run cdk` includes the custom toolkit name. Some CLI versions warn that `diff` ignores that option; the stack synthesizer's `tempofb` qualifier still selects the correct asset/role names. Do not switch qualifiers in response to that warning.

### Bootstrap and permission troubleshooting

For a new account or a deliberate permission update, follow [backend/README.md](backend/README.md). `npm run prepare-access -- ACCOUNT_ID REGION` only creates local `cdk.out/deployment-policy.json` and `cdk.out/tempo-bootstrap.json`.

The owner creates/updates the managed policy in IAM and attaches it to the deployer. It is also the permissions boundary on every bootstrap role and the app runtime role, and the execution policy for CloudFormation. The deployer cannot change the boundary policy itself. Do not try to elevate the agent's credentials when access is denied.

Use the generated custom bootstrap template, qualifier `tempofb`, policy `TempoFeedbackDeploymentBoundary`, and `--bootstrap-kms-key-id AWS_MANAGED_KEY` as documented. The custom template uses a private S3-managed-encryption artifact bucket and avoids CDK's default administrator execution policy. Most permissions are resource-scoped; API Gateway management covers the chosen region because AWS assigns API IDs.

Two real deployment issues to remember:

1. Editing an IAM policy must update its **default version** and all regional resource references. An editor previously showed stale `us-west-2` JSON. Verify the policy version and contents through AWS rather than assuming a save changed them; use a newly named generated file if necessary.
2. Tagged HTTP API stage creation required **`apigateway:TagResource` on `/apis/*/stages`**, in addition to API Gateway HTTP-method permissions. The generator includes this after an observed `CreateStage` denial. Do not remove it just because a generic action reference lists tagging under `PATCH`.

If creation rolls back, inspect stack events and retained resources before retrying. A `ROLLBACK_COMPLETE` stack may need removal, and its retained DynamoDB table may still exist. The original empty table from a failed attempt was verified empty and removed; it is not the current live table. Never confuse that cleanup with permission to delete production requests.

### Live verification and owner review

```sh
# This creates one labeled synthetic request; it is not a read-only health check.
npm run smoke -- 'https://b9rd3v0sc5.execute-api.us-east-2.amazonaws.com/v1/feature-requests'
```

The smoke test verifies submission, immutable retries, required-email validation, and blocked public reads. Use the printed UUID to fetch only that test item through the owner's AWS identity and confirm the original title/email. Do not scan real user content unnecessarily. Clean up only identified synthetic test records when appropriate; do not delete user requests or tables as test cleanup. Existing labeled smoke-test records may remain for owner inspection.

The owner reads requests in **AWS Console → DynamoDB (Ohio) → Tables → output table name → Explore table items**. The `email` field supports manual replies. IAM read access is separate from the public API; no app user receives it.

The error alarm currently has no notification subscription. Configure budgets/notifications when requested and verify their actual state; do not claim that a hard cost cap, automatic alert email, or background monitoring is active merely because an alarm resource exists.

## Git and review workflow

Keep changes reviewable, preserve user work, and update docs with behavior changes. Run appropriate checks once; repeat them for changes, failures, or unresolved concerns rather than as a ritual. Use reserved test email domains such as `example.com` or `.test`. Some workstation Git privacy hooks treat uppercase or malformed synthetic domains differently; use documented allowed test values rather than disabling checks or committing real contact details.

For stacked PRs, merge the parent first and retarget the child to `main` before merging it. Preserve commit ancestry when a child depends on its parent's branch. Check the actual PR state and head SHA before merging, and honor repository checks/reviews. Once merged, fast-forward the main checkout and verify the combined code. Prior feature work is recorded in PRs #1 (workout features), #2 (backend), and #3 (request form); their old branches are not the source of truth for future work.
