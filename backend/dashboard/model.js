export const statuses = { new: "New", planned: "Planned", in_progress: "In progress", implemented: "Implemented", declined: "Declined" };
export function visibleRequests(items, query, status) {
  const needle = query.trim().toLowerCase();
  return items.filter((r) => (status === "all" || r.status === status) &&
    [r.title, r.description, r.email ?? ""].some((text) => text.toLowerCase().includes(needle)))
    .sort((a, b) => b.createdAt.localeCompare(a.createdAt) || a.requestId.localeCompare(b.requestId));
}
export function mergePage(items, page) {
  const byId = new Map(items.map((r) => [r.requestId, r]));
  for (const row of page) {
    const existing = byId.get(row.requestId);
    if (!existing || existing.revision <= row.revision) byId.set(row.requestId, row);
  }
  return [...byId.values()];
}
export function replyLink(row) {
  // Encode the mailbox too: valid local parts may contain ?, #, &, or +.
  // Reject malformed legacy values; never allow them to introduce URI headers.
  if (!row.email || row.email.length > 254 || /[\s\u0000-\u001f\u007f]/.test(row.email) || !/^[^@]+@[^@]+\.[^@]+$/.test(row.email)) return undefined;
  const subject = `Your Tempo idea: ${row.title}`.replace(/[\u0000-\u001f\u007f]/g, " ");
  return `mailto:${encodeURIComponent(row.email)}?subject=${encodeURIComponent(subject)}`;
}
