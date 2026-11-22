import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { test } from "node:test";
import type { APIGatewayProxyEventV2 } from "aws-lambda";
import { createSubmitHandler, MAX_BODY_BYTES, SUBMISSION_PATH, type FeatureRequest } from "../src/submit.js";

const payload = () => ({ requestId: randomUUID(), title: "Repeat exercise blocks", description: "Please let me repeat a group of exercises five times.", appVersion: "1.0" });
const timestamp = "2026-11-21T10:00:00.000Z";
function event(body: unknown = payload(), changes: Partial<APIGatewayProxyEventV2> = {}): APIGatewayProxyEventV2 {
  return {
    version: "2.0", routeKey: `POST ${SUBMISSION_PATH}`, rawPath: SUBMISSION_PATH, rawQueryString: "",
    headers: { "content-type": "application/json" },
    body: JSON.stringify(body), isBase64Encoded: false,
    requestContext: { accountId: "123456789012", apiId: "api", domainName: "example.execute-api.us-west-2.amazonaws.com",
      domainPrefix: "example", requestId: "gateway-id", routeKey: `POST ${SUBMISSION_PATH}`, stage: "$default",
      time: "", timeEpoch: 0, http: { method: "POST", path: SUBMISSION_PATH, protocol: "HTTP/1.1", sourceIp: "192.0.2.1", userAgent: "Tempo" } },
    ...changes,
  };
}
function setup() {
  const records = new Map<string, FeatureRequest>();
  let failures = 0;
  const handler = createSubmitHandler({
    write: async (request) => { if (!records.has(request.requestId)) records.set(request.requestId, request); },
    now: () => new Date(timestamp), reportWriteFailure: () => { failures++; },
  });
  return { handler, records, failures: () => failures };
}

test("accepts anonymous requests and returns only a receipt; stores no network metadata", async () => {
  const { handler, records } = setup();
  const input = payload();
  const result = await handler(event(input));
  assert.equal(result.statusCode, 202);
  assert.deepEqual(JSON.parse(result.body!), { requestId: input.requestId, status: "received" });
  assert.equal(result.headers?.["cache-control"], "no-store");
  assert.deepEqual(records.get(input.requestId), { ...input, createdAt: timestamp, status: "new" });
});

test("retries return the same receipt without changing the original submission", async () => {
  const { handler, records } = setup();
  const input = payload();
  const first = await handler(event(input));
  const retry = await handler(event({ ...input, title: "A different title" }));
  assert.deepEqual(retry, first);
  assert.equal(records.size, 1);
  assert.equal(records.get(input.requestId)?.title, input.title);
});

test("normalizes Swift UUID casing and trims text", async () => {
  const { handler, records } = setup();
  const input = payload();
  const result = await handler(event({ ...input, requestId: input.requestId.toUpperCase(), title: `  ${input.title}  ` }));
  assert.equal(result.statusCode, 202);
  assert.equal(records.get(input.requestId)?.title, input.title);
});

test("accepts Unicode text and multiline descriptions at the character limits", async () => {
  const { handler, records } = setup();
  const input = { ...payload(), title: "🏋️".repeat(40), description: "😀".repeat(4000) };
  assert.equal((await handler(event(input))).statusCode, 202);
  assert.equal(records.get(input.requestId)?.description, input.description);
  assert.equal((await handler(event({ ...payload(), description: "First idea.\nSecond line.\tMore detail." }))).statusCode, 202);
});

test("accepts API Gateway base64 bodies and Content-Type charset/casing", async () => {
  const { handler } = setup();
  const body = Buffer.from(JSON.stringify(payload())).toString("base64");
  const result = await handler(event(null, { body, isBase64Encoded: true, headers: { "Content-Type": "Application/JSON; charset=utf-8" } }));
  assert.equal(result.statusCode, 202);
});

for (const [name, value] of Object.entries({
  null: null, array: [], string: "hello", number: 42,
  missing: {}, unknownField: { ...payload(), email: "unneeded@example.com" },
  clientTimestamp: { ...payload(), createdAt: timestamp }, clientStatus: { ...payload(), status: "approved" },
  badID: { ...payload(), requestId: "not-a-uuid" }, nonV4ID: { ...payload(), requestId: "00000000-0000-1000-8000-000000000000" },
  blankTitle: { ...payload(), title: "   " }, longTitle: { ...payload(), title: "x".repeat(121) },
  multilineTitle: { ...payload(), title: "First\nSecond" }, invalidTitleType: { ...payload(), title: 123 },
  blankDescription: { ...payload(), description: "          " }, shortDescription: { ...payload(), description: "short" },
  longDescription: { ...payload(), description: "x".repeat(4001) }, controlCharacter: { ...payload(), description: "Do not save \u0000 this" },
  unpairedSurrogate: { ...payload(), description: "Invalid Unicode: \uD800" },
  invalidVersion: { ...payload(), appVersion: "1.0\nspoof" }, longVersion: { ...payload(), appVersion: "1".repeat(33) },
})) {
  test(`rejects ${name} without writing`, async () => {
    const { handler, records } = setup();
    assert.equal((await handler(event(value))).statusCode, 400);
    assert.equal(records.size, 0);
  });
}

test("rejects malformed JSON and non-UTF8 bytes", async () => {
  const { handler, records } = setup();
  assert.equal((await handler(event(null, { body: "{broken" }))).statusCode, 400);
  assert.equal((await handler(event(null, { body: Buffer.from([0xff, 0xfe]).toString("base64"), isBase64Encoded: true }))).statusCode, 400);
  assert.equal(records.size, 0);
});

test("limits decoded byte size for ordinary and base64 requests", async () => {
  const { handler, records } = setup();
  assert.equal((await handler(event(null, { body: "x".repeat(MAX_BODY_BYTES + 1) }))).statusCode, 413);
  assert.equal((await handler(event(null, { body: "😀".repeat(MAX_BODY_BYTES / 2) }))).statusCode, 413);
  const body = Buffer.alloc(MAX_BODY_BYTES + 1, 65).toString("base64");
  assert.equal((await handler(event(null, { body, isBase64Encoded: true }))).statusCode, 413);
  assert.equal(records.size, 0);
});

test("rejects non-JSON and compressed requests", async () => {
  const { handler, records } = setup();
  assert.equal((await handler(event(payload(), { headers: {} }))).statusCode, 415);
  assert.equal((await handler(event(payload(), { headers: { "content-type": "text/plain" } }))).statusCode, 415);
  assert.equal((await handler(event(payload(), { headers: { "content-type": "application/json", "content-encoding": "gzip" } }))).statusCode, 415);
  assert.equal(records.size, 0);
});

test("doesn't expose data through GET or an alternate path", async () => {
  const { handler, records } = setup();
  const get = event();
  get.requestContext.http.method = "GET";
  assert.equal((await handler(get)).statusCode, 405);
  assert.equal((await handler(event(payload(), { rawPath: "/v1/feature-requests/some-id" }))).statusCode, 404);
  assert.equal(records.size, 0);
});

test("storage failures produce retryable responses without disclosing or logging request data", async () => {
  let logged = 0;
  const handler = createSubmitHandler({
    write: async () => { throw new Error("sensitive submission text and infrastructure detail"); },
    now: () => new Date(timestamp), reportWriteFailure: (...args: unknown[]) => { assert.deepEqual(args, []); logged++; },
  });
  const response = await handler(event());
  assert.equal(response.statusCode, 503);
  assert.equal(response.headers?.["retry-after"], "5");
  assert.equal(logged, 1);
  assert.doesNotMatch(response.body!, /sensitive|infrastructure/);
});
