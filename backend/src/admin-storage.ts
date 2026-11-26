import { ScanCommand, UpdateItemCommand, type AttributeValue, type DynamoDBClient } from "@aws-sdk/client-dynamodb";
import { ConflictError, STATUSES, type AdminRequest, type RequestPage, type RequestStatus } from "./admin.js";

function decode(item: Record<string, AttributeValue>): AdminRequest {
  const text = (name: string) => {
    const value = item[name]?.S;
    if (value === undefined) throw new Error("Unsupported stored request.");
    return value;
  };
  const revision = item.revision ? Number(item.revision.N) : 0;
  const status = text("status") as RequestStatus;
  if (!STATUSES.includes(status) || !Number.isSafeInteger(revision) || revision < 0) throw new Error("Unsupported request metadata.");
  return {
    requestId: text("requestId"), title: text("title"), description: text("description"),
    appVersion: text("appVersion"), createdAt: text("createdAt"), status, revision,
    ...(item.email?.S !== undefined ? { email: item.email.S } : {}),
    ...(item.updatedAt?.S !== undefined ? { updatedAt: item.updatedAt.S } : {}),
  };
}

export function createAdminStore(client: Pick<DynamoDBClient, "send">, tableName: string, now = () => new Date()) {
  return {
    async list(cursor?: string): Promise<RequestPage> {
      // The existing table has only a requestId key. Each owner-triggered page
      // evaluates at most 50 rows / 1 MiB; it is not globally date-ordered.
      const result = await client.send(new ScanCommand({
        TableName: tableName, Limit: 50, ConsistentRead: true,
        ...(cursor ? { ExclusiveStartKey: { requestId: { S: cursor } } } : {}),
        ProjectionExpression: "requestId, title, description, email, appVersion, createdAt, #status, revision, updatedAt",
        ExpressionAttributeNames: { "#status": "status" },
      }));
      return { items: (result.Items ?? []).map(decode),
        ...(result.LastEvaluatedKey?.requestId?.S ? { nextCursor: result.LastEvaluatedKey.requestId.S } : {}) };
    },
    async update(id: string, status: RequestStatus, revision: number): Promise<AdminRequest> {
      try {
        const result = await client.send(new UpdateItemCommand({
          TableName: tableName, Key: { requestId: { S: id } },
          UpdateExpression: "SET #status = :status, revision = :next, updatedAt = :now",
          ConditionExpression: `attribute_exists(requestId) AND ${revision === 0 ? "(attribute_not_exists(revision) OR revision = :revision)" : "revision = :revision"}`,
          ExpressionAttributeNames: { "#status": "status" },
          ExpressionAttributeValues: { ":status": { S: status }, ":next": { N: String(revision + 1) },
            ":revision": { N: String(revision) }, ":now": { S: now().toISOString() } },
          ReturnValues: "ALL_NEW", ReturnValuesOnConditionCheckFailure: "NONE",
        }));
        if (!result.Attributes) throw new Error("Missing update result.");
        return decode(result.Attributes);
      } catch (failure) {
        if (failure instanceof Error && failure.name === "ConditionalCheckFailedException") throw new ConflictError();
        throw failure;
      }
    },
  };
}
