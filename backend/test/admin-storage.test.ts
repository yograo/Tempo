import assert from "node:assert/strict";
import { test } from "node:test";
import { DynamoDBClient, ScanCommand, UpdateItemCommand } from "@aws-sdk/client-dynamodb";
import { createAdminStore } from "../src/admin-storage.js";
import { ConflictError } from "../src/admin.js";
const id = "00000000-0000-4000-8000-000000000001";
const item = { requestId: { S: id }, title: { S: "A request" }, description: { S: "Please add a helpful feature" }, appVersion: { S: "1.1" }, createdAt: { S: "2026-11-26T12:00:00.000Z" }, status: { S: "new" } };
const client = (send: (command: any) => Promise<unknown>) => ({ send }) as unknown as DynamoDBClient;
test("bounded scan projects request fields and round-trips the last key; legacy email/revision are optional", async () => {
  const store = createAdminStore(client(async (command) => {
    assert.ok(command instanceof ScanCommand); assert.equal(command.input.Limit, 50); assert.equal(command.input.ConsistentRead, true);
    assert.deepEqual(command.input.ExclusiveStartKey, { requestId: { S: id } });
    assert.equal(command.input.ProjectionExpression!.includes("email"), true);
    return { Items: [item], LastEvaluatedKey: { requestId: { S: id } } };
  }), "test-table");
  const page = await store.list(id); assert.equal(page.nextCursor, id); assert.equal(page.items[0]!.revision, 0); assert.equal(page.items[0]!.email, undefined);
});
test("end of scan has no cursor, even for an empty page", async () => {
  assert.deepEqual(await createAdminStore(client(async () => ({})), "test-table").list(), { items: [] });
});
test("updates preserve submitted fields, require an existing item, and compare revisions", async () => {
  for (const revision of [0, 4]) {
    const store = createAdminStore(client(async (command) => {
      assert.ok(command instanceof UpdateItemCommand);
      assert.equal(command.input.UpdateExpression, "SET #status = :status, revision = :next, updatedAt = :now");
      assert.ok(command.input.ConditionExpression!.startsWith("attribute_exists(requestId) AND "));
      assert.equal(command.input.ConditionExpression!.includes("attribute_not_exists(revision)"), revision === 0);
      assert.equal(command.input.ExpressionAttributeValues![":revision"]!.N, String(revision));
      assert.equal(command.input.ExpressionAttributeValues![":next"]!.N, String(revision + 1));
      assert.equal(command.input.ReturnValuesOnConditionCheckFailure, "NONE");
      return { Attributes: { ...item, status: { S: "planned" }, revision: { N: String(revision + 1) } } };
    }), "test-table");
    const result = await store.update(id, "planned", revision); assert.equal(result.status, "planned"); assert.equal(result.revision, revision + 1);
  }
});
test("conditional write failure becomes a conflict; other failures propagate", async () => {
  const conditional = new Error("conflict"); conditional.name = "ConditionalCheckFailedException";
  await assert.rejects(createAdminStore(client(async () => { throw conditional; }), "test-table").update(id, "new", 0), ConflictError);
  const sdkError = new Error("SDK error");
  await assert.rejects(createAdminStore(client(async () => { throw sdkError; }), "test-table").update(id, "new", 0), sdkError);
});
