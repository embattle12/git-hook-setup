#!/usr/bin/env sh
# Lightweight test runner used by the pre-commit smoke gate.
# Simulates compile / elab / sw steps with optional, controllable failures.

set -euo pipefail

# ------------------ colors ------------------
if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  BOLD=$'\033[1m'; GRN=$'\033[32m'; YEL=$'\033[33m'; RED=$'\033[31m'; CYA=$'\033[36m'; RST=$'\033[0m'
else
  BOLD=""; GRN=""; YEL=""; RED=""; CYA=""; RST=""
fi

# ------------------ defaults ----------------
ACTION=""                 # compile | elab | sw (from -do)
TESTNAME="sample_tb"
SEED="1"

# env controls (handy for testing the hook)
# RUNTEST_FAIL="compile,elab,sw"  -> force specific step(s) to fail
# RUNTEST_DELAY_MS=200            -> add 200ms between prints
# RUNTEST_EXIT_CODE=1             -> exit code to use on simulated failure (default 1)
FAIL_LIST="${RUNTEST_FAIL:-}"
DELAY_MS="${RUNTEST_DELAY_MS:-0}"
FAIL_RC="${RUNTEST_EXIT_CODE:-1}"

sleep_delay() { if [[ "$DELAY_MS" -gt 0 ]]; then python - <<PY 2>/dev/null || true
import time; time.sleep(${DELAY_MS}/1000.0)
PY
fi; }

timestamp() { date +"%Y-%m-%d %H:%M:%S"; }

usage() {
  cat <<USAGE
Usage:
  runTest [-do compile|elab|sw] [-test NAME] [-seed N]

Examples:
  runTest -do compile
  runTest -do elab
  runTest -do sw
  runTest -test sample_tb -seed 123

Simulate failures:
  RUNTEST_FAIL=compile runTest -do compile
  RUNTEST_FAIL=elab runTest -do elab
  RUNTEST_FAIL=compile,elab runTest -do compile
USAGE
}

# ------------------ arg parse ----------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    -do)   ACTION="${2:-}"; shift 2;;
    -test) TESTNAME="${2:-}"; shift 2;;
    -seed) SEED="${2:-}"; shift 2;;
    -h|--help) usage; exit 0;;
    --) shift; break;;
    *) # Allow positional testname if not an option
       if [[ -z "$ACTION" && "$1" != -* ]]; then TESTNAME="$1"; shift; else shift; fi;;
  esac
done

# ------------------ helpers ------------------
contains_action() {
  local action="$1"
  [[ ",${FAIL_LIST}," == *",${action},"* ]]
}

step() {
  local action="$1"
  local pretty="$2"
  echo "[runTest] $(timestamp) ${BOLD}${CYA}${pretty}${RST}"
  sleep_delay
  if contains_action "$action"; then
    echo "[runTest] ${RED}Simulated failure for action '${action}'${RST}"
    exit "$FAIL_RC"
  fi
  echo "[runTest] ${GRN}${pretty} OK${RST}"
}

# ------------------ main ---------------------
if [[ -n "$ACTION" ]]; then
  case "$ACTION" in
    compile) step "compile" "Compiling testbench (test=${TESTNAME}, seed=${SEED})";;
    elab)    step "elab"    "Elaborating design (test=${TESTNAME})";;
    sw)      step "sw"      "Building SW headers flow (sw)";;
    *) echo "[runTest] ${YEL}Unknown -do '${ACTION}', doing nothing (success).${RST}";;
  esac
else
  echo "[runTest] Dummy: would run test '${TESTNAME}' with seed '${SEED}' (placeholder)"
  echo "[runTest] Tip: pass '-do compile' | '-do elab' | '-do sw' to exercise hook smoke gate."
fi
