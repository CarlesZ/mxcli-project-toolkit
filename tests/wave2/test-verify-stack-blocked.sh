#!/usr/bin/env bash
# Usage: bash test-verify-stack-blocked.sh [path-to-verify-module.sh]
#
# Fixture for project-bin/verify-module.sh's verdict for the stack rung.
#
# The defect (review of #313, 2026-10-13): test-stack-up.sh exits 4 for "instrument blocked —
# the port `mxcli run --local` needs is held by another process", and its header says to
# record that as blocked, not as a test failure. verify-module's verdict table mapped every
# non-0, non-2 gate exit to FINDING, so a held port read as "the module has findings". It is
# now a FAULT (the instrument did not measure), scoped to the stack rung: exit 4 means NOT
# APPLICABLE from conformance-check.sh, so it is deliberately not a global remap.
#
# The verdict function is extracted from the subject and called directly — a full verify-module
# run needs a live app. The exit codes are the ones test-stack-up.sh's own header documents.

set -uo pipefail

SUT="${1:-}"
[ -z "$SUT" ] && SUT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/project-bin/verify-module.sh"
if [ ! -f "$SUT" ]; then
  echo "SKIP: subject not found at $SUT"
  echo "SCORE: 0/0 — nothing to test"
  exit 0
fi

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  ok   — $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL — $1"; [ -n "${2:-}" ] && echo "         got: $2"; }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/verify-stack.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

FN="$(awk '/^_report_result\(\) \{/{on=1} on{print} on && /^\}/{exit}' "$SUT")"
[ -n "$FN" ] || { echo "FAIL — no _report_result() in $SUT"; exit 1; }

# verdict <kind> <rc> -> the verdict column _report_result writes to the summary
verdict() {
  ( ROOT="$WORK"; SUMMARY="$WORK/summary.tsv"; FINDINGS=0; FAULTED=0
    c_ok() { :; }; c_bad() { :; }; c_warn() { :; }
    : > "$SUMMARY"; echo "log" > "$WORK/x.log"
    eval "$FN"
    _report_result "rung" "$WORK/x.log" "$1" 60 "$2" 1 >/dev/null 2>&1
    cut -f2 "$SUMMARY" )
}

v="$(verdict stack 4)"
[ "$v" = FAULT ] && ok "stack rung exit 4 (port held) is FAULT, not FINDING" \
  || bad "stack rung exit 4 graded as a test result" "$v"
v="$(verdict stack 1)"
[ "$v" = FINDING ] && ok "stack rung exit 1 (not up) is still FINDING" || bad "stack exit 1 changed" "$v"
v="$(verdict stack 0)"
[ "$v" = PASS ] && ok "stack rung exit 0 is PASS" || bad "stack exit 0 changed" "$v"
v="$(verdict stack 2)"
[ "$v" = FAULT ] && ok "stack rung exit 2 is FAULT" || bad "stack exit 2 changed" "$v"
v="$(verdict gate 4)"
[ "$v" = FINDING ] && ok "exit 4 from a non-stack gate rung is not remapped (scoped fix)" \
  || bad "exit 4 remapped globally" "$v"

grep -qE 'run "stack \(test-stack-up --check\)" "[^"]*" stack ' "$SUT" \
  && ok "the stack rung is run with kind 'stack'" \
  || bad "the stack rung does not use kind 'stack', so exit 4 still reads as FINDING"

echo ""
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
