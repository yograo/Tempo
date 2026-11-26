import assert from "node:assert/strict";
import { createRequire } from "node:module";
import { test } from "node:test";

test("the deployable bundle cold-starts and exports the configured Lambda handler", async () => {
  const previousTable = process.env.REQUESTS_TABLE_NAME;
  process.env.REQUESTS_TABLE_NAME = "packaging-test-table";
  try {
    const require = createRequire(import.meta.url);
    const bundle = require("../lambda/index.js");
    assert.equal(typeof bundle.handler, "function");
    // Invalid input takes no DynamoDB path and needs no credentials or network.
    const response = await bundle.handler({
      rawPath: "/v1/feature-requests", requestContext: { http: { method: "POST" } },
      headers: { "content-type": "application/json" }, body: "{}", isBase64Encoded: false,
    });
    assert.equal(response.statusCode, 400);
    assert.equal(JSON.parse(response.body).error.code, "invalid_request");
  } finally {
    if (previousTable === undefined) delete process.env.REQUESTS_TABLE_NAME;
    else process.env.REQUESTS_TABLE_NAME = previousTable;
  }
});
