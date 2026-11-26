import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";

const endpoint = process.argv[2];
if (!endpoint) {
  console.error("Usage: npm run smoke -- https://API_ID.execute-api.REGION.amazonaws.com/v1/feature-requests");
  process.exit(1);
}
const url = new URL(endpoint);
if (url.protocol !== "https:" || !url.hostname.endsWith(".amazonaws.com") || url.pathname !== "/v1/feature-requests") {
  throw new Error("Use the HTTPS SubmissionUrl from this stack's deployment outputs.");
}

const payload = { requestId: randomUUID(), title: "API deployment smoke test",
  description: "Automated test submission. The owner can remove this entry after deployment.", appVersion: "1.0",
  email: "tempo-api-test@example.com" };

async function send(body, method = "POST") {
  // Respect the deliberately low public request rate.
  await new Promise((resolve) => setTimeout(resolve, 1200));
  const result = await fetch(url, {
    method,
    ...(method === "POST" ? { headers: { "content-type": "application/json" }, body: JSON.stringify(body) } : {}),
    signal: AbortSignal.timeout(15000),
  });
  return { status: result.status, body: await result.json() };
}

const first = await send(payload);
assert.equal(first.status, 202);
assert.deepEqual(first.body, { requestId: payload.requestId, status: "received" });
assert.deepEqual(await send(payload), first, "A retry must return the same receipt.");
assert.deepEqual(await send({ ...payload, title: "Must not overwrite the original", email: "different@example.com" }), first);
const invalid = await send({ ...payload, requestId: randomUUID(), title: "" });
assert.equal(invalid.status, 400);
assert.equal((await send({ ...payload, requestId: randomUUID(), email: "not-an-email" })).status, 400);
const { email: omittedEmail, ...withoutEmail } = payload;
assert.equal((await send({ ...withoutEmail, requestId: randomUUID() })).status, 400);
const read = await send(undefined, "GET");
assert.ok([403, 404, 405].includes(read.status), "There must be no public read endpoint.");
console.log(`Smoke test passed. Owner verification requestId: ${payload.requestId}`);
console.log("Verify through your AWS identity that exactly one row exists, with the original title, then delete the test row if desired.");
