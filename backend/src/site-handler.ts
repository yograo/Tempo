import { readFileSync } from "node:fs";
import { join } from "node:path";
import type { APIGatewayProxyEventV2, APIGatewayProxyStructuredResultV2 } from "aws-lambda";
const files: Record<string, [string, string]> = {
  "/": ["index.html", "text/html; charset=utf-8"],
  "/app.js": ["app.js", "text/javascript; charset=utf-8"],
  "/auth.js": ["auth.js", "text/javascript; charset=utf-8"],
  "/model.js": ["model.js", "text/javascript; charset=utf-8"],
  "/style.css": ["style.css", "text/css; charset=utf-8"],
};
export async function handler(event: APIGatewayProxyEventV2): Promise<APIGatewayProxyStructuredResultV2> {
  const authOrigin = process.env.AUTH_ORIGIN;
  const clientId = process.env.CLIENT_ID;
  if (!authOrigin || !/^https:\/\/[a-z0-9-]+\.auth\.[a-z0-9-]+\.amazoncognito\.com$/.test(authOrigin) || !clientId) throw new Error("Invalid dashboard configuration.");
  const headers = {
    "cache-control": "no-store", "x-content-type-options": "nosniff", "referrer-policy": "no-referrer",
    "strict-transport-security": "max-age=31536000; includeSubDomains", "x-frame-options": "DENY",
    "permissions-policy": "camera=(), microphone=(), geolocation=()",
    "content-security-policy": `default-src 'none'; script-src 'self'; style-src 'self'; img-src 'self' data:; connect-src 'self' ${authOrigin}; base-uri 'none'; form-action 'self'; frame-ancestors 'none'`,
  };
  if (event.requestContext.http.method !== "GET") return { statusCode: 404, headers, body: "Not found" };
  if (event.rawPath === "/config.json") return { statusCode: 200, headers: { ...headers, "content-type": "application/json" }, body: JSON.stringify({ authOrigin, clientId, demo: false }) };
  const file = files[event.rawPath];
  if (!file) return { statusCode: 404, headers, body: "Not found" };
  return { statusCode: 200, headers: { ...headers, "content-type": file[1] }, body: readFileSync(join(__dirname, file[0]), "utf8") };
}
