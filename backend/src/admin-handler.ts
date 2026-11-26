import { DynamoDBClient } from "@aws-sdk/client-dynamodb";
import { createAdminHandler } from "./admin.js";
import { createAdminStore } from "./admin-storage.js";

const table = process.env.REQUESTS_TABLE_NAME;
if (!table) throw new Error("REQUESTS_TABLE_NAME is required.");
export const handler = createAdminHandler({
  ...createAdminStore(new DynamoDBClient({}), table),
  reportFailure: () => console.error("feature_request_admin_failed"),
});
