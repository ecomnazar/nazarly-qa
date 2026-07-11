# Changelog

## [1.2.0] — 2026-07-11

Research-driven upgrade: four survey passes over 2024–2026 testing practice (agentic QA, property/mutation/chaos, flake management, e2e/sync) distilled into the run. Theme: cheap deterministic machines catch the bugs; the LLM orchestrates.

- **Invariant oracles** (new phase 5–6 block + `lib/templates/invariants.md` → `.claude/qa/invariants.md`): machine checks (SQL/curl/script) run after every money flow and attack. Oracle trust hierarchy: invariant → differential → DOM → LLM-judge. A bug caught by an invariant needs no adversarial verification.
- **A bug exists only with a reproduction** (AnyPoC/tool-receipts pattern): `confidence: high` requires a working repro; not reproduced in 2–3 attempts → `unconfirmed[]`, not `bugs[]`. Every `evidence` must be a tool artifact from this run.
- **Flake dynamics** on top of the static scan: unit suites run order-shuffled with a recorded seed; new/changed test files stressed ×5; a failed test is re-run once in isolation on the same SHA (passed = `flaky_suspect`, not "fixed itself"); per-test dossier in `.claude/qa/flaky.json`, 2+-run repeats become mandatory fix candidates.
- **New static scan patterns** in `lib/check-flaky-patterns.mjs` (new script): `shared-mock-state` (mock + call-count asserts without a reset — the top JS order-dependency class), `unseeded-random` (Math.random / unseeded faker), `float-money-assert`.
- **Escape rate** — the process's headline metric: `escapes[]` in the report (prod incidents since the previous run + an honest "should QA have caught it"), `QA-SCORE` and `THEATER-SIGNAL` in `baseline-diff.mjs`, a new "escapes closed" line in the PROD-READY GATE.
- **Phase 9 — self-improvement retro**: every run captures one lesson about the tool itself (not the project) and offers to open an issue/PR here. Rails only tighten. New `CONTRIBUTING.md` codifies the shape.
- Report schema (additive): `shuffle_seed`, `invariants[]`, `unconfirmed[]`, `flaky_suspects[]`, `escapes[]`, `metrics{}`, plus `confidence`/`class`/`evidence`/`suggested_fix` on bugs and `refuted[]`/`uncovered[]` (previously prompt-only).
- Phase 2 now backfills memory files added by newer plugin versions into repos that already have `.claude/qa/`.
- Phase 7: the failing test must fail *for the bug's reason*; invariant-violating bugs also get a guard-script proposal that closes the whole class.
- `baseline-diff.mjs`: `REFUTED_REPEAT`, `COVERAGE_REGRESS` ratchet (same-scope runs only), `UNCOVERED`, `FLAKY_REPEAT`.
- Smoke suite: 36 checks (was 20) — new script covered with positive and negative fixtures.

## [1.1.0] — 2026-07-11

Methodology hardening from a real run (a QA pass that only hit ~40% coverage exposed two failure modes).

- **Fan out by flow, not by surface** (phase 5). One agent per surface running flows back-to-back cascades: a failed flow's leftover overlay skips the whole tail. Now one flow = one fresh app instance, laid out across three weight tiers (light API attacks / medium headless-browser / heavy Electron), orchestrated via Workflow by default for `full`.
- **One flow = one fresh instance; parallel money flows each in their own seed org** (rail 3) — prevents cascade skips and cross-flow data contamination in reports/shifts/receipt numbering.
- **Three-tier hardware budget** (rail 6): heavy ≤ `HEAVY_SLOTS`, medium 3–4, light (no-UI API attacks) mass-parallel. "Max agents" is not unlimited.
- **P0 force-majeure attacks are mandatory** (phase 6): offline-chaos / power-loss / migration / backward-compat / start-race can't be skipped "for budget" — a skipped P0 downgrades the verdict to `ship-with-gaps`, not a silent `N/A`.
- New verdict tier `ship-with-gaps` + `p0_executed: N/M` in the report schema; added a "money flows by number" gate line.
- Adversarial verification now checks a finding's claimed **scope/root-cause**, not just the symptom (guards against inflated "never works anywhere" claims).
- New risk classes in the template catalog: `type-overflow` (column-type upper bounds, e.g. INT4) and `start-race` (first action before the first sync/pull completes).

## [1.0.0] — 2026-07-11

Initial public release.

- `/nazarly-qa` command: 8-phase QA run — detect, parallel start (typecheck/unit/stand), memory materialization, deterministic suites, scripted e2e, agentic flow pass with per-surface fan-out, risk attacks, bug→failing-test, prod-ready verdict.
- `lib/detect-stack.sh` — read-only stack detector: workspaces, named test suites, test configs, hardware parallelism budget (`HEAVY_SLOTS`), per-repo QA memory discovery.
- `lib/baseline-diff.mjs` — run-over-run diff: new / fixed / persisting bugs (with ≥3-day escalation), flow regressions.
- Templates for the per-repo test plan (`flows.md`) and risk catalog (`risks.md`).
- Flags: `--fast`, `--deep`, `--fix`, free-text scope narrowing.
