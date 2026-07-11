# QA — invariant oracles: {{PROJECT}}

<!-- /nazarly-qa memory. Machine checks with a deterministic answer:
     SQL against the local/server DB, curl against the API, a script.
     They run after every money flow and every risk attack. A broken
     invariant = a confirmed bug IMMEDIATELY, no adversarial verification —
     machines don't hallucinate.
     Sources: CLAUDE.md / architecture docs / production incidents. -->

Updated: {{DATE}} (commit {{COMMIT}})

Filling rules:
- One row = one check runnable as ONE command with an unambiguous answer
  (a number matches / 0 rows / an HTTP code). Nothing "eyeballed".
- Differential oracles are gold: two independent paths to the same number
  (client DB ↔ server DB after sync; a report ↔ a recount from raw rows).
  A mismatch is a bug even when both paths "look fine".
- An invariant born from a production incident carries the incident link —
  it runs first.

## Global invariants (after every money flow and every attack)

| ID | Invariant (which rule it guards) | Check (command/SQL) | Expected |
|---|---|---|---|
| {{INV_ID}} | {{INVARIANT_RULE}} | `{{CHECK_CMD}}` | {{EXPECTED}} |

<!-- Examples for a typical money/sync project (replace with yours):
| sum-payments | SUM(payments)==total per receipt | SELECT s.id FROM sales s JOIN (SELECT sale_id, SUM(amount) a FROM sale_payments GROUP BY sale_id) p ON p.sale_id=s.id WHERE p.a != s.total AND s.status='completed' | 0 rows |
| no-uuid-dup | Sync idempotency: no duplicates by UUID | SELECT id, COUNT(*) FROM sales GROUP BY id HAVING COUNT(*)>1 | 0 rows |
| money-integer | Money is integer; a float in the DB is impossible | SELECT COUNT(*) FROM sales WHERE total != ROUND(total) | 0 |
| client-server-parity | Differential: local DB == server DB after sync | script: totals/counters for the day from SQLite and from Postgres | numbers equal |
-->

## Sometimes-goals (reach at least once per full run)

<!-- The Antithesis pattern: interesting states that must be reachable.
     Not reached during a run — that's a finding in itself (a dead feature
     or a blind spot in the test plan), a line in "NOT COVERED". -->

| ID | State | How to reach it | Reached last run |
|---|---|---|---|
| {{GOAL_ID}} | {{STATE}} | {{HOW}} | ✅/❌ |

## Incidents → invariants

| Date | Incident | Descendant invariant (ID above) |
|---|---|---|
| {{DATE}} | {{INCIDENT}} | {{INV_ID}} |
