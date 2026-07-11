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
{"date":"2026-01-01T12:00:00","bugs":[{"id":"a","severity":"high","title":"bug A"},{"id":"b","severity":"low","title":"bug B"}],
 "flows":[{"id":"f1","status":"pass"}]}
EOF
cat > "$R/2026-01-05-1200.json" <<'EOF'
{"date":"2026-01-05T12:00:00","bugs":[{"id":"a","severity":"high","title":"bug A"},{"id":"c","severity":"critical","title":"bug C"}],
 "flows":[{"id":"f1","status":"fail"}]}
EOF
OUT=$(node "$LIB/baseline-diff.mjs" "$R")
check "diff mode"        "$OUT" "BASELINE=diff"
check "new bug"          "$OUT" "NEW: c (critical)"
check "fixed bug"        "$OUT" "FIXED: b"
check "persisting bug"   "$OUT" "PERSISTING: a (high)"
check "escalation flag"  "$OUT" "ESCALATION"
check "flow regression"  "$OUT" "FLOW_REGRESSION: f1"

OUT=$(node "$LIB/baseline-diff.mjs" "$TMP/nonexistent")
check "missing dir"      "$OUT" "BASELINE=no-reports-dir"
mkdir -p "$TMP/empty"
OUT=$(node "$LIB/baseline-diff.mjs" "$TMP/empty")
check "empty dir"        "$OUT" "BASELINE=first-run"

echo "== manifests =="
node -e "JSON.parse(require('fs').readFileSync('$HERE/../.claude-plugin/plugin.json','utf8'))" \
  && echo "  ok: plugin.json valid" || { echo "  FAIL: plugin.json"; FAIL=1; }
node -e "JSON.parse(require('fs').readFileSync('$HERE/../.claude-plugin/marketplace.json','utf8'))" \
  && echo "  ok: marketplace.json valid" || { echo "  FAIL: marketplace.json"; FAIL=1; }

if [ "$FAIL" -eq 0 ]; then echo "ALL TESTS PASSED"; else echo "TESTS FAILED"; fi
exit "$FAIL"
