import assert from "node:assert/strict";
import { test } from "node:test";
import { createAuthorization, validateCallback, exchangeCode } from "../dashboard/auth.js";
import { visibleRequests, mergePage, replyLink } from "../dashboard/model.js";
const config = { clientId: "test-client", authOrigin: "https://tempo-test.auth.us-east-2.amazoncognito.com" };
const redirect = "https://dashboard.example.com/";
test("sign-in uses random state and an S256 PKCE challenge with an exact callback", async () => {
  const a = await createAuthorization(config, redirect), b = await createAuthorization(config, redirect);
  assert.notEqual(a.transaction.state, b.transaction.state); assert.notEqual(a.transaction.verifier, b.transaction.verifier);
  const url = new URL(a.url); assert.equal(url.searchParams.get("redirect_uri"), redirect);
  assert.equal(url.searchParams.get("response_type"), "code"); assert.equal(url.searchParams.get("scope"), "openid");
  assert.equal(url.searchParams.get("code_challenge_method"), "S256");
  const digest = Buffer.from(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(a.transaction.verifier))).toString("base64url");
  assert.equal(url.searchParams.get("code_challenge"), digest); assert.equal(url.searchParams.has("client_secret"), false);
});
test("callback rejects missing/wrong/replayed parameters, stale state, and a changed origin", async () => {
  const { transaction } = await createAuthorization(config, redirect);
  const search = `?code=sample&state=${transaction.state}`;
  assert.equal(validateCallback(search, transaction, redirect), "sample");
  for (const query of ["?code=sample", "?code=sample&state=wrong", `${search}&state=${transaction.state}`, `${search}&code=other`, `?error=denied&state=${transaction.state}`]) assert.throws(() => validateCallback(query, transaction, redirect));
  assert.throws(() => validateCallback(search, undefined, redirect));
  assert.throws(() => validateCallback(search, transaction, "https://other.example.com/"));
  assert.throws(() => validateCallback(search, transaction, redirect, transaction.createdAt + 600_001));
});
test("token exchange sends the verifier, omits cookies and never returns refresh or ID tokens", async () => {
  const original = globalThis.fetch;
  globalThis.fetch = async (url, options) => {
    assert.equal(url.href, `${config.authOrigin}/oauth2/token`); assert.equal(options.credentials, "omit"); assert.equal(options.redirect, "error");
    assert.equal(options.body.get("code_verifier"), "sample-verifier"); assert.equal(options.body.get("redirect_uri"), redirect);
    return new Response(JSON.stringify({ access_token: "test-access", expires_in: 600, token_type: "Bearer", refresh_token: "ignore", id_token: "ignore" }));
  };
  try { const result = await exchangeCode(config, "code", { verifier: "sample-verifier", redirectUri: redirect }); assert.deepEqual(Object.keys(result).sort(), ["expiresAt", "token"]); }
  finally { globalThis.fetch = original; }
});
test("loaded search handles legacy email and sorts newest first", () => {
  const items = [{ requestId: "1", title: "Circuit", description: "Repeat", createdAt: "2026-11-25", status: "new" }, { requestId: "2", title: "Voice", description: "Cues", email: "runner@example.com", createdAt: "2026-11-26", status: "planned" }];
  assert.deepEqual(visibleRequests(items, "", "all").map((r) => r.requestId), ["2", "1"]);
  assert.deepEqual(visibleRequests(items, " RUNNER ", "planned").map((r) => r.requestId), ["2"]);
  assert.equal(visibleRequests(items, "missing", "all").length, 0);
});
test("pagination deduplicates IDs without overwriting a newer local revision", () => {
  const items = [{ requestId: "1", revision: 2, status: "planned" }];
  assert.deepEqual(mergePage(items, [{ requestId: "1", revision: 1, status: "new" }]), items);
  assert.equal(mergePage(items, [{ requestId: "2", revision: 0 }]).length, 2);
});
test("reply links cannot inject URI query headers or unsafe protocols", () => {
  const href = replyLink({ email: "hello?bcc=other@example.com", title: "Idea\r\nBcc: injected@example.com" });
  assert.equal(href, "mailto:hello%3Fbcc%3Dother%40example.com?subject=Your%20Tempo%20idea%3A%20Idea%20%20Bcc%3A%20injected%40example.com");
  assert.equal(replyLink({ email: "hello\r\n@example.com", title: "Idea" }), undefined);
  assert.equal(replyLink({ title: "Legacy" }), undefined);
});
