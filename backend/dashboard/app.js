import { createAuthorization, validateCallback, exchangeCode } from "/auth.js";
import { statuses, visibleRequests, mergePage, replyLink } from "/model.js";
const $ = (id) => document.getElementById(id);
const node = (tag, className, text) => { const el = document.createElement(tag); if (className) el.className = className; if (text !== undefined) el.textContent = text; return el; };
const date = (value) => { const d = new Date(value); return Number.isNaN(d.getTime()) ? "Unknown date" : new Intl.DateTimeFormat(undefined, { month: "short", day: "numeric", year: "numeric" }).format(d); };
let config, token, expiresAt = 0, expiryTimer, items = [], cursor, selected, busy = false, hasLoaded = false, generation = 0;
const transactionKey = "tempo.signin.transaction";
const redirectUri = `${location.origin}/`;
function notice(message, success = false) { $("notice").textContent = message; $("notice").className = `notice${success ? " success" : ""}`; $("notice").hidden = !message; }
function clearSession(message = "") {
  generation++; clearTimeout(expiryTimer); token = undefined; expiresAt = 0; items = []; cursor = undefined; selected = undefined; hasLoaded = false; busy = false;
  $("workspace").hidden = true; $("login").hidden = false; $("sign-out").hidden = true;
  $("search").value = ""; $("filter").value = "all";
  for (const id of ["request-list", "detail", "stats"]) $(id).replaceChildren();
  notice(message);
}
async function api(path, options = {}) {
  if (!config.demo && (!token || Date.now() >= expiresAt)) { clearSession("Your session expired. Sign in again to continue."); throw new Error("Your session expired. Sign in again to continue."); }
  const response = await fetch(path, { ...options, cache: "no-store", credentials: "omit", redirect: "error",
    headers: { ...(token ? { authorization: `Bearer ${token}` } : {}), ...(options.body ? { "content-type": "application/json" } : {}) } });
  if (response.status === 401 || response.status === 403) {
    const message = response.status === 403 ? "This account needs TempoOwners membership. Ask the account owner to configure access." : "Your session expired. Sign in again to continue.";
    clearSession(message); throw new Error(message);
  }
  if (response.status === 409) throw new Error("This request changed elsewhere. Refresh to load the latest version before saving again.");
  if (!response.ok) throw new Error(response.status === 429 ? "Too many requests. Wait a moment and try again." : "Could not reach the request service. Please try again.");
  return response.json();
}
function badge(status) { return node("span", `badge badge-${status}`, statuses[status] ?? status); }
function renderStats() {
  const stats = [["Requests loaded", items.length, "All statuses", "↗"], ["New ideas", items.filter((r) => r.status === "new").length, "Ready for a first look", "✧"],
    ["On the roadmap", items.filter((r) => ["planned", "in_progress"].includes(r.status)).length, "Planned & in progress", "→"], ["Implemented", items.filter((r) => r.status === "implemented").length, "Ideas brought to life", "✓"]];
  $("stats").replaceChildren(...stats.map(([label, count, caption, symbol]) => {
    const card = node("div", "stat"); const heading = node("div", "stat-label", label); const icon = node("span", "", symbol); icon.setAttribute("aria-hidden", "true"); heading.append(icon);
    card.append(heading, node("span", "stat-number", String(count)), node("p", "stat-caption", caption)); return card;
  }));
}
function renderDetail() {
  const detail = $("detail"); detail.replaceChildren();
  const row = items.find((r) => r.requestId === selected);
  if (!row) { const empty = node("div", "empty"); empty.append(node("div", "empty-symbol", "↗"), node("h2", "", "A little idea goes a long way."), node("p", "", "Select a request to read the details and decide what’s next.")); detail.append(empty); return; }
  const top = node("div", "detail-top"); top.append(node("span", "detail-eyebrow", "THE IDEA"), badge(row.status));
  const meta = node("div", "detail-meta"); meta.append(node("span", "", `Received ${date(row.createdAt)}`), node("span", "", `Tempo ${row.appVersion}`));
  const label = node("label", "detail-label", "REQUEST STATUS"); label.htmlFor = "status";
  const form = node("form", "update-form"); const select = node("select"); select.id = "status"; select.disabled = busy;
  for (const [value, title] of Object.entries(statuses)) { const option = node("option", "", title); option.value = value; select.append(option); }
  select.value = row.status;
  const save = node("button", "primary", "Save status"); save.type = "submit"; save.disabled = true;
  select.addEventListener("change", () => { save.disabled = busy || select.value === row.status; });
  form.append(select, save); form.addEventListener("submit", async (event) => {
    event.preventDefault(); if (busy || select.value === row.status) return;
    const nextStatus = select.value; busy = true; notice(""); render(); const current = generation;
    try {
      const updated = await api(`/admin/requests/${row.requestId}`, { method: "PATCH", body: JSON.stringify({ status: nextStatus, revision: row.revision }) });
      if (current !== generation) return;
      items = mergePage(items, [updated]); notice(`Status saved as ${statuses[updated.status]}.`, true);
    } catch (error) { if (current === generation) notice(error.message); }
    finally { if (current === generation) { busy = false; render(); } }
  });
  const contact = node("div", "contact"); contact.append(node("span", "detail-label", "CLOSE THE LOOP"), node("span", "email", row.email || "No email on this older request"));
  const link = replyLink(row);
  if (link) { const reply = node("a", "reply", "Draft a reply ↗"); reply.href = link; contact.append(node("p", "", "Opens your email app. Nothing is sent automatically. This address hasn’t been verified."), reply); }
  else contact.append(node("p", "", "A usable reply address wasn’t included with this request."));
  detail.append(top, node("h2", "", row.title), meta, node("p", "description", row.description), label, form, contact,
    node("p", "request-id", `Request ${row.requestId}${row.updatedAt ? ` · Updated ${date(row.updatedAt)}` : ""}`));
}
function render() {
  renderStats(); const visible = visibleRequests(items, $("search").value, $("filter").value);
  if (!visible.some((r) => r.requestId === selected)) selected = visible[0]?.requestId;
  $("loaded-label").textContent = `${items.length} loaded`;
  $("scope").textContent = !hasLoaded ? (busy ? "Loading requests…" : "Requests haven’t loaded. Use Refresh to try again.") : cursor ? "More requests are available. Search, counts, and newest-first sorting cover loaded requests only." : "All pages loaded. Sorted newest first. Refresh to check for new requests.";
  $("result-count").textContent = `${visible.length} matching ${visible.length === 1 ? "request" : "requests"}`;
  $("refresh").disabled = busy; $("load-more").hidden = !cursor; $("load-more").disabled = busy; $("load-more").textContent = busy ? "Loading…" : "Load more";
  const list = $("request-list"); list.setAttribute("aria-busy", String(busy));
  list.replaceChildren(...visible.map((row) => {
    const button = node("button", "request-row"); button.type = "button"; button.setAttribute("aria-pressed", String(row.requestId === selected));
    const top = node("div", "row-top"); top.append(node("span", "row-title", row.title), badge(row.status));
    const meta = node("div", "row-meta"); meta.append(node("span", "", date(row.createdAt)), node("span", "", `v${row.appVersion}`));
    button.append(top, node("p", "row-excerpt", row.description), meta);
    button.addEventListener("click", () => { if (busy) return; selected = row.requestId; render();
      // Keep keyboard focus on the corresponding rebuilt row.
      list.querySelector('[aria-pressed="true"]')?.focus({ preventScroll: true });
    }); return button;
  }));
  if (!visible.length) { const empty = node("div", "empty"); empty.append(node("h2", "", busy ? "Loading ideas…" : items.length ? "No matching ideas" : hasLoaded ? "A fresh start." : "The inbox is waiting."),
    node("p", "", items.length ? "Try another search or status filter. You can also load more requests when available." : hasLoaded ? "New feature requests from Tempo will appear here." : "Use Refresh to load requests.")); list.append(empty); }
  renderDetail();
}
async function load(reset = false) {
  if (busy) return; const current = generation; busy = true; notice(""); render();
  try {
    const page = await api(`/admin/requests${!reset && cursor ? `?cursor=${encodeURIComponent(cursor)}` : ""}`);
    if (current !== generation) return;
    items = mergePage(reset ? [] : items, page.items); cursor = page.nextCursor; hasLoaded = true;
  } catch (error) { if (current === generation) notice(error.message); }
  finally { if (current === generation) { busy = false; render(); } }
}
async function showWorkspace() { $("login").hidden = true; $("workspace").hidden = false; $("sign-out").hidden = config.demo; $("demo-banner").hidden = !config.demo; await load(true); }
$("search").addEventListener("input", render); $("filter").addEventListener("change", render);
$("refresh").addEventListener("click", () => load(true)); $("load-more").addEventListener("click", () => load());
$("sign-in").addEventListener("click", async () => {
  $("sign-in").disabled = true; notice("");
  try { const auth = await createAuthorization(config, redirectUri); sessionStorage.setItem(transactionKey, JSON.stringify(auth.transaction)); location.assign(auth.url); }
  catch { notice("Could not start sign-in. Allow session storage for this site and try again."); $("sign-in").disabled = false; }
});
$("sign-out").addEventListener("click", () => {
  clearSession(); sessionStorage.removeItem(transactionKey);
  const url = new URL("/logout", config.authOrigin); url.search = new URLSearchParams({ client_id: config.clientId, logout_uri: redirectUri }).toString(); location.assign(url.href);
});
// Back/forward cache must not resurrect private data or an old access token.
window.addEventListener("pagehide", () => { clearSession(); });
window.addEventListener("pageshow", (event) => { if (event.persisted) clearSession("Sign in again to continue."); });
async function start() {
  const search = location.search; history.replaceState(null, "", "/");
  try {
    const response = await fetch("/config.json", { cache: "no-store", credentials: "omit", redirect: "error" });
    if (!response.ok) throw new Error("The dashboard is unavailable. Please reload to try again."); config = await response.json();
    $("sign-in").textContent = "Sign in to Tempo"; $("sign-in").disabled = false;
    if (config.demo) { await showWorkspace(); return; }
    if (search) {
      const stored = sessionStorage.getItem(transactionKey); sessionStorage.removeItem(transactionKey);
      const transaction = stored ? JSON.parse(stored) : undefined;
      const code = validateCallback(search, transaction, redirectUri);
      const session = await exchangeCode(config, code, transaction); token = session.token; expiresAt = session.expiresAt;
      expiryTimer = setTimeout(() => clearSession("Your session expired. Sign in again to continue."), Math.max(0, expiresAt - Date.now()));
      await showWorkspace();
    }
  } catch (error) { notice(error.message || "Could not load the dashboard. Please reload to try again."); }
}
start();
