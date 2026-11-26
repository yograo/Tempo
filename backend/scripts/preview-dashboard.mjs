import { createServer } from "node:http";
import { readFile } from "node:fs/promises";
import { createAdminHandler } from "../dist/src/admin.js";
const rows = [
  ["Repeat a group of intervals", "I’d love to group exercises into a circuit and repeat it a few times. It would make building my morning workout so much quicker.", "new"],
  ["A gentle halfway reminder", "An optional spoken cue halfway through a longer stretch would help me switch sides without checking the screen.", "new"],
  ["Share a routine with a friend", "My friend and I do the same mobility routine. Can we share a link so we don’t have to rebuild every interval?", "planned"],
  ["More color themes", "A few softer color options for evening workouts would be lovely. I especially like the green palette.", "declined"],
  ["Apple Watch companion", "I would like to start a saved routine and follow the current interval from my watch during an outdoor workout.", "in_progress"],
  ["See my recent workouts", "It would be helpful to look back at the workouts I completed this week and keep the momentum going.", "implemented"],
  ["Longer rest between circuits", "Let me set a different rest duration between circuits than between individual exercises.", "new"],
  ["Older idea without a reply email", "This sample represents a request received before email became required.", "planned"],
];
let items = rows.map(([title, description, status], i) => ({ requestId: `00000000-0000-4000-8000-${String(i + 1).padStart(12, "0")}`, title, description, status, revision: 0,
  ...(i === 7 ? {} : { email: `runner${i + 1}@example.com` }), appVersion: "1.1", createdAt: new Date(Date.UTC(2026, 10, 26 - i, 12)).toISOString() }));
const admin = createAdminHandler({
  async list(cursor) { const start = cursor ? items.findIndex((r) => r.requestId === cursor) + 1 : 0; const page = items.slice(start, start + 5); return { items: page, ...(start + 5 < items.length ? { nextCursor: page.at(-1).requestId } : {}) }; },
  async update(id, status, revision) { const row = items.find((r) => r.requestId === id); if (!row || row.revision !== revision) { const { ConflictError } = await import("../dist/src/admin.js"); throw new ConflictError(); } Object.assign(row, { status, revision: revision + 1, updatedAt: new Date().toISOString() }); return row; },
  reportFailure() {},
});
const files = { "/": ["index.html", "text/html"], "/app.js": ["app.js", "text/javascript"], "/auth.js": ["auth.js", "text/javascript"], "/model.js": ["model.js", "text/javascript"], "/style.css": ["style.css", "text/css"] };
const server = createServer(async (req, res) => {
  try {
    const url = new URL(req.url, "http://127.0.0.1:4173");
    if (url.pathname === "/config.json") { res.writeHead(200, { "content-type": "application/json", "cache-control": "no-store" }); res.end(JSON.stringify(process.env.TEMPO_PREVIEW_LOGIN ? { demo: false, authOrigin: "https://tempo-preview.auth.us-east-2.amazoncognito.com", clientId: "preview" } : { demo: true })); return; }
    if (url.pathname.startsWith("/admin/")) {
      const chunks = []; for await (const chunk of req) chunks.push(chunk);
      const result = await admin({ rawPath: url.pathname, queryStringParameters: Object.fromEntries(url.searchParams), headers: req.headers,
        body: Buffer.concat(chunks).toString(), isBase64Encoded: false,
        requestContext: { http: { method: req.method }, authorizer: { jwt: { claims: { sub: "synthetic-preview", token_use: "access", "cognito:groups": "[TempoOwners]" } } } } });
      res.writeHead(result.statusCode, result.headers); res.end(result.body); return;
    }
    const file = files[url.pathname]; if (!file) { res.writeHead(404); res.end(); return; }
    res.writeHead(200, { "content-type": file[1], "cache-control": "no-store", "content-security-policy": "default-src 'none'; script-src 'self'; style-src 'self'; img-src data:; connect-src 'self'; base-uri 'none'; frame-ancestors 'none'" });
    res.end(await readFile(new URL(`../dashboard/${file[0]}`, import.meta.url)));
  } catch { res.writeHead(500); res.end("Preview error"); }
});
server.listen(4173, "127.0.0.1", () => console.log("Synthetic dashboard preview: http://127.0.0.1:4173"));
