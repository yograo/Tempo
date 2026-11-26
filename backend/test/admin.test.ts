import assert from "node:assert/strict";
import { test } from "node:test";
import type { APIGatewayProxyEventV2WithJWTAuthorizer } from "aws-lambda";
import { createAdminHandler, ConflictError, isOwner } from "../src/admin.js";
const id = "00000000-0000-4000-8000-000000000001";
const claims = { sub: "test-owner", token_use: "access", "cognito:groups": "[TempoOwners]" };
function event(overrides: Record<string, unknown> = {}) {
  return { rawPath: "/admin/requests", headers: {}, requestContext: { http: { method: "GET" }, authorizer: { jwt: { claims } } }, ...overrides } as unknown as APIGatewayProxyEventV2WithJWTAuthorizer;
}
function setup() {
  const calls: unknown[] = [];
  const handler = createAdminHandler({ list: async (cursor) => { calls.push(cursor); return { items: [] }; },
    update: async (...args) => { calls.push(args); return { requestId: id, title: "Test", description: "A test request", appVersion: "1.1", createdAt: "2026-11-26T12:00:00.000Z", status: args[1], revision: args[2] + 1 }; },
    reportFailure: () => { calls.push("failure"); } });
  return { handler, calls };
}
function patch(body: unknown, overrides: Record<string, unknown> = {}) {
  return event({ rawPath: `/admin/requests/${id}`, headers: { "content-type": "application/json" }, body: JSON.stringify(body),
    requestContext: { http: { method: "PATCH" }, authorizer: { jwt: { claims } } }, ...overrides });
}
test("only complete owner group names and access tokens pass", () => {
  for (const groups of [["TempoOwners"], '["TempoOwners"]', '[Other, TempoOwners]', 'TempoOwners']) assert.equal(isOwner({ ...claims, "cognito:groups": groups }), true);
  for (const groups of [undefined, "", "NotTempoOwners", "[TempoOwnersExtra]", '["Owner"]', { TempoOwners: true }]) assert.equal(isOwner({ ...claims, "cognito:groups": groups }), false);
  assert.equal(isOwner(undefined), false);
  assert.equal(isOwner({ ...claims, token_use: "id" }), false);
  assert.equal(isOwner({ ...claims, sub: "" }), false);
});
test("missing claims and forged body/header group membership cannot invoke storage", async () => {
  const { handler, calls } = setup();
  for (const ctx of [{ http: { method: "GET" } }, { http: { method: "GET" }, authorizer: { jwt: { claims: { ...claims, "cognito:groups": "[Other]" } } } }]) {
    const result = await handler(event({ requestContext: ctx, headers: { authorization: "Bearer forged", "cognito:groups": "TempoOwners" }, body: JSON.stringify(claims) }));
    assert.equal(result.statusCode, 403); assert.equal(result.headers?.["cache-control"], "no-store");
  }
  assert.deepEqual(calls, []);
});
test("list validates cursors and query fields before reads", async () => {
  const { handler, calls } = setup();
  for (const params of [{ cursor: "bad" }, { cursor: "" }, { limit: "10000" }]) assert.equal((await handler(event({ queryStringParameters: params }))).statusCode, 400);
  assert.deepEqual(calls, []);
  assert.equal((await handler(event({ queryStringParameters: { cursor: id } }))).statusCode, 200);
  assert.deepEqual(calls, [id]);
});
test("status updates require a known status, safe revision and no submitted-field changes", async () => {
  const { handler, calls } = setup();
  for (const body of [null, [], {}, { status: "new" }, { status: "unknown", revision: 0 }, { status: "new", revision: -1 }, { status: "new", revision: 0.5 }, { status: "new", revision: Number.MAX_SAFE_INTEGER }, { status: "planned", revision: 0, email: "edited@example.com" }]) {
    assert.equal((await handler(patch(body))).statusCode, 400);
  }
  assert.deepEqual(calls, []);
  const result = await handler(patch({ status: "planned", revision: 0 }));
  assert.equal(result.statusCode, 200); assert.equal(JSON.parse(result.body!).revision, 1);
  assert.deepEqual(calls, [[id, "planned", 0]]);
});
test("invalid routes, body size, encoding and JSON never write", async () => {
  const { handler, calls } = setup();
  assert.equal((await handler(patch({}, { rawPath: "/admin/requests/invalid" }))).statusCode, 404);
  assert.equal((await handler(patch({}, { headers: { "content-type": "text/plain" } }))).statusCode, 415);
  assert.equal((await handler(patch({}, { headers: { "content-type": "application/json", "content-encoding": "gzip" } }))).statusCode, 415);
  assert.equal((await handler(patch({}, { body: "{" }))).statusCode, 400);
  assert.equal((await handler(patch({}, { body: "x".repeat(1500) }))).statusCode, 413);
  assert.equal((await handler(patch({}, { body: Buffer.from([0xff]).toString("base64"), isBase64Encoded: true }))).statusCode, 400);
  assert.deepEqual(calls, []);
});
test("a conditional conflict is 409; storage failures expose no SDK details", async () => {
  let logs = 0;
  const handler = createAdminHandler({ list: async () => { throw new Error("private@example.com SDK details"); }, update: async () => { throw new ConflictError(); }, reportFailure: () => { logs++; } });
  assert.equal((await handler(patch({ status: "new", revision: 1 }))).statusCode, 409);
  assert.equal(logs, 0);
  const result = await handler(event()); assert.equal(result.statusCode, 503);
  assert.equal(result.body!.includes("private@example.com"), false); assert.equal(logs, 1);
});
