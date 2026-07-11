# nazarly-qa

**A staff QA engineer for Claude Code — not a one-off audit.** One command brings your project up locally, runs every test suite in parallel, walks the critical user flows like a real tester, attacks the known risk classes (money math, offline sync, power loss, migrations), turns every confirmed bug into a failing test, and hands you a prod-ready verdict.

Its value compounds: the test plan, the risk catalog, and the run history live in your repo and grow with every invocation. A bug that bites twice is a process failure — this tool is built around that rule.

```
NAZARLY-QA — my-shop [main@9e50daa]  stack: web-next server-nest  mode: full

PHASES    detect ✅  stand ✅  typecheck ✅  unit ✅  e2e ✅  agentic ⚠️  risks ✅

FLOWS (from the test plan)
  ✅ checkout-card — verified by number: total == 12 400
  ❌ refund-full   — 500 on POST /refunds + artifacts/refund-500.png
  ⏭️ export-csv    — not covered (no test data for empty period)

RISK ATTACKS (P0)
  ✅ offline-chaos   ✅ input-money   ✅ double-submit   N/A migration (no DB)

BUGS (by severity) — failing tests written: 1
  1. high refund-500 — POST /refunds 500 on refunded order — api/refunds.ts:84
     repro: refund the same order twice — test: tests/refund-double.test.ts

DIFF VS PREVIOUS RUN (2026-07-08)
  new: 1   fixed: 2   persisting: 0

PROD-READY GATE
  tests (unit+e2e)     ✅
  P0 risk attacks      ✅
  project preflight    ✅
  cheap rollback       ✅
  backward compat      N/A

VERDICT: no-ship — refund flow 500s on a real user path; fix the failing test first
Stand torn down: ✅
```

## Install

```
/plugin marketplace add ecomnazar/nazarly-qa
/plugin install nazarly-qa@nazarly-qa
```

Then, in any project:

```
/nazarly-qa                  # full run
/nazarly-qa --fast           # deterministic tests only (typecheck, unit, scripted e2e)
/nazarly-qa --deep           # + P1 risk attacks, P2 flows, adversarial verification
/nazarly-qa only the admin   # narrow the scope to one surface or flow
/nazarly-qa --fix            # allow it to fix what it finds (default: report only)
```

## What it actually does

| Phase | What happens |
|---|---|
| 0. Detect | Read-only stack detector: package manager, monorepo layout, every workspace, every test config, **every named test suite** (`test:money`, `e2e:smoke` — the ones generic runners silently miss), docker compose files, flow docs, and a hardware budget (`HEAVY_SLOTS`) so parallelism never swaps your machine to death. |
| 1. Parallel start | Three streams at once: typecheck+lint+all unit suites (background, max parallel), the local stand (DB → env → migrations → seed → servers), and the test plan. Typecheck red → agentic phases don't start. |
| 2. Memory | First run materializes `.claude/qa/flows.md` (test plan + proven stand recipe) and `.claude/qa/risks.md` (attack catalog) in your repo. Both are assets that belong in git. |
| 3–4. Deterministic | All existing unit/integration/e2e suites against the local stand. Never against production — hard rail. |
| 5. Agentic pass | Subagents fan out per surface (web / desktop / API), walk the flows via accessibility tree, collect console errors and failed network requests the whole time, and verify results **by number** for anything money-related. Findings are adversarially re-verified — flakes don't reach the report. |
| 6. Risk attacks | Negative money inputs, double-submit idempotency, offline chaos (kill the server mid-operation), power loss (`kill -9` mid-write), migrations on an old-schema dump, backward compat, auth bypass. Each ends in a deterministic check. |
| 7. Bug → test | Every high+ bug becomes a **failing test** in your project's own test framework. The test is the report that never goes stale. |
| 8. Verdict | Teardown first, then the verdict block: flows, attacks, bugs, a diff against the previous run (new / fixed / persisting with escalation), and a PROD-READY GATE. |

## The memory model

```
your-repo/
└── .claude/qa/
    ├── flows.md      # test plan + stand recipe — committed, edited freely
    ├── risks.md      # attack catalog — committed; one incident = one new attack
    └── reports/      # run history (JSON + MD) — gitignored, local
```

Runs are linked by stable bug slugs: the diff tells you what's new, what got fixed, and what has been hanging for N days (with an escalation flag at 3+).

## Hard rails

- **Localhost only.** Production URLs and production DBs are forbidden; money flows are never driven against production.
- **Teardown always** — even when tests fail.
- **Isolated runs** — desktop apps get a fresh temp profile; your real data is never touched.
- **No silent fixes** — bugs go to the verdict; code changes only with `--fix`. Failing tests are the one exception: they are always written, because a failing test is a report, not a fix.
- **Nothing installed globally.**

## Requirements

- [Claude Code](https://claude.com/claude-code) with plugin support
- Node.js 18+ (the detector and diff tool are plain bash + node, zero dependencies)
- macOS or Linux (Windows: WSL)
- Your project's own toolchain (docker for the DB if the project uses one)

## Roadmap

- `--ci` mode: headless run in GitHub Actions as a PR gate (exit code = verdict, JSON report as artifact)
- Coverage accounting: "P0 flows with a deterministic test: 7/9" in the verdict
- Flake quarantine: tests flapping across runs get flagged instead of blocking the gate
- Visual regression: screenshot diffs between runs
- Optional a11y pass (axe-core)

## License

MIT © Nazar ([Nazarly Digital](https://github.com/ecomnazar))
