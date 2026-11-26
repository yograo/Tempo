import { PutItemCommand } from "@aws-sdk/client-dynamodb";
import type { FeatureRequest } from "./submit.js";

export interface DynamoWriter {
  send: (command: PutItemCommand) => Promise<unknown>;
}

export function createWriter(client: DynamoWriter, tableName: string) {
  return async (request: FeatureRequest): Promise<void> => {
    try {
      await client.send(new PutItemCommand({
        TableName: tableName,
        Item: {
          requestId: { S: request.requestId },
          title: { S: request.title },
          description: { S: request.description },
          appVersion: { S: request.appVersion },
          ...(request.email ? { email: { S: request.email } } : {}),
          createdAt: { S: request.createdAt },
          status: { S: request.status },
        },
        ConditionExpression: "attribute_not_exists(#id)",
        ExpressionAttributeNames: { "#id": "requestId" },
        ReturnValues: "NONE",
        ReturnValuesOnConditionCheckFailure: "NONE",
      }));
    } catch (failure) {
      if (failure instanceof Error && failure.name === "ConditionalCheckFailedException") return;
      throw failure;
    }
  };
}
