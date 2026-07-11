# Changelog

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
