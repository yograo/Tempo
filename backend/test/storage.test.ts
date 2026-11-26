import assert from "node:assert/strict";
import { test } from "node:test";
import { PutItemCommand } from "@aws-sdk/client-dynamodb";
import { createWriter } from "../src/storage.js";
import type { FeatureRequest } from "../src/submit.js";

const request: FeatureRequest = { requestId: "00000000-0000-4000-8000-000000000000", title: "Repeat blocks",
  description: "Please repeat blocks of exercises.", appVersion: "1.0", email: "reply@example.com", createdAt: "2026-11-21T10:00:00.000Z", status: "new" };

test("writes conditionally, requests no old data, and performs no reads", async () => {
  const calls: PutItemCommand[] = [];
  const write = createWriter({ send: async (command) => { calls.push(command); } }, "private-table");
  await write(request);
  assert.equal(calls.length, 1);
  assert.ok(calls[0] instanceof PutItemCommand);
  assert.deepEqual(calls[0].input, {
    TableName: "private-table", Item: Object.fromEntries(Object.entries(request).map(([key, value]) => [key, { S: value }])),
    ConditionExpression: "attribute_not_exists(#id)", ExpressionAttributeNames: { "#id": "requestId" },
    ReturnValues: "NONE", ReturnValuesOnConditionCheckFailure: "NONE",
  });
});

test("duplicate writes succeed without a follow-up read", async () => {
  let calls = 0;
  const duplicate = new Error("duplicate");
  duplicate.name = "ConditionalCheckFailedException";
  const write = createWriter({ send: async () => { calls++; throw duplicate; } }, "private-table");
  await write(request);
  assert.equal(calls, 1);
});

test("includes a supplied reply email in the private item", async () => {
  let item: PutItemCommand["input"]["Item"];
  const write = createWriter({ send: async (command) => { item = command.input.Item; } }, "private-table");
  await write({ ...request, email: "reply+tempo@example.com" });
  assert.deepEqual(item?.email, { S: "reply+tempo@example.com" });
});

test("other DynamoDB failures propagate so clients can retry", async () => {
  const unavailable = new Error("DynamoDB unavailable");
  const write = createWriter({ send: async () => { throw unavailable; } }, "private-table");
  await assert.rejects(() => write(request), unavailable);
});
