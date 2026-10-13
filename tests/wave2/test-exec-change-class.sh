#!/bin/bash
# test-exec-change-class.sh — exec.sh's advisory change-class tag (ui-only | logic).
#
# Usage: bash test-exec-change-class.sh [path-to-exec.sh]
#
# WHY. testing-shape.md §3 scopes re-runs by what a change touched: a UI-only change re-runs its
# own journey once plus a LOOK; a logic change re-runs the tests whose subject it touched. exec.sh
# prints which lane applies, so the lane is in front of whoever reads the run rather than left to
# habit (toolkit issue #274: UI-only changes re-proven 5-10x in a 20-task UX-fix run).
#
# GOLDEN INPUT IS REAL MDL, never hand-written statements: the toolkit's own shipped scripts
# (skills/agents-examples/, examples/stylegallery/mdlsource/gallery/) and the verbatim/exec'd
# page fixtures under tests/wave2/fixtures/page-fidelity-mocks/. The one "mixed" case built here
# is two real files concatenated, which is what a batch script that touches both looks like.
#
# Covers: ui-only (ALTER PAGE, CREATE SNIPPET with comments, CREATE PAGE with string literals
# holding braces/quotes); logic (microflow, module, entity); mixed → logic (page + GRANT, snippets
# + microflow, concatenation); a script with no page statement → logic; the mode writes nothing
# and needs no .mpr; and that the run actually carries the tag (BUILD-LOG detail + summary).

TOOLKIT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SUBJECT="${1:-$TOOLKIT/project-bin/exec.sh}"
case "$SUBJECT" in /*) ;; *) SUBJECT="$PWD/$SUBJECT" ;; esac
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  ok   — $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL — $1"; }

WORK=$(mktemp -d "${TMPDIR:-/tmp}/chgcls.XXXXXX") || exit 2
trap 'rm -rf "$WORK"' EXIT
echo "== subject: $SUBJECT"

AG="$TOOLKIT/skills/agents-examples"
GAL="$TOOLKIT/examples/stylegallery/mdlsource/gallery"
PFM="$TOOLKIT/tests/wave2/fixtures/page-fidelity-mocks"

# Run from an empty dir with no .mpr: the mode must not need a project and must write nothing.
cls() { (cd "$WORK/empty" && bash "$SUBJECT" --change-class "$1" 2>&1); }
mkdir -p "$WORK/empty"

expect() {  # $1=file  $2=class  $3=label
  [ -f "$1" ] || { bad "$3 — golden input missing: ${1#$TOOLKIT/}"; return; }
  out="$(cls "$1")"; got="$(printf '%s' "$out" | cut -f1)"
  [ "$got" = "$2" ] && ok "$3 → $2" || bad "$3 → expected $2, got: $out"
}

echo "-- ui-only"
expect "$PFM/bind-contract-alter.mdl"        ui-only "ALTER PAGE with set ... on (bind-contract-alter)"
expect "$GAL/13-badges-chips.mdl"            ui-only "CREATE SNIPPET, brace on its own line (13-badges-chips)"
expect "$AG/agent-snippet.example.mdl"       ui-only "CREATE OR MODIFY SNIPPET with -- and /** */ comments (agent-snippet)"
expect "$PFM/dynclasses-script.mdl"          ui-only "CREATE PAGE whose DynamicClasses string holds quotes (dynclasses-script)"
expect "$PFM/commented-template-snippets.mdl" ui-only "page + snippet, both UI (commented-template-snippets)"

echo "-- logic"
expect "$AG/tool-write.example.mdl"          logic "CREATE OR MODIFY MICROFLOW (tool-write)"
expect "$GAL/00-module.mdl"                  logic "CREATE MODULE (gallery 00-module)"
expect "$GAL/05-demo-data.mdl"               logic "non-persistent entities + datasource microflows (gallery 05-demo-data)"

echo "-- mixed → logic"
expect "$GAL/90-gallery-home.mdl"            logic "CREATE PAGE + GRANT VIEW ON PAGE — a grant is security (gallery 90-gallery-home)"
out="$(cls "$GAL/90-gallery-home.mdl")"
case "$out" in *grant*) ok "  and names the GRANT as the deciding statement" ;;
               *) bad "  deciding statement not the grant: $out" ;; esac
expect "$GAL/18-breadcrumbs.mdl"             logic "snippets + a navigation microflow (gallery 18-breadcrumbs)"
cat "$PFM/bind-contract-alter.mdl" "$AG/tool-write.example.mdl" > "$WORK/mixed.mdl"
expect "$WORK/mixed.mdl"                     logic "ALTER PAGE then a microflow, one batch (two real files concatenated)"
cat "$AG/tool-write.example.mdl" "$PFM/bind-contract-alter.mdl" > "$WORK/mixed2.mdl"
expect "$WORK/mixed2.mdl"                    logic "microflow first, page second — order does not matter"

echo "-- edges"
expect "$TOOLKIT/fixtures/import-mapping-range-repro/import.test.mdl" logic \
       "no page/snippet statement at all → logic (the heavier lane when unsure)"
[ -z "$(ls -A "$WORK/empty")" ] && ok "--change-class wrote nothing and needed no .mpr" \
                               || bad "--change-class wrote into the cwd: $(ls -A "$WORK/empty")"
(cd "$WORK/empty" && bash "$SUBJECT" --change-class "$WORK/no-such.mdl" >/dev/null 2>&1); rc=$?
[ "$rc" = 2 ] && ok "missing script → exit 2" || bad "missing script exited $rc"

echo "-- wiring: the run carries the tag"
grep -q 'change: \$CHANGE_CLASS' "$SUBJECT" && ok "BUILD-LOG detail carries 'change: <class>'" \
                                            || bad "log_build detail does not carry the change class"
grep -q 'change class: \$CHANGE_CLASS — test lane' "$SUBJECT" && ok "success summary prints the class and its test lane" \
                                                           || bad "summary does not print the change class"
grep -q 'testing-shape.md' "$SUBJECT" && ok "the lane text points at testing-shape.md" \
                                      || bad "no pointer to testing-shape.md"
# A changed snippet or layout is shown on every page that embeds it, so its ui-only lane is those
# pages' journeys — not "no other module's journeys" (independent review of #290).
_lane="$(grep -E '^ +ui-only\) echo' "$SUBJECT")"
case "$_lane" in
  *"no other module's journeys"*) bad "ui-only lane still says 'no other module's journeys' (wrong for a snippet/layout)" ;;
  *"embedders of a changed snippet/layout"*) ok "ui-only lane names the embedders of a changed snippet/layout" ;;
  *) bad "ui-only lane text not found or does not name embedders: $_lane" ;;
esac
# The metrics ledger is 19 fixed columns (test-metrics-ledger.sh asserts it); the tag must not
# be smuggled into it as a 20th.
grep -qiE 'change[_ -]class' "$(dirname "$SUBJECT")/metrics-ledger.sh" 2>/dev/null \
  && bad "metrics-ledger.sh grew a change-class column" || ok "metrics ledger untouched (19 columns stay 19)"

echo; echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
