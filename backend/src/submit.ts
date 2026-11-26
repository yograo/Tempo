import { Buffer } from "node:buffer";
import type { APIGatewayProxyEventV2, APIGatewayProxyStructuredResultV2 } from "aws-lambda";

export const SUBMISSION_PATH = "/v1/feature-requests";
export const MAX_BODY_BYTES = 24 * 1024;

export interface FeatureRequest {
  requestId: string;
  title: string;
  description: string;
  appVersion: string;
  email?: string;
  createdAt: string;
  status: "new";
}

export interface SubmissionDependencies {
  write: (request: FeatureRequest) => Promise<void>;
  now: () => Date;
  reportWriteFailure: () => void;
}

const fields = new Set(["requestId", "title", "description", "appVersion", "email"]);
const uuidV4 = /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
// Permit newlines/tabs in descriptions, but reject other control characters.
const disallowedControls = /[\u0000-\u0008\u000b\u000c\u000e-\u001f\u007f]/u;

function response(statusCode: number, body: unknown, headers: Record<string, string> = {}): APIGatewayProxyStructuredResultV2 {
  return {
    statusCode,
    headers: { "content-type": "application/json", "cache-control": "no-store", ...headers },
    body: JSON.stringify(body),
  };
}

function error(status: number, code: string, message: string, headers: Record<string, string> = {}) {
  return response(status, { error: { code, message } }, headers);
}

function cleanText(value: unknown, min: number, max: number): string | undefined {
  if (typeof value !== "string" || disallowedControls.test(value) || /[\uD800-\uDFFF]/u.test(value)) return undefined;
  const clean = value.trim();
  const length = Array.from(clean).length;
  return length >= min && length <= max ? clean : undefined;
}

// Accept common ASCII mailboxes (including plus addressing), without claiming
// to verify ownership or deliverability. Only the domain is case-normalized.
function cleanEmail(value: string): string | undefined {
  if (/[\u0000-\u001f\u007f]/u.test(value)) return undefined;
  const email = value.trim();
  if (email.length > 254) return undefined;
  const parts = email.split("@");
  if (parts.length !== 2) return undefined;
  const [local = "", domain = ""] = parts;
  if (!local || local.length > 64 || !/^[A-Za-z0-9!#$%&'*+/=?^_`{|}~.-]+$/.test(local) ||
      local.startsWith(".") || local.endsWith(".") || local.includes("..")) return undefined;
  const labels = domain.split(".");
  if (labels.length < 2 || labels.some((label) => label.length > 63 ||
      !/^[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?$/.test(label))) return undefined;
  return `${local}@${domain.toLowerCase()}`;
}

export function createSubmitHandler(dependencies: SubmissionDependencies) {
  return async (event: APIGatewayProxyEventV2): Promise<APIGatewayProxyStructuredResultV2> => {
    if (event.rawPath !== SUBMISSION_PATH) return error(404, "not_found", "Endpoint not found.");
    if (event.requestContext.http.method !== "POST") {
      return error(405, "method_not_allowed", "Use POST to submit a request.", { allow: "POST" });
    }
    const headers = Object.fromEntries(Object.entries(event.headers).map(([key, value]) => [key.toLowerCase(), value]));
    if (headers["content-type"]?.split(";")[0]?.trim().toLowerCase() !== "application/json") {
      return error(415, "unsupported_media_type", "Send an application/json request body.");
    }
    if (headers["content-encoding"] && headers["content-encoding"].toLowerCase() !== "identity") {
      return error(415, "unsupported_encoding", "Compressed request bodies are not supported.");
    }
    const raw = event.body ?? "";
    // Bound allocation before decoding the API Gateway body representation.
    if (raw.length > (event.isBase64Encoded ? Math.ceil(MAX_BODY_BYTES / 3) * 4 : MAX_BODY_BYTES)) {
      return error(413, "payload_too_large", "The request body must be at most 24 KiB.");
    }
    const bytes = Buffer.from(raw, event.isBase64Encoded ? "base64" : "utf8");
    if (bytes.length > MAX_BODY_BYTES) {
      return error(413, "payload_too_large", "The request body must be at most 24 KiB.");
    }
    let data: unknown;
    try {
      data = JSON.parse(new TextDecoder("utf-8", { fatal: true }).decode(bytes));
    } catch {
      return error(400, "invalid_json", "Send a valid UTF-8 JSON object.");
    }
    if (data === null || typeof data !== "object" || Array.isArray(data)) {
      return error(400, "invalid_request", "Send a JSON object with requestId, title, description, and appVersion.");
    }
    const input = data as Record<string, unknown>;
    if (Object.keys(input).some((field) => !fields.has(field))) {
      return error(400, "invalid_request", "Only requestId, title, description, appVersion, and optional email are accepted.");
    }
    if (typeof input.requestId !== "string" || !uuidV4.test(input.requestId)) {
      return error(400, "invalid_request", "requestId must be a randomly generated UUID v4.");
    }
    const title = cleanText(input.title, 3, 120);
    if (!title || /[\r\n\t]/u.test(title)) {
      return error(400, "invalid_request", "title must be a single line of 3–120 characters.");
    }
    const description = cleanText(input.description, 10, 4000);
    if (!description) return error(400, "invalid_request", "description must contain 10–4000 characters.");
    if (typeof input.appVersion !== "string" || input.appVersion.length > 32 || !/^\d+(?:\.\d+){0,2}$/.test(input.appVersion)) {
      return error(400, "invalid_request", "appVersion must be a version such as 1.0 or 1.2.3 (at most 32 characters).");
    }
    let email: string | undefined;
    if (input.email !== undefined) {
      if (typeof input.email !== "string" || /[\u0000-\u001f\u007f]/u.test(input.email)) {
        return error(400, "invalid_request", "email must be a valid reply address or left blank.");
      }
      if (input.email.trim()) {
        email = cleanEmail(input.email);
        if (!email) return error(400, "invalid_request", "email must be a valid reply address of at most 254 characters.");
      }
    }
    const requestId = input.requestId.toLowerCase();
    try {
      await dependencies.write({ requestId, title, description, appVersion: input.appVersion,
        ...(email ? { email } : {}),
        createdAt: dependencies.now().toISOString(), status: "new" });
    } catch {
      // Never log payloads, SDK exceptions, identifiers, or source IP addresses.
      dependencies.reportWriteFailure();
      return error(503, "temporarily_unavailable", "Please retry using the same requestId.", { "retry-after": "5" });
    }
    // Identical receipt for a new submission and a retry. No stored data is returned.
    return response(202, { requestId, status: "received" });
  };
}
