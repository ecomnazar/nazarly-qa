#!/usr/bin/env node
// check-flaky-patterns.mjs — static scan of a project's tests for flaky patterns.
// Catches the class: tests that are green locally and red on CI (sleep-as-sync,
// shared /tmp paths, wall-clock assertions, a forgotten .only, shared mock state,
// unseeded randomness).
//
// Usage: node check-flaky-patterns.mjs [project-root]
// Read-only. Conservative: better to miss than to spam.
// False positives go to <root>/.claude/qa/flaky-allowlist.txt: a line of
// `file:line reason` or `file reason` (whole file).
import { readdirSync, readFileSync, existsSync, statSync } from 'node:fs';
import { join, relative } from 'node:path';

const root = process.argv[2] || process.cwd();
const SKIP_DIRS = new Set(['node_modules', '.git', 'dist', 'build', 'out', 'coverage', '.next', 'dist-electron', 'vendor', '.claude']);
const TEST_FILE = /\.(test|spec|e2e)\.[cm]?[jt]sx?$/;
const TEST_DIR = /(^|\/)(tests?|__tests__|e2e)(\/|$)/;

// Patterns: [class, regex, advice]. Each one is about nondeterminism, not style.
const PATTERNS = [
  ['sleep-as-sync', /\b(?:await\s+)?(?:page\.)?waitForTimeout\s*\(\s*\d/, 'wait for a signal (expect(...).toBeVisible / waitForSelector / an event), not a fixed duration'],
  ['sleep-as-sync', /\bsetTimeout\s*\(\s*(?:resolve|res)\b/, 'new Promise(r=>setTimeout(r,N)) as synchronization — wait for the real event or use fake timers'],
  ['sleep-as-sync', /\bawait\s+(?:sleep|delay|wait)\s*\(\s*\d/, 'sleep(N) as synchronization — wait for the causal signal, not a duration'],
  ['wall-clock-assert', /expect\s*\(\s*(?:elapsed|duration|took|delta|ms)\b[^)]*\)\s*\.\s*to(?:Be)?(?:LessThan|GreaterThan)/i, 'asserting a measured duration flakes under CI load — assert causality, not latency'],
  ['shared-tmp-path', /['"`]\/tmp\/(?!.*(?:\$\{|uuid|random|pid|Date\.now))[^'"`]*['"`]/, 'hardcoded /tmp path without uuid/pid — parallel runs trample each other; use mkdtemp'],
  ['focused-test', /\b(?:it|test|describe)\.only\s*\(/, 'a forgotten .only silently disables the rest of the suite'],
  ['retry-masking', /\b(?:retries|retry)\s*[:(]\s*[2-9]/, 'retries ≥2 in a test mask a real flake — fix the cause, don\'t hide it'],
  ['unseeded-random', /\bMath\.random\s*\(/, 'unseeded randomness in a test — failures are unreproducible; fix a seed or use deterministic data'],
  ['float-money-assert', /\.to(?:Be|Equal|StrictEqual)\(\s*-?\d+\.\d+/, 'a float literal in an assertion — for money it\'s a smell (integer minor units!), elsewhere a precision risk'],
];

// File-level patterns: [class, predicate(content) -> anchor line or null, advice].
// They catch line combinations a per-line regex can't see.
const FILE_PATTERNS = [
  ['shared-mock-state',
    (c) => {
      if (!/\b(?:vi|jest)\.mock\s*\(/.test(c)) return null;
      if (!/(?:\.mock\.calls|toHaveBeenCalled)/.test(c)) return null;
      if (/(?:restoreAllMocks|clearAllMocks|resetAllMocks|restoreMocks|clearMocks|mockReset)/.test(c)) return null;
      return c.split('\n').findIndex(l => /(?:\.mock\.calls|toHaveBeenCalled)/.test(l)) + 1;
    },
    'mock + call-count assertions without a reset (clearAllMocks/restoreAllMocks in beforeEach/config) — the top order-dependency class in JS (JS-TOD: 42/55)'],
  ['unseeded-random',
    (c) => {
      if (!/\bfaker\./.test(c)) return null;
      if (/faker\.seed\s*\(/.test(c)) return null;
      return c.split('\n').findIndex(l => /\bfaker\./.test(l)) + 1;
    },
    'faker without faker.seed(N) — data changes between runs, failures are unreproducible'],
];

// allowlist
const allowPath = join(root, '.claude', 'qa', 'flaky-allowlist.txt');
const allow = new Set();
const allowFiles = new Set();
if (existsSync(allowPath)) {
  for (const raw of readFileSync(allowPath, 'utf8').split('\n')) {
    const entry = raw.trim().split(/\s+/)[0];
    if (!entry || entry.startsWith('#')) continue;
    (entry.includes(':') ? allow : allowFiles).add(entry);
  }
}

// walk
const testFiles = [];
const walk = (dir) => {
  let entries;
  try { entries = readdirSync(dir, { withFileTypes: true }); } catch { return; }
  for (const e of entries) {
    if (e.isDirectory()) {
      if (!SKIP_DIRS.has(e.name) && !e.name.startsWith('.')) walk(join(dir, e.name));
    } else if (TEST_FILE.test(e.name) || (TEST_DIR.test(relative(root, dir)) && /\.[cm]?[jt]sx?$/.test(e.name))) {
      testFiles.push(join(dir, e.name));
    }
  }
};
walk(root);

let findings = 0;
const byClass = {};
for (const file of testFiles) {
  const rel = relative(root, file);
  if (allowFiles.has(rel)) continue;
  if (statSync(file).size > 1_000_000) continue;
  const content = readFileSync(file, 'utf8');
  const lines = content.split('\n');
  lines.forEach((line, i) => {
    if (line.trimStart().startsWith('//') || line.trimStart().startsWith('*')) return;
    for (const [cls, re, advice] of PATTERNS) {
      if (re.test(line)) {
        const key = `${rel}:${i + 1}`;
        if (allow.has(key)) continue;
        findings++;
        byClass[cls] = (byClass[cls] || 0) + 1;
        console.log(`FLAKY[${cls}] ${key} — ${line.trim().slice(0, 120)}\n  → ${advice}`);
      }
    }
  });
  for (const [cls, probe, advice] of FILE_PATTERNS) {
    const lineNo = probe(content);
    if (!lineNo) continue;
    const key = `${rel}:${lineNo}`;
    if (allow.has(key)) continue;
    findings++;
    byClass[cls] = (byClass[cls] || 0) + 1;
    console.log(`FLAKY[${cls}] ${key} — ${(lines[lineNo - 1] || '').trim().slice(0, 120)}\n  → ${advice}`);
  }
}

console.log(`\nSCANNED=${testFiles.length} FINDINGS=${findings} ${Object.entries(byClass).map(([k, v]) => `${k}=${v}`).join(' ')}`);
if (findings) console.log(`False positives → ${relative(root, allowPath)} (line: "file:line reason").`);
process.exit(0); // a report for the QA run, not a gate: the agent delivers the verdict
