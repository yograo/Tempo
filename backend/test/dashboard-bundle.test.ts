import assert from "node:assert/strict";
import { createRequire } from "node:module";
import { test } from "node:test";
const require = createRequire(import.meta.url);
test("admin bundle cold-starts and denies an unauthenticated caller without touching AWS", async () => {
  process.env.REQUESTS_TABLE_NAME = "packaging-test-table";
  const admin = require("../admin-lambda/index.js");
  const response = await admin.handler({ rawPath: "/admin/requests", requestContext: { http: { method: "GET" } }, headers: {} });
  assert.equal(response.statusCode, 403);
});
test("website bundle serves assets, public configuration and restrictive security headers", async () => {
  process.env.AUTH_ORIGIN = "https://tempo-test.auth.us-east-2.amazoncognito.com";
  process.env.CLIENT_ID = "test-client";
  const site = require("../site-lambda/index.js");
  const get = (rawPath: string) => site.handler({ rawPath, requestContext: { http: { method: "GET" } } });
  for (const path of ["/", "/app.js", "/auth.js", "/model.js", "/style.css", "/config.json"]) {
    const response = await get(path); assert.equal(response.statusCode, 200, path);
    assert.equal(response.headers["cache-control"], "no-store");
    assert.equal(response.headers["referrer-policy"], "no-referrer");
    assert.match(response.headers["content-security-policy"], /frame-ancestors 'none'/);
    assert.doesNotMatch(response.headers["content-security-policy"], /unsafe-inline|unsafe-eval/);
  }
  assert.deepEqual(JSON.parse((await get("/config.json")).body), { authOrigin: process.env.AUTH_ORIGIN, clientId: "test-client", demo: false });
  assert.equal((await get("/../../package.json")).statusCode, 404);
  assert.equal((await get("/admin/requests")).statusCode, 404);
});
