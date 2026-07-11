#!/usr/bin/env node
// baseline-diff.mjs — compare /nazarly-qa runs by their JSON reports.
// Usage: node baseline-diff.mjs <reports-dir>
// Reads all *.json in the folder (name sort = date sort), compares the latest
// with the previous one and prints: new / fixed / persisting bugs, plus flow
// regressions. first_seen of persisting bugs comes from the full history.
import { readdirSync, readFileSync } from 'node:fs';
import { join } from 'node:path';

const dir = process.argv[2];
if (!dir) { console.log('USAGE=node baseline-diff.mjs <reports-dir>'); process.exit(1); }

let files;
try {
  files = readdirSync(dir).filter(f => f.endsWith('.json')).sort();
} catch { console.log('BASELINE=no-reports-dir'); process.exit(0); }
if (files.length === 0) { console.log('BASELINE=first-run'); process.exit(0); }

const load = (f) => {
  try { return JSON.parse(readFileSync(join(dir, f), 'utf8')); }
  catch { return null; }
};
const reports = files.map(f => ({ file: f, data: load(f) })).filter(r => r.data);
if (reports.length === 0) { console.log('BASELINE=no-valid-reports'); process.exit(0); }

const cur = reports[reports.length - 1];
if (reports.length === 1) {
  console.log(`BASELINE=first-run CUR=${cur.file}`);
  process.exit(0);
}
const prev = reports[reports.length - 2];

const bugsOf = (r) => new Map((r.data.bugs || []).map(b => [b.id, b]));
const flowsOf = (r) => new Map((r.data.flows || []).map(f => [f.id, f]));

const curBugs = bugsOf(cur), prevBugs = bugsOf(prev);
const curFlows = flowsOf(cur), prevFlows = flowsOf(prev);

// first_seen: the earliest report where the bug appears
const firstSeen = (id) => {
  for (const r of reports) {
    if ((r.data.bugs || []).some(b => b.id === id)) return r.data.date || r.file;
  }
  return cur.data.date || cur.file;
};
const daysAgo = (iso) => {
  const t = Date.parse(iso);
  if (Number.isNaN(t)) return null;
  return Math.floor((Date.now() - t) / 86400000);
};

console.log(`BASELINE=diff PREV=${prev.file} CUR=${cur.file}`);
for (const [id, b] of curBugs) {
  if (!prevBugs.has(id)) console.log(`NEW: ${id} (${b.severity}) — ${b.title}`);
}
for (const [id, b] of prevBugs) {
  if (!curBugs.has(id)) console.log(`FIXED: ${id} — ${b.title}`);
}
for (const [id, b] of curBugs) {
  if (prevBugs.has(id)) {
    const seen = firstSeen(id);
    const d = daysAgo(seen);
    const age = d === null ? `first_seen=${seen}` : `open for ${d}d (since ${seen.slice(0, 10)})`;
    console.log(`PERSISTING: ${id} (${b.severity}) — ${age}${d !== null && d >= 3 ? ' ⚠️ ESCALATION' : ''}`);
  }
}
// flow regressions: was pass → became fail
for (const [id, f] of curFlows) {
  const p = prevFlows.get(id);
  if (p && p.status === 'pass' && f.status === 'fail') {
    console.log(`FLOW_REGRESSION: ${id} — was green in ${prev.file}`);
  }
}
console.log(`SUMMARY: bugs=${curBugs.size} prev=${prevBugs.size} flows=${curFlows.size}`);
