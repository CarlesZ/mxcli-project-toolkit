#!/usr/bin/env bash
# test-extraction-quality-report.sh — bin/extraction-report.sh reads the validator's
# extraction-quality*.json (#151) and renders one row per dimension the file declares.
#
# GOLDEN INPUT. No extraction-quality.json exists anywhere in this repo: none of the three
# pipelines ships a validator, so there is no captured sample output to pin. The input here is
# the example object in skills/extractor-quality-loop.md "Output Format" — read out of the skill
# at run time, never copied, so the fixture follows the documented contract if the skill moves.
# Variants (self-graded, process-model dimensions, 0/0, broken) are mutations of that object.
# A captured validator output from a field run is still owed.
#
#   Q1  documents KB, no score file → section `skipped`, no new fault (existing projects)
#   Q2  the skill's example at analysis/<src>/extraction-quality.json → read, 6 rows, not
#       passed → `manual`; figures on the page (score, found/expected, gaps, confirmed zero)
#   Q3  analysis/<src>/extracted/extraction-quality-<name>.json with the stack's OWN dimension
#       keys, selfGraded + passed → `fault` "self-graded pass"
#   Q4  code-extracted KB, no score file → `manual` "not produced yet" (no shipped pipeline
#       writes a validator, so nothing mandatory produces it — never green, never a fault)
#   Q5  the score file inside <kb>/extracted/ is not counted as an unparseable item file
#   Q6  a 0/0 dimension not in confirmedZeros → fault; the example's confirmed one is not
#   Q7  passed:true under its own threshold → fault; broken JSON → fault, page still rendered
#
# usage: bash tests/wave2/test-extraction-quality-report.sh /path/to/extraction-report.sh

set -uo pipefail
SUT="${1:?usage: test-extraction-quality-report.sh /path/to/extraction-report.sh}"
case "$SUT" in /*) ;; *) SUT="$PWD/$SUT" ;; esac
TOOLKIT="$(cd "$(dirname "$SUT")/.." && pwd)"
SKILL="$TOOLKIT/skills/extractor-quality-loop.md"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/eqr.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL %s\n     %s\n' "$1" "${2:-}"; }
has()   { case "$2" in *"$3"*) ok "$1" ;; *) bad "$1" "missing '$3'" ;; esac; }
hasnt() { case "$2" in *"$3"*) bad "$1" "unexpected '$3'" ;; *) ok "$1" ;; esac; }

# shellcheck disable=SC1091
. "$TOOLKIT/bin/lib/portable.sh"
require_py

# the documented example, straight out of the skill
EXAMPLE="$WORK/example.json"
awk '/^## Output Format: extraction-quality.json/{f=1;next} f&&/^```json/{g=1;next} g&&/^```/{exit} g' "$SKILL" > "$EXAMPLE"
"$PY" -c 'import json,sys; d=json.load(open(sys.argv[1])); assert len(d["dimensions"])==6' "$EXAMPLE" \
  || { echo "could not read the example out of $SKILL"; exit 2; }

mutate() {   # $1 in, $2 out, $3 statements over `d`
  "$PY" -c 'import json,sys
d=json.load(open(sys.argv[1]))
exec(sys.argv[3])
json.dump(d,open(sys.argv[2],"w"),indent=2)' "$1" "$2" "$3"
}

doc_kb() {   # a documents-provenance knowledge base
  mkdir -p "$1/analysis/src/knowledge-base/share"
  printf '# KB\n\nsomething\n' > "$1/analysis/src/knowledge-base/share/KB.md"
  printf '# KB_a\n\nsomething\n' > "$1/analysis/src/knowledge-base/share/KB_a.md"
}
code_kb() {  # a code-extracted knowledge base (merger output + extracted/)
  local kb="$1/analysis/src/knowledge-base"
  mkdir -p "$kb/extracted"
  printf '[{"name":"Order","module":"Sales"}]\n' > "$kb/entities.json"
  printf '[{"name":"ACT_Save","module":"Sales"}]\n' > "$kb/logics.json"
  printf '[{"name":"OrderEdit","module":"Sales"}]\n' > "$kb/screens.json"
  printf '{"items":[{"type":"entity","name":"Order"},{"type":"logic","name":"ACT_Save"},{"type":"screen","name":"OrderEdit"}]}\n' > "$kb/extracted/a.json"
}
run() { bash "$SUT" "$1" "${@:2}" 2>&1; }
jget() { "$PY" -c 'import json,sys
d=json.loads(sys.stdin.read()); b=d["bases"][0]
print(eval(sys.argv[1]))' "$1"; }

# --- Q1 -------------------------------------------------------------------------------------
P1="$WORK/p1"; doc_kb "$P1"
J="$(run "$P1" --json)"
[ "$(printf '%s' "$J" | jget 'b["sections"].get("extractionQuality")')" = skipped ] \
  && ok "Q1 documents KB, no file → skipped" || bad "Q1 documents KB, no file → skipped" "$J"
[ "$(printf '%s' "$J" | jget 'b["verdicts"]["fault"]')" = 0 ] && ok "Q1 no new fault" || bad "Q1 no new fault" "$J"

# --- Q2 -------------------------------------------------------------------------------------
P2="$WORK/p2"; doc_kb "$P2"; cp "$EXAMPLE" "$P2/analysis/src/extraction-quality.json"
J="$(run "$P2" --json)"
[ "$(printf '%s' "$J" | jget 'len(b["extractionQuality"][0]["rows"])')" = 6 ] && ok "Q2 six rows" || bad "Q2 six rows" "$J"
[ "$(printf '%s' "$J" | jget 'b["extractionQuality"][0]["verdict"]')" = manual ] && ok "Q2 not passed → manual" || bad "Q2 not passed → manual" "$J"
[ "$(printf '%s' "$J" | jget 'b["sections"]["quality:analysis/src/extraction-quality.json"]')" = manual ] \
  && ok "Q2 section keyed by file" || bad "Q2 section keyed by file" "$J"
H="$(cat "$P2/analysis/src/knowledge-base/extraction-report.html")"
has "Q2 html section"        "$H" "<h2>Extraction quality</h2>"
has "Q2 html dimension key"  "$H" ">entityFields<"
has "Q2 html found/expected" "$H" "49 / 50"
has "Q2 html gap text"       "$H" "User.avatar missing"
has "Q2 html overall"        "$H" "Overall <strong>94.2</strong> against threshold <strong>95</strong>"
has "Q2 html confirmed zero" "$H" "ts-ast, python-regex"
O="$(run "$P2")"
has "Q2 prose line" "$O" "quality analysis/src/extraction-quality.json: overall 94.2 / threshold 95, passed=False, selfGraded=no, 6 dimension(s)"

# --- Q3 -------------------------------------------------------------------------------------
P3="$WORK/p3"; doc_kb "$P3"; mkdir -p "$P3/analysis/src/extracted"
mutate "$EXAMPLE" "$P3/analysis/src/extracted/extraction-quality-procmodel.json" '
d["dimensions"]={k:{"score":100,"found":n,"expected":n,"gaps":[]} for k,n in
  (("nodes",41),("transitions",57),("guards",12),("documentation",41),("diagramMembership",41),("labelRecall",88),("images",3))}
d["overallScore"]=100; d["passed"]=True; d["selfGraded"]=True; d["confirmedZeros"]=[]'
J="$(run "$P3" --json)"
[ "$(printf '%s' "$J" | jget 'b["extractionQuality"][0]["verdict"]')" = fault ] && ok "Q3 self-graded pass → fault" || bad "Q3 self-graded pass → fault" "$J"
[ "$(printf '%s' "$J" | jget 'len(b["extractionQuality"][0]["rows"])')" = 7 ] && ok "Q3 the file's own 7 dimensions" || bad "Q3 the file's own 7 dimensions" "$J"
O="$(run "$P3")"
has "Q3 prose FAULT names it" "$O" "self-graded pass"
H="$(cat "$P3/analysis/src/knowledge-base/extraction-report.html")"
has "Q3 html stack's own key" "$H" ">labelRecall<"

# --- Q4 / Q5 --------------------------------------------------------------------------------
P4="$WORK/p4"; code_kb "$P4"
J="$(run "$P4" --json)"
[ "$(printf '%s' "$J" | jget 'b["sections"].get("extractionQuality")')" = manual ] \
  && ok "Q4 code-extracted, no file → manual" || bad "Q4 code-extracted, no file → manual" "$J"
O="$(run "$P4")"
has "Q4 says not produced yet" "$O" "not produced yet — no shipped pipeline writes a validator"
cp "$EXAMPLE" "$P4/analysis/src/knowledge-base/extracted/extraction-quality.json"
J="$(run "$P4" --json)"
hasnt "Q5 score file not read as an item array" "$J" "would not parse"
[ "$(printf '%s' "$J" | jget 'b["extractionQuality"][0]["file"]')" = "analysis/src/knowledge-base/extracted/extraction-quality.json" ] \
  && ok "Q5 found inside <kb>/extracted" || bad "Q5 found inside <kb>/extracted" "$J"

# --- Q6 -------------------------------------------------------------------------------------
P6="$WORK/p6"; doc_kb "$P6"
mutate "$EXAMPLE" "$P6/analysis/src/extraction-quality.json" '
d["dimensions"]["enumerations"].update(found=0, expected=0, score=100)
d["dimensions"]["endpoints"].update(found=0, expected=0, score=100, gaps=[])'
J="$(run "$P6" --json)"
[ "$(printf '%s' "$J" | jget '[r["flag"] for r in b["extractionQuality"][0]["rows"] if r["dimension"]=="endpoints"][0]')" = "unconfirmed zero" ] \
  && ok "Q6 unconfirmed 0/0 flagged" || bad "Q6 unconfirmed 0/0 flagged" "$J"
[ "$(printf '%s' "$J" | jget '[r["flag"] for r in b["extractionQuality"][0]["rows"] if r["dimension"]=="enumerations"][0]')" = "" ] \
  && ok "Q6 confirmed 0/0 not flagged" || bad "Q6 confirmed 0/0 not flagged" "$J"
[ "$(printf '%s' "$J" | jget 'b["extractionQuality"][0]["verdict"]')" = fault ] && ok "Q6 → fault" || bad "Q6 → fault" "$J"

# --- Q7 -------------------------------------------------------------------------------------
P7="$WORK/p7"; doc_kb "$P7"; mkdir -p "$P7/analysis/src/extracted"
mutate "$EXAMPLE" "$P7/analysis/src/extraction-quality.json" 'd["passed"]=True'
printf '{"overallScore": 9' > "$P7/analysis/src/extracted/extraction-quality-broken.json"
J="$(run "$P7" --json)"; RC=$?
[ "$RC" = 0 ] && ok "Q7 exit 0 (a fault is information)" || bad "Q7 exit 0" "rc=$RC"
[ "$(printf '%s' "$J" | jget 'sorted(q["verdict"] for q in b["extractionQuality"])')" = "['fault', 'fault']" ] \
  && ok "Q7 under-threshold pass and broken file both fault" || bad "Q7 both fault" "$J"
has "Q7 contradiction named" "$J" "under the file's own threshold 95"
[ -s "$P7/analysis/src/knowledge-base/extraction-report.html" ] && ok "Q7 page still rendered" || bad "Q7 page still rendered"

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" = 0 ]
