#!/usr/bin/env bash
# test-batch2-rules.sh -- unit tests for lint-rules/perf001_generalization_depth.star,
# perf002_nested_data_widgets.star and perf004_npe_system_user_assoc.star, run under the real
# Go Starlark interpreter with the mxcli builtins mocked from JSON (tests/lint-rules/starrun).
#
# IMPORTANT: every fixture in tests/lint-rules/fixtures/perf*.json is a HAND-WRITTEN unit
# fixture. The entity_type / generalization / widget_type spellings in them ("Persistent",
# "NonPersistent", "Forms$DataView", ...) are GUESSES at the catalog vocabulary, not captured
# tool output. These tests prove the rule logic and the self-checks; they do NOT prove the
# vocabulary matches a real model. That is what the field probe in each rule's header is for.
#
# Needs `go` on PATH. A missing toolchain is a FAILURE (exit 1), never a quiet skip.
# Keep bash-3.2 compatible.
# Usage: tests/lint-rules/test-batch2-rules.sh      Exit 0 only if every assertion holds.

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TK="$(cd "$HERE/../.." && pwd)"
FX="$HERE/fixtures"
R1="$TK/lint-rules/perf001_generalization_depth.star"
R2="$TK/lint-rules/perf002_nested_data_widgets.star"
R4="$TK/lint-rules/perf004_npe_system_user_assoc.star"

if ! command -v go >/dev/null 2>&1; then
  echo "FAIL go toolchain not found; these tests cannot run (NOT a pass)."
  echo "     Install Go (https://go.dev/dl/, or: brew install go / apt install golang) and re-run."
  exit 1
fi
# shellcheck source=../../bin/lib/portable.sh
. "$TK/bin/lib/portable.sh"
require_py   # sets $PY or exits 2 with an actionable message

W=$(mktemp -d "${TMPDIR:-/tmp}/b2rules.XXXXXX")
trap 'rm -rf "$W"' EXIT
PASS=0; FAILED=0
ok(){ printf '  PASS %s\n' "$1"; PASS=$((PASS+1)); }
no(){ printf '  FAIL %s\n' "$1"; FAILED=$((FAILED+1)); }

cd "$TK" || exit 1
OUT="$W/out.json"; ERR="$W/err.txt"; RC=0

BIN="$W/starrun"
if ! (cd "$HERE/starrun" && GOFLAGS=-mod=mod go build -o "$BIN" . 2>"$ERR"); then
  echo "FAIL could not build tests/lint-rules/starrun: $(head -c 400 "$ERR")"; exit 1
fi

# run RULE FIXTURE [STRIP]  -> OUT holds stdout, RC the exit code
run(){
  local rule="$1" fix="$2" strip="${3:-}"
  if [ -n "$strip" ]; then
    "$BIN" -rule "$rule" -fixture "$FX/$fix.json" -strip-fields "$strip" >"$OUT" 2>"$ERR"
  else
    "$BIN" -rule "$rule" -fixture "$FX/$fix.json" >"$OUT" 2>"$ERR"
  fi
  RC=$?
}

# check LABEL PY-EXPR : v is the parsed violation list; the expression must be truthy.
check(){
  local label="$1" expr="$2"
  if [ "$RC" -ne 0 ]; then no "$label (harness exit $RC: $(head -c 300 "$ERR"))"; return; fi
  if "$PY" - "$OUT" "$expr" <<'PY'
import json, sys
v = json.load(open(sys.argv[1]))
sys.exit(0 if eval(sys.argv[2]) else 1)
PY
  then ok "$label"; else no "$label (got: $(head -c 400 "$OUT"))"; fi
}

echo "== PERF001 =="
run "$R1" perf001-a-flat
check "a chain of exactly 2 ancestors -> 0 findings" 'len(v)==0'
run "$R1" perf001-b-deep
check "b A<-B<-C<-D<-E -> D (3) and E (4) flagged, with chain" 'sorted(x["document_name"] for x in v)==["Sales.D","Sales.E"] and "Sales.E -> Sales.D -> Sales.C -> Sales.B -> Sales.A" in [x["message"] for x in v if x["document_name"]=="Sales.E"][0]'
run "$R1" perf001-c-system-ancestor
check "c System.User ancestor counts one level -> only Sales.D (3) flagged" 'len(v)==1 and v[0]["document_name"]=="Sales.D" and "System.User" in v[0]["message"]'
run "$R1" perf001-d-no-generalization
check "d 20 entities, no generalization -> 1 _rule finding" 'len(v)==1 and v[0]["module"]=="_rule" and "not one has a generalization" in v[0]["message"]'
run "$R1" perf001-e-unresolvable
check "e generalization values nothing resolves -> 1 _rule vocabulary finding" 'len(v)==1 and v[0]["module"]=="_rule" and "could resolve none" in v[0]["message"]'
run "$R1" perf001-b-deep "generalization"
check "f stripped generalization -> 1 _rule finding 'inspected NOTHING'" 'len(v)==1 and v[0]["module"]=="_rule" and "inspected NOTHING" in v[0]["message"]'

echo "== PERF002 =="
run "$R2" perf002-a-flat
check "a two-deep nesting, grid columns ignored -> 0 findings" 'len(v)==0'
run "$R2" perf002-b-nested
check "b third data container -> exactly 1 finding naming page and widget" 'len(v)==1 and v[0]["document_name"]=="Sales.P1" and "wc" in v[0]["message"] and "Sales.P1" in v[0]["message"] and v[0]["document_type"]=="Page"'
run "$R2" perf002-c-unknown-types
check "c widgets exist, no type matches -> 1 _rule vocabulary finding" 'len(v)==1 and v[0]["module"]=="_rule" and "needs probing" in v[0]["message"]'
run "$R2" perf002-d-listview-template
check "d ListViewTemplate row template is not a container -> 0 findings" 'len(v)==0'
run "$R2" perf002-b-nested "parent_widget_id"
check "e stripped parent_widget_id -> 1 _rule finding 'inspected NOTHING'" 'len(v)==1 and v[0]["module"]=="_rule" and "inspected NOTHING" in v[0]["message"]'

echo "== PERF004 =="
run "$R4" perf004-a-clean
check "a NPE<->persistent, persistent<->User -> 0 findings" 'len(v)==0'
run "$R4" perf004-b-npe-user
check "b NPE->User and Session->NPE flagged, Order->User not" 'sorted(x["document_name"] for x in v)==["Sales.Prefs_User","Sales.Session_Filter"] and all(x["document_type"]=="Association" for x in v)'
run "$R4" perf004-c-via-generalization
check "c NPE -> entity generalizing System.User -> 1 finding" 'len(v)==1 and v[0]["document_name"]=="Sales.Filter_Account"'
run "$R4" perf004-d-unknown-types
check "d entity_type vocabulary unrecognised -> 1 _rule finding" 'len(v)==1 and v[0]["module"]=="_rule" and "needs probing" in v[0]["message"]'
run "$R4" perf004-b-npe-user "entity_type"
check "e stripped entity_type -> 1 _rule finding 'inspected NOTHING'" 'len(v)==1 and v[0]["module"]=="_rule" and "inspected NOTHING" in v[0]["message"]'

echo
echo "passed: $PASS  failed: $FAILED"
[ "$FAILED" -eq 0 ]
