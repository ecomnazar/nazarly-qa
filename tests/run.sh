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

echo "== detect-stack.sh: php/laravel =="
# fixture: a Laravel backend whose package.json only drives the vite asset pipeline
mkdir -p "$TMP/laravel"
cat > "$TMP/laravel/composer.json" <<'EOF'
{ "name": "acme/shop-backend",
  "require": { "php": "^8.2", "laravel/framework": "^12.0" },
  "require-dev": { "phpunit/phpunit": "^11.5" },
  "scripts": { "test": ["@php artisan test"], "dev": ["npx concurrently \"php artisan serve\" \"npm run dev\""], "setup": "cp .env.example .env" } }
EOF
cat > "$TMP/laravel/package.json" <<'EOF'
{ "name": "acme-shop-assets", "devDependencies": { "vite": "^6.0.0" }, "scripts": { "dev": "vite", "build": "vite build" } }
EOF
touch "$TMP/laravel/artisan" "$TMP/laravel/phpunit.xml"
OUT=$(bash "$LIB/detect-stack.sh" "$TMP/laravel")
check "composer detected"      "$OUT" "HAS_COMPOSER=yes"
check "laravel stack"          "$OUT" "server-laravel"
check "artisan flagged"        "$OUT" "HAS_ARTISAN=yes"
check "php test runner"        "$OUT" "PHP_TEST=phpunit"
check "composer test script"   "$OUT" "test="
check "phpunit config"         "$OUT" "CONFIG=./phpunit.xml"
check "vite marked as assets"  "$OUT" "+vite-assets"
if echo "$OUT" | grep "^STACKS=" | grep -q "web-vite"; then
  echo "  FAIL: laravel asset-pipeline vite misdetected as web-vite stack"; FAIL=1
else
  echo "  ok: web-vite not in STACKS for a laravel backend"
fi

echo "== detect-stack.sh: php monorepo / library / lumen / broken json =="
# Laravel backend in a monorepo subdir: the PHP block used to read only the
# root composer.json — the subdir got +vite-assets but STACKS stayed empty
mkdir -p "$TMP/phpmono/services/api"
cat > "$TMP/phpmono/package.json" <<'EOF'
{ "name": "phpmono-root", "workspaces": ["services/*"] }
EOF
cat > "$TMP/phpmono/services/api/composer.json" <<'EOF'
{ "name": "acme/api", "require": { "laravel/framework": "^12.0" }, "require-dev": { "pestphp/pest": "^3.0" }, "scripts": { "test": "pest" } }
EOF
cat > "$TMP/phpmono/services/api/package.json" <<'EOF'
{ "name": "acme-api-assets", "devDependencies": { "vite": "^6.0.0" } }
EOF
touch "$TMP/phpmono/services/api/artisan"
OUT=$(bash "$LIB/detect-stack.sh" "$TMP/phpmono")
check "subdir laravel stack"   "$OUT" "server-laravel"
check "subdir php line"        "$OUT" "PHP dir=services/api fw=laravel artisan=yes test=pest"
check "subdir composer script" "$OUT" "PKG=services/api COMPOSER_SCRIPTS="
if echo "$OUT" | grep "^STACKS=" | grep -q "web-vite"; then
  echo "  FAIL: subdir asset-pipeline vite misdetected as web-vite"; FAIL=1
else
  echo "  ok: web-vite not in STACKS for laravel-in-subdir"
fi

# a Laravel *package* (framework only in require-dev) is a library, not a server
mkdir -p "$TMP/phplib"
cat > "$TMP/phplib/composer.json" <<'EOF'
{ "name": "acme/laravel-extension", "require": { "php": "^8.2" }, "require-dev": { "laravel/framework": "^12.0", "phpunit/phpunit": "^11.5" } }
EOF
OUT=$(bash "$LIB/detect-stack.sh" "$TMP/phplib")
check "library keeps test runner" "$OUT" "PHP_TEST=phpunit"
if echo "$OUT" | grep "^STACKS=" | grep -q "server-laravel"; then
  echo "  FAIL: require-dev framework misdetected as server-laravel"; FAIL=1
else
  echo "  ok: require-dev laravel is not a server stack"
fi

# Lumen with a vite asset pipeline: same misdetect, different package name
mkdir -p "$TMP/lumen"
cat > "$TMP/lumen/composer.json" <<'EOF'
{ "name": "acme/lumen-api", "require": { "laravel/lumen-framework": "^10.0" } }
EOF
cat > "$TMP/lumen/package.json" <<'EOF'
{ "name": "lumen-assets", "devDependencies": { "vite": "^5.0.0" } }
EOF
OUT=$(bash "$LIB/detect-stack.sh" "$TMP/lumen")
check "lumen -> laravel stack" "$OUT" "server-laravel"
if echo "$OUT" | grep "^STACKS=" | grep -q "web-vite"; then
  echo "  FAIL: lumen asset vite misdetected as web-vite"; FAIL=1
else
  echo "  ok: web-vite not in STACKS for lumen"
fi

# broken composer.json must fail loud, not silently degrade
mkdir -p "$TMP/phpbad"
echo '{ broken json' > "$TMP/phpbad/composer.json"
OUT=$(bash "$LIB/detect-stack.sh" "$TMP/phpbad")
check "parse error is loud"    "$OUT" "COMPOSER_PARSE=error dir=."

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
  cy.wait(1000);
  await page.waitForLoadState('networkidle');
  await page.goto(url, { waitUntil: 'networkidle0' });
  const n = Math.random();
  expect(api.mock.calls.length).toBe(1);
  expect(total).toBe(10.5);
});
test.only('focused', () => {});
EOF
cat > "$F/tests/good.test.ts" <<'EOF'
test('waits for signal', async () => {
  cy.wait('@getUsers');
  await expect(page.getByRole('button')).toBeVisible();
  expect(total).toBe(1050);
});
EOF
OUT=$(node "$LIB/check-flaky-patterns.mjs" "$F")
check "sleep-as-sync"     "$OUT" "FLAKY[sleep-as-sync] tests/bad.test.ts"
check "cy.wait number"    "$OUT" "cy.wait(1000)"
check "networkidle wait"  "$OUT" "FLAKY[networkidle]"
check "networkidle0 puppeteer" "$OUT" "networkidle0"
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
