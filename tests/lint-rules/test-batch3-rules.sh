#!/usr/bin/env bash
# test-batch3-rules.sh -- unit tests for lint-rules/txt001_build_words_in_user_text.star,
# txt002_non_iso_date_in_user_text.star and ui001_widget_layout_traps.star, run under the real
# Go Starlark interpreter with the mxcli builtins mocked from JSON (tests/lint-rules/starrun).
#
# IMPORTANT: every fixture in tests/lint-rules/fixtures/txt*.json and ui001-*.json is a
# HAND-WRITTEN unit fixture. The object_type / context / widget_type spellings in them were
# taken from a 2026-10-13 probe of a real catalog (see each rule's header), but the rows
# themselves are invented. These tests prove the rule logic and the self-checks; they do NOT
# prove the vocabulary matches YOUR model. That is what the field probe in each header is for.
#
# Needs `go` on PATH. A missing toolchain is a FAILURE (exit 1), never a quiet skip.
# Keep bash-3.2 compatible.
# Usage: tests/lint-rules/test-batch3-rules.sh      Exit 0 only if every assertion holds.

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TK="$(cd "$HERE/../.." && pwd)"
FX="$HERE/fixtures"
R1="$TK/lint-rules/txt001_build_words_in_user_text.star"
R2="$TK/lint-rules/txt002_non_iso_date_in_user_text.star"
R3="$TK/lint-rules/ui001_widget_layout_traps.star"

if ! command -v go >/dev/null 2>&1; then
  echo "FAIL go toolchain not found; these tests cannot run (NOT a pass)."
  echo "     Install Go (https://go.dev/dl/, or: brew install go / apt install golang) and re-run."
  exit 1
fi
# shellcheck source=../../bin/lib/portable.sh
. "$TK/bin/lib/portable.sh"
require_py   # sets $PY or exits 2 with an actionable message

W=$(mktemp -d "${TMPDIR:-/tmp}/b3rules.XXXXXX")
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

echo "== TXT001 =="
run "$R1" txt001-a-clean
check "a clean text, near-misses (Backstage 3, FF0042, v2), leaks only in documentation/log node -> 0" 'len(v)==0'
run "$R1" txt001-b-leaks
check "b six leaked words, one per element, second language folded -> 6 findings" 'len(v)==6 and all(x["module"]=="Sales" for x in v)'
check "b labels: stage, rule id, work marker, data-source note, version tag, feature id" 'sorted(x["message"].split("contains a ")[1].split(":")[0] for x in v)==sorted(["stage number","rule or requirement id","work marker","data-source note","version tag","BRD feature id"])'
check "b document types follow object_type (Page, Snippet, Menu_document, Microflow)" 'sorted(set(x["document_type"] for x in v))==["Menu_document","Microflow","Page","Snippet"]'
run "$R1" txt001-c-skipped
check "c page templates, building blocks, System/Administration, URLs skipped -> 0" 'len(v)==0'
sed 's/^PROJECT_WORDS = ()$/PROJECT_WORDS = ("Northwind",)/' "$R1" >"$W/txt001-words.star"
run "$W/txt001-words.star" txt001-d-project-word
check "d PROJECT_WORDS whole word, any case -> 1 finding (Northwindish not matched)" 'len(v)==1 and "NORTHWIND sync" in v[0]["message"]'
run "$R1" txt001-e-no-strings
check "e pages exist, strings() empty -> 1 _rule finding 'not FULL'" 'len(v)==1 and v[0]["module"]=="_rule" and "not FULL" in v[0]["message"]'
run "$R1" txt001-f-empty-model
check "f no pages, no strings -> 0 findings (a tiny model is not blindness)" 'len(v)==0'
run "$R1" txt001-g-all-invisible
check "g strings exist, none user-visible -> 1 _rule vocabulary finding" 'len(v)==1 and v[0]["module"]=="_rule" and "needs probing" in v[0]["message"]'
run "$R1" txt001-b-leaks "context"
check "h stripped context field -> 1 _rule finding 'inspected NOTHING'" 'len(v)==1 and v[0]["module"]=="_rule" and "inspected NOTHING" in v[0]["message"]'

echo "== TXT002 =="
run "$R2" txt002-a-iso
check "a ISO dates/formats, ratios, words, documentation -> 0" 'len(v)==0'
run "$R2" txt002-b-dates
check "b seven non-ISO forms, one element each, second language folded -> 7 findings" 'len(v)==7'
check "b every pattern kind reported once" 'sorted(x["message"].split("non-ISO ")[1].split(":")[0] for x in v)==sorted(["slash date","dashed day-month-year date","dotted date","day month-name year date","month-name day, year date","day-month format pattern","month-day format pattern"])'
run "$R2" txt002-c-format-slash
check "c d/M/yy in a microflow template and MM-dd beside an ISO form -> 2 findings" 'len(v)==2 and sorted(x["document_type"] for x in v)==["Microflow","Snippet"]'
run "$R2" txt002-d-no-strings
check "d pages exist, strings() empty -> 1 _rule finding 'not FULL'" 'len(v)==1 and v[0]["module"]=="_rule" and "not FULL" in v[0]["message"]'
run "$R2" txt002-e-all-invisible
check "e strings exist, none user-visible -> 1 _rule vocabulary finding" 'len(v)==1 and v[0]["module"]=="_rule" and "needs probing" in v[0]["message"]'
run "$R2" txt002-b-dates "value"
check "f stripped value field -> 1 _rule finding 'inspected NOTHING'" 'len(v)==1 and v[0]["module"]=="_rule" and "inspected NOTHING" in v[0]["message"]'

echo "== UI001 =="
run "$R3" ui001-a-clean
check "a grid without list view, 100%/flex/min-max widths, non-input widths -> 0" 'len(v)==0'
run "$R3" ui001-b-listview-in-grid
check "b list view under a grid (via container, and in a snippet) -> 2; grid-in-listview and System not" 'sorted(x["message"].split(": list view ")[1].split(" ")[0] for x in v)==["'"'"'lvLines'"'"'","'"'"'lvTags'"'"'"] and sorted(x["document_type"] for x in v)==["Page","Snippet"]'
run "$R3" ui001-c-input-width
check "c width on text box, combo box (!important, caps), text area -> 3; max-width not" 'sorted(x["message"].split("input ")[1].split(" ")[0] for x in v)==["'"'"'cbOwner'"'"'","'"'"'taNote'"'"'","'"'"'txtCode'"'"'"]'
run "$R3" ui001-d-unknown-types
check "d widgets exist, no type matches -> 1 _rule vocabulary finding" 'len(v)==1 and v[0]["module"]=="_rule" and "needs probing" in v[0]["message"]'
run "$R3" ui001-e-no-parents
check "e grid exists, no widget has a parent -> _rule finding beside the width finding" 'len(v)==2 and len([x for x in v if x["module"]=="_rule" and "parent_widget_id" in x["message"]])==1'
run "$R3" ui001-b-listview-in-grid "style"
check "f stripped style field -> 1 _rule finding 'inspected NOTHING'" 'len(v)==1 and v[0]["module"]=="_rule" and "inspected NOTHING" in v[0]["message"]'

echo
echo "passed: $PASS  failed: $FAILED"
[ "$FAILED" -eq 0 ]
