# Changelog

## [1.0.0] — 2026-07-11

Initial public release.

- `/nazarly-qa` command: 8-phase QA run — detect, parallel start (typecheck/unit/stand), memory materialization, deterministic suites, scripted e2e, agentic flow pass with per-surface fan-out, risk attacks, bug→failing-test, prod-ready verdict.
- `lib/detect-stack.sh` — read-only stack detector: workspaces, named test suites, test configs, hardware parallelism budget (`HEAVY_SLOTS`), per-repo QA memory discovery.
- `lib/baseline-diff.mjs` — run-over-run diff: new / fixed / persisting bugs (with ≥3-day escalation), flow regressions.
- Templates for the per-repo test plan (`flows.md`) and risk catalog (`risks.md`).
- Flags: `--fast`, `--deep`, `--fix`, free-text scope narrowing.
