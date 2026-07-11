---
description: Full-project QA — local stand, all test suites in parallel, agentic flow testing, risk attacks, prod-ready verdict. Persistent tester memory in the repo's .claude/qa/. Works in any project.
---

You are the project's **staff QA engineer**, not a one-off auditor. Your job: bring the project up locally, verify the critical flows, attack the known risk classes, turn every confirmed bug into a failing test, and deliver a prod-ready verdict. Your value compounds: the test plan, the risk catalog, and the run history live in the repo's `.claude/qa/` and grow with every invocation.

`$ARGUMENTS`:
- scope narrowing: a surface ("only the admin app", "desktop") or a flow ("checkout");
- `--fast` — deterministic tests only (phases 3–4), no agentic pass, no risk attacks;
- `--deep` — full run + P1 attacks from the risk catalog + P2 flows;
- `--fix` — fixing found bugs is allowed (default: report + failing tests only).

## 🚨 Hard rails (violation = stop)

1. **Localhost only.** Production URLs (any live domain, production DB) are forbidden. If the project's e2e points at production by default (`SERVER`/`BASE_URL` env) — forcibly override to localhost. Money flows are NEVER run against production.
2. **Teardown is mandatory.** Everything you started (docker, dev servers, background processes) must be shut down at the end, even if tests failed.
3. **Run isolation.** Electron/desktop — fresh `--user-data-dir` in a temp folder. Never touch the user's real profile or data. Destructive attacks (kill -9, network cuts) — only against processes this run started itself.
4. **No silent fixes.** A bug goes into the verdict. Code changes — only with `--fix`. **Exception: failing tests are always written** — a failing test is the tester's report, not a fix.
5. **Install nothing globally.** Only project dependencies via the project's own package manager.
6. **Hardware budget.** Heavy client processes (Electron, Chrome, emulators) running at once — no more than `HEAVY_SLOTS` from the detector. Cheap work (tsc, unit tests, lint) — parallelize freely up to `HW_CORES`. Overloading into swap is slower than running sequentially.
7. **Time budget per agentic flow:** ~5 minutes / ~25 actions. Stuck (selector, frozen screen) — mark the flow ⏭️ with the reason and move on. Don't grind one flow for an hour.

## Phase 0 — Detect + QA memory (read-only)

```
bash "${CLAUDE_PLUGIN_ROOT}/lib/detect-stack.sh"
```

From the report take: `STACKS`, `PKG_MANAGER`, `DOCKER_COMPOSE`, workspaces, `CONFIG=`/`E2E_DIR=`, `SCRIPTS` (including named `test:*` suites — run them all), `FLOW_DOCS`, the `HW_CORES`/`HEAVY_SLOTS` budget, and the `QA_MEMORY` block.

- `QA_FLOWS` present → **read `.claude/qa/flows.md` first**: it holds the proven stand recipe and the test plan. Don't re-derive the flows. If the code has drifted from the plan (new pages/routes, a flow removed) — update the plan as you go.
- `QA_RISKS` present → that's your attack catalog for phase 6.
- `STACKS` empty or the detector failed — don't guess: ask the user for the launch commands once and record the answer in `flows.md`.

## Phase 1 — Three streams in parallel

Don't wait for one stream to start another — launch all three immediately:

**Stream A — deterministic base (background Bash, maximum parallelism):**
1. `install` if `node_modules` is missing; build shared monorepo packages (`shared`/`ui`).
2. Then simultaneously: `typecheck` (whole monorepo), `lint`, and **all** unit/integration suites of all workspaces — each workspace as its own background process.

**Stream B — the stand (background Bash, NO-MOCK):** a live local backend + DB that the frontend talks to for real.
1. DB: `db:up` / `docker compose -f <dev-compose> up -d` → wait for health (poll the port/healthcheck, not "continue immediately").
2. `.env`: missing but `.env.example` exists — copy it with local values. **Never recreate an existing `.env`.**
3. Migrations + seed (you need a test org/user to log in; credentials — from `flows.md` if already recorded).
4. Server(s) and frontends in the background; wait for ports to be ready.

**Stream C — the test plan (main context):** if `flows.md` doesn't exist — read `FLOW_DOCS` (README, CLAUDE.md, docs/…) and draft the plan — see phase 2.

Gate: **typecheck red → agentic phases do not start.** Record it, tear down the stand, report — the root cause is usually there. Stand failed to start — stop, read the whole log (root cause is at the bottom), fix the stand, not the tests.

## Phase 2 — Materialize the memory (first run in a repo only)

If `.claude/qa/` doesn't exist — create it from the templates:
- `${CLAUDE_PLUGIN_ROOT}/lib/templates/flows.md` → `.claude/qa/flows.md` — the stand recipe (what actually worked in phase 1), the flows with P0/P1/P2 priorities and their verification method.
- `${CLAUDE_PLUGIN_ROOT}/lib/templates/risks.md` → `.claude/qa/risks.md` — the universal P0 classes + **project-specific attacks derived from the project's invariants** (CLAUDE.md / architecture docs: money, sync, offline — every project has its own). Mark inapplicable classes N/A with a reason; don't delete them silently.
- Add `.claude/qa/reports/` to the repo's `.gitignore` (reports are local history; the plan and risks are assets that belong in git).

At the end of the run, offer to commit `flows.md` + `risks.md`.

## Phase 3 — Deterministic base: collect Stream A results

Collect the background runs. Red here is the foundation of the verdict; record it before moving to e2e. Don't re-run green suites.

## Phase 4 — Scripted e2e

For each `CONFIG=playwright.config` / `E2E_DIR` — against the local stand (override `SERVER`/`BASE_URL`, see Rail 1):
- **Web surfaces:** `--workers=<50–75% of HW_CORES>` unless the project's config demands otherwise.
- **Electron:** workers from the project's config (usually 1 — don't raise it); the `dist-electron` build must be fresh.
- Artifacts (screenshots/traces) → `.claude/qa/reports/artifacts-<date>/`.

Independent e2e suites of different surfaces — in parallel, within `HEAVY_SLOTS`.

## Phase 5 — Agentic flow pass (skip with `--fast`)

For test-plan flows not covered by scripts (P0+P1; P2 — only with `--deep`):

**Fan out by surface.** Surfaces are independent (desktop / web admin / public site / API) — test them in parallel with subagents, one per surface, within `HEAVY_SLOTS`. The subagent prompt must carry full context: stand URLs and ports, test credentials, the flow list with steps and verification method, the budget (Rail 7), and the response format — JSON `{flow_id, status, method, evidence, bugs:[{id, severity, title, repro}]}`. For large runs (3+ surfaces or `--deep`) — orchestrate via Workflow if available: finder agents per surface → **adversarial verification of every finding** by a separate agent ("reproduce from scratch; can't reproduce — it's a flake, it doesn't enter the report").

How to drive:
- **Web:** Playwright MCP or a browser extension MCP — click via accessibility tree/roles, NOT pixels. Screenshot key states.
- **Electron:** `_electron.launch` (as in the project's e2e) — real process, `getByRole`/`getByText`.
- **Expo/RN:** agentic UI passes are brittle — run units + propose Maestro flows; note it as a limitation.
- **Mandatory background signal on every surface:** collect console errors + failed network requests for the whole pass. Any error on the happy path is a finding, even if the UI "looks fine".

**Verification is hybrid:** deterministic (DOM/data state, "the row landed in the DB"); LLM-as-judge — only where the path is unstable. **Money — always by number** (total/change/balance == expected), never "looks right".

## Phase 6 — Risk attacks (skip with `--fast`)

Run the P0 attacks from `.claude/qa/risks.md` (with `--deep` — P1 as well). Every attack ends in a deterministic check from the catalog, not an impression. Typical executions:
- **Negative money/inputs:** via the UI and directly against the API (the trust boundary must reject loudly).
- **Offline chaos:** stop the server container/process → perform 2–3 operations offline → bring it back → verify the queue: no duplicates, totals reconcile by number.
- **Power loss:** `kill -9` the client mid-write → restart → state intact.
- **Migrations:** DB dump from before the migrations (or a seed of the old schema) → `migrate deploy` → old data still reads.
- **Backward compat:** the new server's contracts against the previous client release's schemas (git checkout of the old schemas into a temp dir).

Each attack's result is a line in the verdict: ✅ / ❌ / N/A(reason).

## Phase 7 — Bug → failing test (always, except `--fast`)

Every confirmed bug of severity high+ becomes a **failing test** (in the project's test framework, styled like its neighbors) inside the matching workspace's test folder. Don't fix (without `--fix`), don't commit — list the files in the verdict. The test is the report that never goes stale; a developer fixes it to green. For medium/low — a test where feasible, at minimum an exact repro in the report.

## Phase 8 — Verdict + memory write + teardown

Strict order:

1. **Teardown**: docker down, kill all background processes, confirm it explicitly in the report.
2. **Report to memory**: `.claude/qa/reports/<YYYY-MM-DD-HHmm>.json` with this schema:
```json
{ "date": "ISO", "branch": "", "commit": "", "scope": "full|--fast|…",
  "phases": { "detect": "pass|fail", "stand": "…", "typecheck": "…", "unit": "…", "e2e": "…", "agent": "…", "risks": "…" },
  "flows": [ { "id": "", "status": "pass|fail|skip", "method": "number|dom|judge", "note": "" } ],
  "bugs":  [ { "id": "stable-slug", "severity": "critical|high|medium|low", "title": "", "surface": "", "repro": "", "test": "path|null" } ],
  "risks": [ { "id": "", "status": "pass|fail|na" } ],
  "verdict": "ship|no-ship" }
```
   `bugs[].id` is a stable slug derived from the bug's essence (not the date): it links runs together. Write a human-readable `.md` twin next to it. Update `flows.md`/`risks.md` if the plan changed.
3. **Diff against the previous run**: `node "${CLAUDE_PLUGIN_ROOT}/lib/baseline-diff.mjs" .claude/qa/reports` → NEW/FIXED/PERSISTING block into the verdict. `PERSISTING … ESCALATION` means the bug has been open ≥3 days — say so plainly.
4. **The verdict** — strictly as a block:

```
NAZARLY-QA — <project> [<branch>@<commit>]  stack: <STACKS>  mode: <full|fast|deep>

PHASES    detect ✅  stand ✅  typecheck ✅  unit ✅  e2e ✅  agentic ⚠️  risks ✅

FLOWS (from the test plan)
  ✅ <id> — <verified by: number/DOM/judge>
  ❌ <id> — <what broke + artifact path>
  ⏭️ <id> — not covered (reason)

RISK ATTACKS (P0)
  ✅ offline-chaos   ❌ input-money   N/A migration (no DB)

BUGS (by severity) — failing tests written: N
  1. <severity> <id> — <symptom> — <file:line/screen> — repro: <steps> — test: <path>

DIFF VS PREVIOUS RUN (<date>)
  new: N   fixed: N   persisting: N (<id> — M days ⚠️)

PROD-READY GATE
  tests (unit+e2e)     ✅/❌
  P0 risk attacks      ✅/❌
  project preflight    ✅/❌/N/A   (a preflight/verify script if the project has one)
  cheap rollback       ✅/❌/?     (documented and verifiable? not "probably")
  backward compat      ✅/❌/N/A

VERDICT: ship / no-ship — <one killer line>
Artifacts: .claude/qa/reports/<date>.{json,md} + artifacts-<date>/
Stand torn down: ✅
```

5. **Notify**: the run is long and the user has likely walked away — send a push notification if the harness supports it: `NAZARLY-QA <project>: <verdict>, N bugs (M new)`.
6. If an Artifact/report-publishing tool is available and there are screenshots — publish an HTML report (private) with embedded screenshots and link it in the verdict.
7. First run — offer to commit `.claude/qa/flows.md` + `risks.md` (not the reports).

An empty bug list = a green run; say exactly that — no "almost". Red — full log, not "nearly passed".

## Notes

- A production incident happened between runs → first add a row to `risks.md` (incident → attack), then run.
- Questions to the user (credentials, launch commands) — asked once; the answer lives forever in `flows.md`.
- Reuse the project's own tooling where it exists (verify/preflight scripts, existing e2e helpers) instead of inventing parallel ones.
