# QA — risk catalog: {{PROJECT}}

<!-- /nazarly-qa memory. The universal classes below are the starter set; the
     command derives project-specific attacks from the project's invariants
     (CLAUDE.md / architecture docs / spec). After every production incident
     a successor attack is added here: one incident = one new row.
     A bug that bites twice is a process failure. -->

Updated: {{DATE}}

## P0 — mandatory attacks (every full run)

Mark a row N/A with a reason if the class doesn't apply — never delete it silently.

| ID | Class | Attack | Deterministic check |
|---|---|---|---|
| input-money | Negative inputs | NaN / float / negative / 1e15 / empty into every money and qty field | input rejected at the boundary (fail loud), DB state unchanged |
| input-bounds | Boundary values | empty cart/form, max lengths, unicode/emoji in text fields | no crash, no 500, sane validation |
| double-submit | Idempotency | double-click the CTA, replay a request with the same ID | exactly one record, money not doubled |
| offline-chaos | Offline/sync | kill the server mid-operation → keep working offline → bring the server back | queue drains without duplicates, totals reconcile **by number** |
| power-loss | Crash resilience | `kill -9` the client process mid-write → restart | local state intact, last operation neither lost nor doubled |
| migration | Migrations | apply migrations to a dump of the previous schema (not just a fresh DB) | migration succeeds, old data still reads |
| backward-compat | Backward compatibility | new server's contracts against the previous client release's schemas | old client keeps working: additivity not broken |
| auth-bypass | Authorization | protected endpoints without a token / with a wrong role / expired token | 401/403, not 200 and not 500 |
| console-clean | Runtime hygiene | the whole agentic pass collects console errors + failed network requests | zero unexplained errors on the happy path |

## P1 — with the `--deep` flag

| ID | Class | Attack | Check |
|---|---|---|---|
| perf-smoke | Performance | catalog/list with 1000+ records | interactive < 3s, no list freezes |
| i18n-full | Localization | key flows in every language | no raw keys/truncation, layout holds |
| restore | Backup/restore | restore from the latest backup | app works, data intact |

## Project-specific attacks (derived from invariants)

| ID | Source invariant | Attack | Check |
|---|---|---|---|
| {{RISK_ID}} | {{INVARIANT}} | {{ATTACK}} | {{CHECK}} |

## Incidents → attacks

| Date | Incident (short) | Successor attack (ID above) |
|---|---|---|
| {{DATE}} | {{INCIDENT}} | {{RISK_ID}} |
