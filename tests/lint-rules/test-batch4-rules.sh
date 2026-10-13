#!/usr/bin/env bash
# test-batch4-rules.sh -- unit tests for lint-rules/sec014_external_role_write.star (issue
# #268) and the toolkit-owned lint-rules/conv009_max_microflow_objects.star (issue #267), run
# under the real Go Starlark interpreter with the mxcli builtins mocked from JSON
# (tests/lint-rules/starrun). get_option() is mocked the way mxcli 0.26.0 converts
# lint-config.yaml options: bool / int / float / text pass, a list becomes None.
#
# IMPORTANT: every fixture in tests/lint-rules/fixtures/sec014-*.json and conv009-*.json is a
# HAND-WRITTEN unit fixture. The access_type / data_type spellings and the qualified member
# and role names in them were taken from a 2026-10-13 probe of two real catalogs (see each
# rule's header), but the rows themselves are invented. These tests prove the rule logic and
# the self-checks; they do NOT prove the vocabulary matches YOUR model.
#
# Needs `go` on PATH. A missing toolchain is a FAILURE (exit 1), never a quiet skip.
# Keep bash-3.2 compatible.
# Usage: tests/lint-rules/test-batch4-rules.sh      Exit 0 only if every assertion holds.

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TK="$(cd "$HERE/../.." && pwd)"
FX="$HERE/fixtures"
R1="$TK/lint-rules/sec014_external_role_write.star"
R2="$TK/lint-rules/conv009_max_microflow_objects.star"
for r in "$R1" "$R2"; do
  [ -f "$r" ] || { echo "FAIL rule file missing: ${r#"$TK"/}"; exit 1; }
done

if ! command -v go >/dev/null 2>&1; then
  echo "FAIL go toolchain not found; these tests cannot run (NOT a pass)."
  echo "     Install Go (https://go.dev/dl/, or: brew install go / apt install golang) and re-run."
  exit 1
fi
# shellcheck source=../../bin/lib/portable.sh
. "$TK/bin/lib/portable.sh"
require_py   # sets $PY or exits 2 with an actionable message

W=$(mktemp -d "${TMPDIR:-/tmp}/b4rules.XXXXXX")
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

echo "== SEC014 =="
run "$R1" sec014-a-unset
check "a external_roles unset -> 1 _rule finding, nothing inspected" 'len(v)==1 and v[0]["module"]=="_rule" and "no external roles configured" in v[0]["message"]'
run "$R1" sec014-b-none
check "b external_roles \"none\" -> 0 (the app has no external role, on the record)" 'len(v)==0'
run "$R1" sec014-c-list
check "c external_roles as a YAML list (reaches Starlark as None) -> 1 _rule finding" 'len(v)==1 and v[0]["module"]=="_rule" and "not text" in v[0]["message"]'
run "$R1" sec014-d-write-all
check "d write * by the external role -> 1 finding (internal role with the same grant not flagged)" 'len(v)==1 and v[0]["document_name"]=="Portal.Offer" and "external role '"'"'Partner'"'"'" in v[0]["message"]'
check "d message lists all members, state, both audit attrs, the ownership association" 'all(s in v[0]["message"] for s in ["all 6 attributes (write *)","state Status","audit ApprovedBy, SubmittedAt","ownership association Offer_Partner"])'
check "d suggestion names the fix (read all, write only inputs, gate on initial state)" '"only the input members" in v[0]["suggestion"] and "initial state" in v[0]["suggestion"]'
run "$R1" sec014-e-input-only
check "e input members + a non-owner association + part of another entity -> 0" 'len(v)==0'
run "$R1" sec014-f-state-only
check "f two state enums flagged; a String StatusText and Format (not audit) are not" 'len(v)==1 and "state ReviewStatus, Status." in v[0]["message"] and "audit" not in v[0]["message"] and "StatusText" not in v[0]["message"]'
run "$R1" sec014-g-qualified-member
check "g qualified member names, bare role in the rows, qualified module role configured -> 1" 'len(v)==1 and "state Status" in v[0]["message"]'
run "$R1" sec014-h-unknown-role
check "h a configured role that does not exist -> 1 _rule finding naming it" 'len(v)==1 and v[0]["module"]=="_rule" and "Partnr" in v[0]["message"]'
run "$R1" sec014-i-not-full
check "i persistable entities, no permission rows at all -> 1 _rule finding 'not FULL'" 'len(v)==1 and v[0]["module"]=="_rule" and "not FULL" in v[0]["message"]'
run "$R1" sec014-j-skipped
check "j Administration, non-persistable and external entities skipped -> 0" 'len(v)==0'
run "$R1" sec014-k-two-roles
check "k two roles (';' and ',' separators, a duplicate) -> one finding per entity x role" 'sorted(x["message"].split("external role ")[1].split(" ")[0] for x in v)==["'"'"'Customer'"'"'","'"'"'Partner'"'"'"]'
run "$R1" sec014-l-mapping-only
check "l user_roles() empty, role_mappings() names the role -> still resolved, 1 finding" 'len(v)==1 and v[0]["module"]=="Portal"'

echo "== CONV009 =="
run "$R2" conv009-a-default
check "a no option -> stock threshold 15: 16 and 30 flagged, 15 not" 'sorted(x["document_name"] for x in v)==["Sales.ACT_Medium","Sales.SUB_Large"] and all("(max: 15)" in x["message"] for x in v)'
run "$R2" conv009-b-max20
check "b maxObjects: 20 is read (the stock rule ignores it) -> only the 30-object flow" 'len(v)==1 and v[0]["document_name"]=="Sales.SUB_Large" and "(max: 20)" in v[0]["message"]'
run "$R2" conv009-c-loop-bodies
check "c countLoopBodies: true counts total_activity_count -> 3 flows over 20" 'len(v)==3 and all("loop bodies included" in x["message"] for x in v)'
run "$R2" conv009-d-max-text
check "d maxObjects: \"20\" (quoted) -> read as 20" 'len(v)==1 and "(max: 20)" in v[0]["message"]'
run "$R2" conv009-e-max-list
check "e maxObjects as a list (None) -> 1 _rule finding, no silent fallback to 15" 'len(v)==1 and v[0]["module"]=="_rule" and "maxObjects" in v[0]["message"]'
run "$R2" conv009-f-max-zero
check "f maxObjects: 0 -> 1 _rule finding" 'len(v)==1 and v[0]["module"]=="_rule"'
run "$R2" conv009-g-loop-text
check "g countLoopBodies: \"yes\" -> 1 _rule finding" 'len(v)==1 and v[0]["module"]=="_rule" and "countLoopBodies" in v[0]["message"]'
run "$R2" conv009-h-all-zero
check "h four flows all at 0 objects -> 1 _rule finding 'not populated'" 'len(v)==1 and v[0]["module"]=="_rule" and "not populated" in v[0]["message"]'
run "$R2" conv009-i-empty
check "i no flows -> 0 (an empty model is not blindness)" 'len(v)==0'
run "$R2" conv009-j-nanoflow
check "j a nanoflow is named a nanoflow" 'len(v)==1 and v[0]["document_type"]=="Nanoflow" and "sub-nanoflows" in v[0]["message"]'
run "$R2" conv009-j-nanoflow "document_noun,document_noun_title"
check "k mxcli before 0.25 (no document_noun) -> falls back to Microflow, still 1 finding" 'len(v)==1 and v[0]["document_type"]=="Microflow"'
run "$R2" conv009-c-loop-bodies "total_activity_count"
check "l countLoopBodies on an mxcli without total_activity_count -> 1 _rule finding" 'len(v)==1 and v[0]["module"]=="_rule" and "total_activity_count" in v[0]["message"]'

echo
echo "passed: $PASS  failed: $FAILED"
[ "$FAILED" -eq 0 ]
