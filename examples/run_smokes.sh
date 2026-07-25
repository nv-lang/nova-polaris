#!/usr/bin/env bash
# SPDX-License-Identifier: MIT OR Apache-2.0
# Polaris examples — build every example --strict-effects, then for each one
# that runs a server: start it, hit it with 1-2 curl requests, stop it.
# Plan 230 Ф.1 gate.
#
# Env overrides (all optional, defaults assume this script runs from a
# checkout next to a sibling `nova` repo checkout one level up):
#   NOVA_BIN              - path to the nova CLI binary (default: `nova`,
#                            i.e. resolved via PATH)
#   NOVA_GC_LIB_DIR / NOVA_GC_INCLUDE_DIR / NOVA_RT_DIR / NOVA_CG_INCLUDE
#                         - Boehm GC + nova_rt + codegen-include paths
#   NOVA_STD_PATH         - stdlib source root (needed when building outside
#                            the nova repo itself)
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NOVA_BIN="${NOVA_BIN:-nova}"

PASS=0
FAIL=0
FAILED_NAMES=()

# example dir -> "port|path1:expect1[|path2:expect2]"
declare -A SMOKE_PLAN=(
  [01-hello]="18082|/hello/nova:hello, nova|/:hello, world"
  [02-routing]="18083|/users/42:user 42|/api/widgets/9:widget 9"
  [03-json-api]="18084|/todos:[]"
  [04-middleware]="18085|/x:base"
  [05-auth]="18086|/public:public"
  [06-static-site]="18087|/assets/style.css:font-family|/:h1"
  [07-sse-stream]="18088|/events:event:"
  [08-websocket-echo]="18089|/health:ok"
  [09-graceful]="18090|/health:ok"
  [10-mini-service]="18091|/health:ok"
)

log() { printf '%s\n' "$*"; }

check_one() {
  local dir="$1"
  local name
  name="$(basename "$dir")"
  log "=== ${name} ==="

  (
    cd "$dir" || exit 1
    "$NOVA_BIN" build --strict-effects src/main.nv
  )
  if [ $? -ne 0 ]; then
    log "BUILD-FAIL ${name}"
    FAIL=$((FAIL + 1))
    FAILED_NAMES+=("${name} (build)")
    return
  fi
  log "BUILD-OK   ${name}"

  local plan="${SMOKE_PLAN[$name]:-}"
  if [ -z "$plan" ]; then
    log "SMOKE-SKIP ${name} (no smoke plan yet)"
    PASS=$((PASS + 1))
    return
  fi

  local port="${plan%%|*}"
  local rest="${plan#*|}"
  IFS='|' read -r -a checks <<< "$rest"

  ( cd "$dir" && ./main.exe ) &
  local pid=$!
  sleep 1

  local ok=1
  for chk in "${checks[@]}"; do
    local path="${chk%%:*}"
    local expect="${chk#*:}"
    local body
    body="$(curl -s -m 3 "http://127.0.0.1:${port}${path}" 2>/dev/null)"
    if [[ "$body" == *"$expect"* ]]; then
      log "  OK   GET ${path} -> contains \"${expect}\""
    else
      log "  FAIL GET ${path} -> expected \"${expect}\", got: ${body}"
      ok=0
    fi
  done

  kill "$pid" 2>/dev/null
  wait "$pid" 2>/dev/null

  if [ "$ok" -eq 1 ]; then
    log "SMOKE-OK   ${name}"
    PASS=$((PASS + 1))
  else
    log "SMOKE-FAIL ${name}"
    FAIL=$((FAIL + 1))
    FAILED_NAMES+=("${name} (smoke)")
  fi
}

for dir in "$SCRIPT_DIR"/[0-9][0-9]-*/; do
  [ -d "$dir" ] || continue
  check_one "${dir%/}"
done

log ""
log "===== SUMMARY ====="
log "PASS: ${PASS}  FAIL: ${FAIL}"
if [ "$FAIL" -gt 0 ]; then
  log "Failed: ${FAILED_NAMES[*]}"
  exit 1
fi
exit 0
