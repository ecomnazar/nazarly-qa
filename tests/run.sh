#!/usr/bin/env bash
# Smoke tests for nazarly-qa lib scripts. Exit non-zero on any failure.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
LIB="$HERE/../lib"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

FAIL=0
check() { # check <label> <haystack> <needle>
  if echo "$2" | grep -qF "$3"; then
    echo "  ok: $1"
  else
    echo "  FAIL: $1 — expected to find: $3"
    FAIL=1
  fi
}

echo "== detect-stack.sh =="
# fixture: a tiny monorepo-ish project
mkdir -p "$TMP/proj/apps/web"
cat > "$TMP/proj/package.json" <<'EOF'
{ "name": "fixture", "scripts": { "typecheck": "tsc", "test": "vitest run", "test:money": "vitest run money", "db:up": "docker compose up -d" } }
EOF
cat > "$TMP/proj/apps/web/package.json" <<'EOF'
{ "name": "fixture-web",
  "dependencies": { "next": "14.0.0" },
  "devDependencies": { "@playwright/test": "1.40.0" },
  "scripts": { "dev": "next dev", "e2e:smoke": "playwright test" } }
EOF
touch "$TMP/proj/pnpm-lock.yaml" "$TMP/proj/pnpm-workspace.yaml" "$TMP/proj/README.md"
OUT=$(bash "$LIB/detect-stack.sh" "$TMP/proj")
check "package manager"        "$OUT" "PKG_MANAGER=pnpm"
check "monorepo"               "$OUT" "MONOREPO=pnpm-workspaces"
check "next detected"          "$OUT" "STACKS=web-next"
check "playwright flagged"     "$OUT" "+playwright"
check "named test suite kept"  "$OUT" "test:money="
check "named e2e suite kept"   "$OUT" "e2e:smoke="
check "hardware budget"        "$OUT" "HEAVY_SLOTS="
check "qa memory block"        "$OUT" "QA_REPORT_COUNT=0"
check "flow docs"              "$OUT" "DOC=README.md"

echo "== baseline-diff.mjs =="
R="$TMP/reports"; mkdir -p "$R"
cat > "$R/2026-01-01-1200.json" <<'EOF'
{"date":"2026-01-01T12:00:00","scope":"full","bugs":[{"id":"a","severity":"high","title":"bug A"},{"id":"b","severity":"low","title":"bug B"}],
 "flows":[{"id":"f1","status":"pass"}],"refuted":[{"id":"ghost","reason":"not real"}],
 "flaky_suspects":[{"test":"x.test.ts > y","detail":"seed 1"}]}
EOF
cat > "$R/2026-01-05-1200.json" <<'EOF'
{"date":"2026-01-05T12:00:00","scope":"full","bugs":[{"id":"a","severity":"high","title":"bug A"},{"id":"c","severity":"critical","title":"bug C"}],
 "flows":[{"id":"f1","status":"fail"}],"refuted":[{"id":"ghost","reason":"still not real"}],
 "unconfirmed":[{"id":"maybe","attempts":3}],
 "flaky_suspects":[{"test":"x.test.ts > y","detail":"seed 2"}],
 "escapes":[{"incident":"prod 500 on refund","date":"2026-01-04","qa_should_have_caught":true,"why_missed":"no such attack"}]}
EOF
OUT=$(node "$LIB/baseline-diff.mjs" "$R")
check "diff mode"        "$OUT" "BASELINE=diff"
check "new bug"          "$OUT" "NEW: c (critical)"
check "fixed bug"        "$OUT" "FIXED: b"
check "persisting bug"   "$OUT" "PERSISTING: a (high)"
check "escalation flag"  "$OUT" "ESCALATION"
check "flow regression"  "$OUT" "FLOW_REGRESSION: f1"
check "refuted repeat"   "$OUT" "REFUTED_REPEAT: ghost"
check "coverage regress" "$OUT" "COVERAGE_REGRESS: pass flows 1→0"
check "escape line"      "$OUT" "ESCAPE: prod 500 on refund"
check "escape verdict"   "$OUT" "QA should have caught it: YES"
check "qa score"         "$OUT" "QA-SCORE (whole history, 2 runs)"
check "flaky repeat"     "$OUT" "FLAKY_REPEAT: x.test.ts > y"
check "summary counters" "$OUT" "unconfirmed=1 flaky_suspects=1"

OUT=$(node "$LIB/baseline-diff.mjs" "$TMP/nonexistent")
check "missing dir"      "$OUT" "BASELINE=no-reports-dir"
mkdir -p "$TMP/empty"
OUT=$(node "$LIB/baseline-diff.mjs" "$TMP/empty")
check "empty dir"        "$OUT" "BASELINE=first-run"

echo "== check-flaky-patterns.mjs =="
F="$TMP/flaky-proj"; mkdir -p "$F/tests"
cat > "$F/tests/bad.test.ts" <<'EOF'
import { vi } from 'vitest';
vi.mock('./api');
test('sleeps', async () => {
  await page.waitForTimeout(500);
  const n = Math.random();
  expect(api.mock.calls.length).toBe(1);
  expect(total).toBe(10.5);
});
test.only('focused', () => {});
EOF
cat > "$F/tests/good.test.ts" <<'EOF'
test('waits for signal', async () => {
  await expect(page.getByRole('button')).toBeVisible();
  expect(total).toBe(1050);
});
EOF
OUT=$(node "$LIB/check-flaky-patterns.mjs" "$F")
check "sleep-as-sync"     "$OUT" "FLAKY[sleep-as-sync] tests/bad.test.ts"
check "focused test"      "$OUT" "FLAKY[focused-test]"
check "unseeded random"   "$OUT" "FLAKY[unseeded-random]"
check "float money"       "$OUT" "FLAKY[float-money-assert]"
check "shared mock state" "$OUT" "FLAKY[shared-mock-state]"
check "scan summary"      "$OUT" "SCANNED=2"
if echo "$OUT" | grep -qF "good.test.ts"; then
  echo "  FAIL: clean file flagged"; FAIL=1
else
  echo "  ok: clean file not flagged"
fi
# allowlist silences a finding
mkdir -p "$F/.claude/qa"
echo "tests/bad.test.ts known legacy file" > "$F/.claude/qa/flaky-allowlist.txt"
OUT=$(node "$LIB/check-flaky-patterns.mjs" "$F")
check "allowlist works"   "$OUT" "FINDINGS=0"

echo "== detect-stack.sh: QA memory files =="
mkdir -p "$TMP/proj/.claude/qa"
echo x > "$TMP/proj/.claude/qa/flows.md"
echo x > "$TMP/proj/.claude/qa/invariants.md"
echo '{}' > "$TMP/proj/.claude/qa/flaky.json"
OUT=$(bash "$LIB/detect-stack.sh" "$TMP/proj")
check "invariants detected" "$OUT" "QA_INVARIANTS=.claude/qa/invariants.md"
check "flaky dossier"       "$OUT" "QA_FLAKY=.claude/qa/flaky.json"

echo "== manifests =="
if node -e "JSON.parse(require('fs').readFileSync('$HERE/../.claude-plugin/plugin.json','utf8'))"; then
  echo "  ok: plugin.json valid"
else
  echo "  FAIL: plugin.json"; FAIL=1
fi
if node -e "JSON.parse(require('fs').readFileSync('$HERE/../.claude-plugin/marketplace.json','utf8'))"; then
  echo "  ok: marketplace.json valid"
else
  echo "  FAIL: marketplace.json"; FAIL=1
fi

if [ "$FAIL" -eq 0 ]; then echo "ALL TESTS PASSED"; else echo "TESTS FAILED"; fi
exit "$FAIL"
