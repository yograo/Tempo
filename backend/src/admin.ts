import type { APIGatewayProxyEventV2WithJWTAuthorizer, APIGatewayProxyStructuredResultV2 } from "aws-lambda";

export const OWNER_GROUP = "TempoOwners";
export const ADMIN_PATH = "/admin/requests";
export const STATUSES = ["new", "planned", "in_progress", "implemented", "declined"] as const;
export type RequestStatus = typeof STATUSES[number];
export interface AdminRequest {
  requestId: string;
  title: string;
  description: string;
  email?: string;
  appVersion: string;
  createdAt: string;
  status: RequestStatus;
  revision: number;
  updatedAt?: string;
}
export interface RequestPage { items: AdminRequest[]; nextCursor?: string }
export interface AdminDependencies {
  list: (cursor?: string) => Promise<RequestPage>;
  update: (id: string, status: RequestStatus, revision: number) => Promise<AdminRequest>;
  reportFailure: () => void;
}
export class ConflictError extends Error {}
export const validId = (value: string) => /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/.test(value);

// HTTP API authorizer claims can serialize a list as JSON or as [group, group].
// Match complete group names, never substrings. The gateway validates the JWT;
// these trusted claims must come from requestContext, never caller headers/body.
export function isOwner(claims: Record<string, unknown> | undefined): boolean {
  if (!claims || claims.token_use !== "access" || typeof claims.sub !== "string" || !claims.sub) return false;
  let groups: unknown = claims["cognito:groups"];
  if (typeof groups === "string") {
    const raw = groups;
    try { groups = JSON.parse(raw); }
    catch { groups = raw.replace(/^\[|\]$/g, "").split(",").map((g) => g.trim()); }
  }
  return Array.isArray(groups) && groups.includes(OWNER_GROUP);
}

function reply(statusCode: number, body: unknown): APIGatewayProxyStructuredResultV2 {
  return { statusCode, headers: { "content-type": "application/json", "cache-control": "no-store", "x-content-type-options": "nosniff" }, body: JSON.stringify(body) };
}
const error = (status: number, message: string) => reply(status, { error: message });

export function createAdminHandler(deps: AdminDependencies) {
  return async (event: APIGatewayProxyEventV2WithJWTAuthorizer): Promise<APIGatewayProxyStructuredResultV2> => {
    if (!isOwner(event.requestContext.authorizer?.jwt?.claims)) return error(403, "Owner access required.");
    const method = event.requestContext.http.method;
    try {
      if (event.rawPath === ADMIN_PATH && method === "GET") {
        const params = event.queryStringParameters ?? {};
        if (Object.keys(params).some((key) => key !== "cursor") || (params.cursor !== undefined && !validId(params.cursor))) {
          return error(400, "Invalid page cursor.");
        }
        return reply(200, await deps.list(params.cursor));
      }
      const id = event.rawPath.startsWith(`${ADMIN_PATH}/`) ? event.rawPath.slice(ADMIN_PATH.length + 1) : "";
      if (method !== "PATCH" || !validId(id)) return error(404, "Endpoint not found.");
      const headers = Object.fromEntries(Object.entries(event.headers).map(([k, v]) => [k.toLowerCase(), v]));
      if (headers["content-type"]?.split(";")[0]?.trim().toLowerCase() !== "application/json" ||
          (headers["content-encoding"] && headers["content-encoding"] !== "identity")) return error(415, "Use uncompressed application/json.");
      const raw = event.body ?? "";
      if (raw.length > 1400) return error(413, "Request too large.");
      let value: unknown;
      try {
        const bytes = Buffer.from(raw, event.isBase64Encoded ? "base64" : "utf8");
        if (bytes.length > 1024) return error(413, "Request too large.");
        value = JSON.parse(new TextDecoder("utf-8", { fatal: true }).decode(bytes));
      } catch { return error(400, "Invalid JSON."); }
      if (!value || typeof value !== "object" || Array.isArray(value)) return error(400, "Invalid update.");
      const data = value as Record<string, unknown>;
      if (Object.keys(data).some((key) => key !== "status" && key !== "revision") ||
          !STATUSES.includes(data.status as RequestStatus) || !Number.isSafeInteger(data.revision) ||
          (data.revision as number) < 0 || (data.revision as number) >= Number.MAX_SAFE_INTEGER) return error(400, "Supply a valid status and current revision.");
      return reply(200, await deps.update(id, data.status as RequestStatus, data.revision as number));
    } catch (failure) {
      if (failure instanceof ConflictError) return error(409, "This request changed or no longer exists. Refresh before saving again.");
      deps.reportFailure();
      return error(503, "Requests are temporarily unavailable. Please retry.");
    }
  };
}
