import { DynamoDBClient } from "@aws-sdk/client-dynamodb";
import { createSubmitHandler } from "./submit.js";
import { createWriter } from "./storage.js";

const tableName = process.env.REQUESTS_TABLE_NAME;
if (!tableName) throw new Error("Missing REQUESTS_TABLE_NAME configuration.");

const client = new DynamoDBClient({ maxAttempts: 2 });

export const handler = createSubmitHandler({
  write: createWriter(client, tableName),
  now: () => new Date(),
  reportWriteFailure: () => console.error("feature_request_write_failed"),
});
