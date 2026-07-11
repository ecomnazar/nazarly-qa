#!/usr/bin/env bash
# detect-stack.sh — project stack detector for /nazarly-qa.
# Prints a structured report (KEY=VALUE + blocks) that the agent reads
# to decide how to bring the stand up locally and what to run e2e with.
# Read-only: runs nothing, installs nothing, changes nothing.
#
# Usage:  bash detect-stack.sh [PROJECT_DIR]   (default: cwd)
set -uo pipefail

ROOT="${1:-$PWD}"
cd "$ROOT" 2>/dev/null || { echo "ERROR=cannot_cd:$ROOT"; exit 1; }

# --- helper: read a field from package.json via node (more reliable than grep) ---
has_node() { command -v node >/dev/null 2>&1; }

# pkg_field <file> <js-expression-over-pkg> — prints the result or nothing
pkg_field() {
  local f="$1" expr="$2"
  [ -f "$f" ] || return 0
  if has_node; then
    node -e '
      try {
        const p = JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"));
        const out = (function(pkg){ return '"$expr"'; })(p);
        if (out === undefined || out === null) process.exit(0);
        if (typeof out === "object") { console.log(JSON.stringify(out)); }
        else console.log(out);
      } catch(e) {}
    ' "$f" 2>/dev/null
  fi
}

# dep_exists <file> <dep-name> -> "1" if present in deps/devDeps
dep_exists() {
  local f="$1" name="$2"
  [ -f "$f" ] || return 0
  pkg_field "$f" 'pkg.dependencies&&pkg.dependencies["'"$name"'"]?1:(pkg.devDependencies&&pkg.devDependencies["'"$name"'"]?1:"")'
}

echo "PROJECT_DIR=$ROOT"
echo "DETECTED_AT=$(date +%Y-%m-%dT%H:%M:%S 2>/dev/null || echo unknown)"

# ── hardware: the agent's parallelism budget ──
# HEAVY_SLOTS — how many "heavy" clients (Electron/Chrome/emulator) can run
# at once. The bottleneck is usually RAM, not cores: ~8 GB per slot.
HW_CORES=""
HW_RAM_GB=""
if sysctl -n hw.ncpu >/dev/null 2>&1; then
  HW_CORES=$(sysctl -n hw.ncpu 2>/dev/null)
  HW_RAM_GB=$(( $(sysctl -n hw.memsize 2>/dev/null || echo 0) / 1073741824 ))
elif [ -r /proc/meminfo ]; then
  HW_CORES=$(nproc 2>/dev/null || echo "")
  HW_RAM_GB=$(( $(awk '/MemTotal/{print $2}' /proc/meminfo) / 1048576 ))
fi
HEAVY_SLOTS=1
if [ -n "$HW_RAM_GB" ] && [ "$HW_RAM_GB" -ge 0 ] 2>/dev/null; then
  HEAVY_SLOTS=$(( HW_RAM_GB / 8 ))
  [ "$HEAVY_SLOTS" -lt 1 ] && HEAVY_SLOTS=1
  [ "$HEAVY_SLOTS" -gt 4 ] && HEAVY_SLOTS=4
fi
echo "HW_CORES=${HW_CORES:-unknown}"
echo "HW_RAM_GB=${HW_RAM_GB:-unknown}"
echo "HEAVY_SLOTS=$HEAVY_SLOTS"

# ── git ──
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "GIT=yes"
  echo "GIT_BRANCH=$(git branch --show-current 2>/dev/null)"
  echo "GIT_COMMIT=$(git rev-parse --short HEAD 2>/dev/null)"
  echo "GIT_DIRTY=$([ -n "$(git status --porcelain 2>/dev/null)" ] && echo yes || echo no)"
else
  echo "GIT=no"
fi

ROOT_PKG="package.json"
echo "HAS_ROOT_PKG=$([ -f "$ROOT_PKG" ] && echo yes || echo no)"

# ── package manager ──
PM="unknown"
[ -f "pnpm-lock.yaml" ] && PM="pnpm"
[ -f "yarn.lock" ] && PM="yarn"
[ -f "package-lock.json" ] && PM="npm"
[ -f "bun.lockb" ] && PM="bun"
echo "PKG_MANAGER=$PM"

# ── monorepo ──
MONO="no"
[ -f "pnpm-workspace.yaml" ] && MONO="pnpm-workspaces"
[ -f "turbo.json" ] && MONO="turbo"
[ -f "lerna.json" ] && MONO="lerna"
if [ "$MONO" = "no" ] && [ -f "$ROOT_PKG" ]; then
  WS=$(pkg_field "$ROOT_PKG" 'pkg.workspaces?"yes":""')
  [ -n "$WS" ] && MONO="npm-workspaces"
fi
echo "MONOREPO=$MONO"

# ── docker / DB ──
DC=""
for f in docker-compose.yml docker-compose.yaml docker-compose.dev.yml compose.yml compose.yaml; do
  [ -f "$f" ] && DC="$DC $f"
done
echo "DOCKER_COMPOSE=${DC# }"

# ── .env ──
ENV_EXAMPLES=""
for f in .env.example .env.sample .env.template apps/*/.env.example; do
  [ -f "$f" ] && ENV_EXAMPLES="$ENV_EXAMPLES $f"
done
echo "ENV_EXAMPLES=${ENV_EXAMPLES# }"
echo "HAS_ENV=$([ -f .env ] && echo yes || echo no)"

# ── framework detection: scan root + apps/*/ + packages/*/ ──
declare -a PKG_FILES=()
[ -f "$ROOT_PKG" ] && PKG_FILES+=("$ROOT_PKG")
for d in apps/* packages/* services/*; do
  [ -f "$d/package.json" ] && PKG_FILES+=("$d/package.json")
done

STACKS=""
add_stack() { case " $STACKS " in *" $1 "*) ;; *) STACKS="$STACKS $1";; esac; }

echo "--- WORKSPACES ---"
for pf in ${PKG_FILES[@]+"${PKG_FILES[@]}"}; do
  dir=$(dirname "$pf")
  name=$(pkg_field "$pf" 'pkg.name||""')
  kind=""
  [ -n "$(dep_exists "$pf" electron)" ] && kind="$kind electron" && add_stack electron
  [ -n "$(dep_exists "$pf" next)" ] && kind="$kind next" && add_stack web-next
  { [ -n "$(dep_exists "$pf" vite)" ] && [ -z "$(dep_exists "$pf" electron)" ]; } && kind="$kind vite" && add_stack web-vite
  [ -n "$(dep_exists "$pf" expo)" ] && kind="$kind expo" && add_stack expo-rn
  { [ -n "$(dep_exists "$pf" react-native)" ] && [ -z "$(dep_exists "$pf" expo)" ]; } && kind="$kind react-native" && add_stack rn
  [ -n "$(dep_exists "$pf" @nestjs/core)" ] && kind="$kind nestjs" && add_stack server-nest
  [ -n "$(dep_exists "$pf" express)" ] && kind="$kind express" && add_stack server-node
  [ -n "$(dep_exists "$pf" fastify)" ] && kind="$kind fastify" && add_stack server-node
  # mobile wrappers: same renderer, but a separate run surface
  if [ -n "$(dep_exists "$pf" @capacitor/core)" ]; then
    kind="$kind capacitor" && add_stack capacitor
    [ -d "$dir/android" ] && kind="$kind +android"
    [ -d "$dir/ios" ] && kind="$kind +ios"
  fi
  [ -n "$(dep_exists "$pf" @tauri-apps/api)" ] && kind="$kind tauri" && add_stack tauri
  # test tooling
  [ -n "$(dep_exists "$pf" @playwright/test)" ] && kind="$kind +playwright"
  [ -n "$(dep_exists "$pf" vitest)" ] && kind="$kind +vitest"
  [ -n "$(dep_exists "$pf" jest)" ] && kind="$kind +jest"
  echo "WS name=${name:-?} dir=$dir kind=${kind# }"
done

echo "--- STACKS ---"
echo "STACKS=${STACKS# }"

# ── test configs ──
echo "--- TEST_CONFIG ---"
find . -maxdepth 3 \( -name "playwright.config.*" -o -name "vitest.config.*" -o -name "jest.config.*" \) \
  -not -path "*/node_modules/*" 2>/dev/null | sed 's/^/CONFIG=/' | head -20
# e2e directories
find . -maxdepth 3 -type d \( -name "e2e" -o -name "__e2e__" \) -not -path "*/node_modules/*" 2>/dev/null | sed 's/^/E2E_DIR=/' | head -10

# ── run scripts (root + workspaces) ──
# Named suites (test:license, e2e:smoke, db:seed…) matter too —
# an exact-name match used to lose them.
echo "--- SCRIPTS ---"
for pf in ${PKG_FILES[@]+"${PKG_FILES[@]}"}; do
  dir=$(dirname "$pf")
  scripts=$(pkg_field "$pf" 'pkg.scripts?Object.keys(pkg.scripts).filter(function(k){return /^(test|e2e|db|seed|migrate)([:.].+)?$/.test(k) || /^(dev|start|serve|preview|build|typecheck|lint)$/.test(k)}).map(function(k){return k+"="+pkg.scripts[k]}):[]')
  [ -n "$scripts" ] && [ "$scripts" != "[]" ] && echo "PKG=$dir SCRIPTS=$scripts"
done

# ── docs describing the flows (the agent reads them in phase 1) ──
echo "--- FLOW_DOCS ---"
for f in README.md CLAUDE.md PROJECT.md STATE.md TASK.md TASKS.md docs/TZ.md docs/FLOWS.md; do
  [ -f "$f" ] && echo "DOC=$f"
done

# ── this repo's QA memory (test plan, risk catalog, past reports) ──
echo "--- QA_MEMORY ---"
[ -f ".claude/qa/flows.md" ] && echo "QA_FLOWS=.claude/qa/flows.md"
[ -f ".claude/qa/risks.md" ] && echo "QA_RISKS=.claude/qa/risks.md"
[ -f ".claude/qa/invariants.md" ] && echo "QA_INVARIANTS=.claude/qa/invariants.md"
[ -f ".claude/qa/flaky.json" ] && echo "QA_FLAKY=.claude/qa/flaky.json"
LAST_REPORT=$(find .claude/qa/reports -maxdepth 1 -name '*.json' 2>/dev/null | sort | tail -1)
[ -n "$LAST_REPORT" ] && echo "QA_LAST_REPORT=$LAST_REPORT"
REPORT_COUNT=$(find .claude/qa/reports -maxdepth 1 -name '*.json' 2>/dev/null | wc -l | tr -d ' ')
echo "QA_REPORT_COUNT=${REPORT_COUNT:-0}"

echo "--- END ---"
