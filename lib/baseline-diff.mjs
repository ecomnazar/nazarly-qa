#!/usr/bin/env node
// baseline-diff.mjs — run-over-run comparison of /nazarly-qa JSON reports.
// Usage: node baseline-diff.mjs <reports-dir>
// Reads every *.json in the folder (name sort = date sort), compares the
// latest with the previous one and prints: new / fixed / persisting bugs,
// flow regressions, coverage ratchet, escape rate, flaky repeats.
// first_seen for persisting bugs is computed across the whole history.
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
    const age = d === null ? `first_seen=${seen}` : `open ${d} days (since ${seen.slice(0, 10)})`;
    console.log(`PERSISTING: ${id} (${b.severity}) — ${age}${d !== null && d >= 3 ? ' ⚠️ ESCALATION' : ''}`);
  }
}
// flow regressions: was pass → now fail
for (const [id, f] of curFlows) {
  const p = prevFlows.get(id);
  if (p && p.status === 'pass' && f.status === 'fail') {
    console.log(`FLOW_REGRESSION: ${id} — was green in ${prev.file}`);
  }
}

// repeated false candidates: refuted in both the previous and the current run —
// finder agents keep discovering a bug that doesn't exist; document it as a known non-bug
const refutedIds = (r) => new Set((r.data.refuted || []).map(x => x.id));
const curRef = refutedIds(cur), prevRef = refutedIds(prev);
for (const id of curRef) {
  if (prevRef.has(id)) console.log(`REFUTED_REPEAT: ${id} — refuted two runs in a row; document as a known non-bug`);
}

// coverage ratchet: pass-flow count and run scope must not shrink between runs.
// Only compare runs of the same scope (--fast vs full is a mode, not a regression).
const passCount = (r) => [...flowsOf(r).values()].filter(f => f.status === 'pass').length;
const curPass = passCount(cur), prevPass = passCount(prev);
if ((cur.data.scope || '') === (prev.data.scope || '')) {
  if (curPass < prevPass) console.log(`COVERAGE_REGRESS: pass flows ${prevPass}→${curPass} ⚠️ (coverage dropped — that's a gate, not a footnote)`);
  if (curFlows.size < prevFlows.size) console.log(`COVERAGE_REGRESS: planned flows ${prevFlows.size}→${curFlows.size} ⚠️ (flows fell out of the run)`);
} else {
  console.log(`SCOPE_DIFF: ${prev.data.scope || '?'} → ${cur.data.scope || '?'} (coverage not compared)`);
}
const uncovered = cur.data.uncovered || [];
if (uncovered.length) console.log(`UNCOVERED: ${uncovered.length} — ${uncovered.join('; ')}`);

// escape rate — the process's headline metric: production incidents that got past QA.
// Across the whole history: bugs QA found vs incidents that hit production,
// and how many of those QA was supposed to catch. Theater signal: QA stays green while escapes keep coming.
for (const e of cur.data.escapes || []) {
  console.log(`ESCAPE: ${e.incident} (${e.date || '?'}) — QA should have caught it: ${e.qa_should_have_caught ? 'YES ❌' : 'no'}${e.why_missed ? ` — ${e.why_missed}` : ''}`);
}
const allBugIds = new Set(), allEscapes = [], missable = [];
for (const r of reports) {
  for (const b of r.data.bugs || []) allBugIds.add(b.id);
  for (const e of r.data.escapes || []) {
    allEscapes.push(e);
    if (e.qa_should_have_caught) missable.push(e.incident);
  }
}
console.log(`QA-SCORE (whole history, ${reports.length} runs): found by QA=${allBugIds.size}, prod incidents=${allEscapes.length}, of which QA should have caught=${missable.length}${missable.length ? ` (${missable.join('; ')})` : ''}`);
if (allBugIds.size === 0 && missable.length > 0) console.log('THEATER-SIGNAL ⚠️: QA finds nothing while prod incidents keep coming — the tests are not where the risk is.');

// flaky repeats: a test in flaky_suspects two runs in a row is a mandatory fix candidate
const suspectsOf = (r) => new Set((r.data.flaky_suspects || []).map(s => s.test));
const curSus = suspectsOf(cur), prevSus = suspectsOf(prev);
for (const t of curSus) {
  if (prevSus.has(t)) console.log(`FLAKY_REPEAT: ${t} — flaky_suspect two runs in a row; fix it, don't watch it`);
}

console.log(`SUMMARY: bugs=${curBugs.size} prev=${prevBugs.size} flows=${curFlows.size} pass=${curPass} refuted=${curRef.size} unconfirmed=${(cur.data.unconfirmed || []).length} flaky_suspects=${curSus.size}`);
