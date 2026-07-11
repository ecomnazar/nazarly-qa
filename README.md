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
| 3–4. Deterministic | All existing unit/integration/e2e suites against the local stand (units order-shuffled with a recorded seed; a failed test is re-run once in isolation — passed = `flaky_suspect`, not "fixed itself"). Never against production — hard rail. |
| 5. Agentic pass | Subagents fan out per flow (one flow = one fresh app instance), laid across three weight tiers, walk the flows via accessibility tree, collect console errors and failed network requests the whole time, and verify results **by number** for anything money-related. Findings are adversarially re-verified; `confidence: high` requires a working reproduction, and every claim must carry a tool receipt (log / screenshot / SQL output). |
| 6. Risk attacks | Negative money inputs, double-submit idempotency, offline chaos (kill the server mid-operation), power loss (`kill -9` mid-write), migrations on an old-schema dump, backward compat, auth bypass. Each ends in a deterministic check, followed by the applicable invariants. |
| 7. Bug → test | Every high+ bug becomes a **failing test** in your project's own test framework. The test is the report that never goes stale. Invariant-violating bugs also get a guard-script proposal that closes the whole class. |
| 8. Verdict | Teardown first, then the verdict block: flows, attacks, invariants, bugs, refuted + unconfirmed candidates, flakes, escapes, a diff against the previous run (new / fixed / persisting with escalation, QA-SCORE), and a PROD-READY GATE. |
| 9. Retro | The tool improves itself: friction caused by the command (not the project) is captured as a lesson and offered as an issue/PR to this repo. See [CONTRIBUTING.md](CONTRIBUTING.md). |

## The oracle hierarchy

Findings are trusted by how they were caught, top to bottom — and the run is engineered so the cheap, reliable oracles do most of the work:

1. **Invariants** (`invariants.md`) — machine checks after every money flow and attack: `SUM(payments)==total`, no duplicates by UUID. A broken invariant is a confirmed bug immediately; machines don't hallucinate.
2. **Differential oracles** — two independent paths to the same number (client DB ↔ server DB after sync). A mismatch is a bug with no LLM judgment involved.
3. **DOM/data state** — the row appeared, the status changed.
4. **LLM-as-judge** — last resort, and its findings must survive adversarial re-verification plus a working reproduction.

## The memory model

```
your-repo/
└── .claude/qa/
    ├── flows.md       # test plan + stand recipe — committed, edited freely
    ├── risks.md       # attack catalog — committed; one incident = one new attack
    ├── invariants.md  # machine oracle checks + sometimes-goals — committed
    ├── flaky.json     # flake dossier per test — gitignored, local
    └── reports/       # run history (JSON + MD) — gitignored, local
```

Runs are linked by stable bug slugs: the diff tells you what's new, what got fixed, and what has been hanging for N days (with an escalation flag at 3+). The report also tracks **escapes** — production incidents that got past QA — so after ~10 runs the QA-SCORE answers the only question that matters: is this process catching bugs, or is it theater?

## Hard rails

- **Localhost only.** Production URLs and production DBs are forbidden; money flows are never driven against production.
- **Teardown always** — even when tests fail.
- **Isolated runs** — desktop apps get a fresh temp profile; your real data is never touched.
- **No silent fixes** — bugs go to the verdict; code changes only with `--fix`. Failing tests are the one exception: they are always written, because a failing test is a report, not a fix.
- **Nothing installed globally.**

## Using it on a team

The intended workflow for a team that ships together:

1. **One person runs the first full pass** in a repo and commits `.claude/qa/flows.md` + `risks.md` + `invariants.md`. From that moment the test plan, the attack catalog and the invariants are shared team assets — everyone's runs read and update the same memory.
2. **Before handing work in**: `/nazarly-qa --fast` (minutes — typecheck, units with shuffle, scripted e2e, flake triage). Before a release: full `/nazarly-qa` (the agentic pass + P0 attacks are mandatory there).
3. **A bug report from a run = a failing test** already sitting in your test folder. Fix it to green; commit the test first (red), the fix second (green) — the diff of the next run will show it as FIXED.
4. **After any production incident**: add one row to `risks.md` (incident → attack) and, if it's invariant-shaped, to `invariants.md` — before hotfixing anything else. A bug that bites twice is a process failure.
5. **Don't argue with the gate in chat** — a `ship-with-gaps` verdict names the exact uncovered flow/attack. Either cover it or consciously accept the gap in writing (it's in the report either way).

The memory files are plain markdown — edit them by hand freely; the tool treats your edits as the source of truth.

## Requirements

- [Claude Code](https://claude.com/claude-code) with plugin support
- Node.js 18+ (the detector and diff tool are plain bash + node, zero dependencies)
- macOS or Linux (Windows: WSL)
- Your project's own toolchain (docker for the DB if the project uses one)

## Contributing

The tool is built to learn from its own runs: phase 9 of every run captures friction caused by the command itself and offers to turn it into an issue or PR here. Human contributions follow the same shape — see [CONTRIBUTING.md](CONTRIBUTING.md). Short version: bring the evidence from a real run, put the fix at the lowest possible level (script > template > prompt text), never weaken a rail.

## Roadmap

- `--ci` mode: headless run in GitHub Actions as a PR gate (exit code = verdict, JSON report as artifact)
- Coverage accounting: "P0 flows with a deterministic test: 7/9" in the verdict
- An app map with coverage marks + plan caching for the agentic pass (fewer tokens, gap-driven exploration)
- Visual regression: aria snapshots / screenshot diffs between runs
- Optional a11y pass (axe-core)

## License

MIT © Nazar ([Nazarly Digital](https://github.com/ecomnazar))
