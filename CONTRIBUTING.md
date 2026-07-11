# Contributing to nazarly-qa

The tool is designed to improve with every run: phase 9 of the command captures friction and proposes changes back to this repo. Human contributions follow the same discipline.

## What makes a good contribution

**Evidence first.** Every change must trace back to a real run: a flow that got cut for the wrong reason, a pattern the static scan missed, a stack the detector didn't recognize, a class of false findings an agent kept producing. "This would be nice" without a run behind it is a discussion, not a PR.

**Lowest possible level.** Fix things at the most machine-checkable layer available, in this order:

1. `lib/*.mjs` / `lib/detect-stack.sh` — a new detector, scan pattern, or diff rule. Deterministic, testable, catches the class forever.
2. `lib/templates/*.md` — a new universal attack class, invariant example, or plan structure.
3. `commands/nazarly-qa.md` — prompt text. Last resort, and only as a rule in this shape: **ban + precise carve-out + one-line cost of violation.** Not "avoid X", but "X is forbidden; the exception is Y with a stated reason; otherwise Z breaks."

**Rails only tighten.** PRs that loosen an existing rail, gate, or P0 attack class need an explicit justification and maintainer sign-off. A QA tool that quietly relaxes its own gates degrades into theater — that's the one failure mode this project refuses.

**Universal only.** Project-specific knowledge (your stand recipe, your flows, your invariants) belongs in your repo's `.claude/qa/`, not here. If a lesson only makes sense for one codebase, it's not a plugin change.

## Mechanics

- Scripts are zero-dependency (plain bash + node). Keep them that way.
- Every script change needs a case in `tests/run.sh` — the smoke suite runs in CI on each PR. New scan patterns need both a positive fixture (flagged) and a negative one (clean file stays clean).
- Scan patterns are conservative by design: better to miss than to spam. If your pattern can misfire, make sure it's allowlistable via `.claude/qa/flaky-allowlist.txt` and say so in the advice string.
- Issue titles for run lessons: `lesson: <slug>`. Body: the friction, the evidence (verdict excerpt / report line), the proposed change and which file it lands in.
- One logical change per PR. Update `CHANGELOG.md` in the same PR.

## Report schema changes

`bugs[].id` slugs and the report JSON schema link runs together — `lib/baseline-diff.mjs` reads the history. Schema changes must be additive (new optional fields only) and handled gracefully for old reports; a diff tool that crashes on last month's report destroys the memory this tool exists to build.
