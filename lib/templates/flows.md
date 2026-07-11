# QA — test plan: {{PROJECT}}

<!-- /nazarly-qa memory. This file is a project asset: the command reads it
     instead of re-scouting and updates it when the code drifts. Edit freely. -->

Updated: {{DATE}} (commit {{COMMIT}})

## Stand recipe (proven)

- Install: `{{INSTALL}}`
- DB: `{{DB_UP}}` — health check: {{DB_HEALTH}}
- .env: {{ENV_NOTES}}
- Migrations/seed: `{{MIGRATE_SEED}}` — test credentials: {{TEST_CREDS}}
- Launch: {{RUN_RECIPE}}
- Ports: {{PORTS}}
- Gotchas: {{GOTCHAS}}

## Flows

Priorities: **P0** — money/data/auth, run every time.
**P1** — main user flows. **P2** — rare, `--deep` only.

| ID | Prio | Surface | Flow (steps) | Verification | Coverage |
|---|---|---|---|---|---|
| {{FLOW_ID}} | P0 | {{SURFACE}} | {{STEPS}} | number: {{CHECK}} | script `{{TEST_FILE}}` / agent |

Filling rules:
- "Verification" — deterministic wherever possible: a **number** (total, balance, count),
  **DOM/data** (row appeared, status changed), **judge** — only where the path is unstable.
- "Coverage" — what checks it: an existing scripted test (path) or the agentic pass.
  A flow without a scripted test is a candidate for materialization into one.

## Known limitations

- {{LIMITATION}}
