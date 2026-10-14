#!/usr/bin/env bash
# Usage: bash test-oql-rows.sh [path-to-helpers.js]
#
# Fixture for project-tests/e2e/helpers.js's OQL reader — parseOqlOutput(), oqlScalar(),
# oqlRows(), oqlAliases() (#154).
#
# The defect (card-disbursement requirements-driven build, 2026-09-26/27): oql() turned each
# row of `mxcli oql --direct --json` into `Object.values(r)` and oqlScalar read rows[0][0].
# mxcli prints the keys ALPHABETICALLY and leaves out a column that is null in every row, so
# positions were not SELECT positions; over a view entity the answer carries `ID` beside the
# alias, and rows[0][0] was the ID, not the count. A string value holding `]` or `}` ended the
# brace-counting slice early and the helper returned null on a real answer.
#
# Golden input is CAPTURED: fixtures/oql-json/<case>.stdout|.stderr are the released mxcli
# v0.26.0 binary's verbatim output for the queries in fixtures/oql-json/cases.txt, run against
# fixtures/oql-json/admin-api-stub.js (the runtime half is synthetic, shaped after mxcli's own
# tests: null columns omitted from a row object). mxcli's own JSON formatting is the real part.
# Not captured: a live runtime's answer over a real view entity (no app reachable from the
# session that wrote this); the view case's `ID` key is the shape the field report describes.

set -uo pipefail

SUT="${1:-}"
[ -z "$SUT" ] && SUT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/project-tests/e2e/helpers.js"
if [ ! -f "$SUT" ]; then
  echo "SKIP: subject not found at $SUT"
  echo "SCORE: 0/0 — nothing to test"
  exit 0
fi
command -v node >/dev/null 2>&1 || { echo "SKIP: node not installed"; exit 0; }
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FIX="$HERE/fixtures/oql-json"
for c in nullcol allnull view bracket; do
  for x in stdout stderr; do [ -f "$FIX/$c.$x" ] || { echo "FAIL — golden missing: $FIX/$c.$x"; exit 1; }; done
done
E2E="$(cd "$(dirname "$SUT")" && pwd)"
CFG="$E2E/project.config.template.js"
[ -f "$CFG" ] || CFG="$HERE/../../project-tests/e2e/project.config.template.js"

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  ok   — $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL — $1"; [ -n "${2:-}" ] && printf '%s\n' "$2" | sed 's/^/         got: /'; }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/oql-rows.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/tests/e2e" "$WORK/stub"; : > "$WORK/Fixture.mpr"
cp "$SUT" "$WORK/tests/e2e/helpers.js"
cp "$E2E/config.js" "$WORK/tests/e2e/"
cp "$CFG" "$WORK/tests/e2e/project.config.js"

# A stub mxcli that replays a captured case: stdout and stderr verbatim, exit 0.
cat > "$WORK/stub/mxcli" <<'EOF'
#!/usr/bin/env bash
cat "$FIXDIR/$CASE.stdout"; cat "$FIXDIR/$CASE.stderr" >&2
EOF
chmod +x "$WORK/stub/mxcli"

sqlof() { awk -F'\t' -v c="$1" '$1==c{print $2}' "$FIX/cases.txt"; }
export Q_NULLCOL="$(sqlof nullcol)" Q_ALLNULL="$(sqlof allnull)" Q_VIEW="$(sqlof view)" Q_BRACKET="$(sqlof bracket)"
[ -n "$Q_NULLCOL" ] && [ -n "$Q_VIEW" ] && [ -n "$Q_BRACKET" ] && [ -n "$Q_ALLNULL" ] \
  || { echo "FAIL — cases.txt lost a query"; exit 1; }

IFS= read -r -d '' JS <<'JSEOF' || true
const fs = require('fs');
const H = require('./helpers.js');
const E = process.env;
const out = (k, v) => console.log(`${k} ${typeof v === 'string' ? v : JSON.stringify(v)}`);
const cap = c => fs.readFileSync(`${E.FIXDIR}/${c}.stdout`, 'utf8');
const P = (c, q) => { const r = H.parseOqlOutput(cap(c), q); return r && { rows: r.rows, objects: r.objects }; };

// one parser over the captured stdout
out('P_NULLCOL', P('nullcol', E.Q_NULLCOL));
out('P_ALLNULL', P('allnull', E.Q_ALLNULL));
out('P_VIEW', P('view', E.Q_VIEW));
out('P_BRACKET', P('bracket', E.Q_BRACKET));
// stdout + stderr together, as the admin preflight reads it
out('P_MIXED', P('view', E.Q_VIEW) && H.parseOqlOutput(cap('view') + fs.readFileSync(`${E.FIXDIR}/view.stderr`, 'utf8'), E.Q_VIEW).rows);

// through the real oql() spawn, the stub replaying each case
const scal = (c, q) => { process.env.CASE = c; return JSON.stringify(H.oqlScalar(q)); };  // JSON: the string "null" is not null
const rowsOf = (c, q) => { process.env.CASE = c; return typeof H.oqlRows === 'function' ? H.oqlRows(q) : 'NOFN'; };
out('S_VIEW', scal('view', E.Q_VIEW));
out('S_BRACKET', scal('bracket', E.Q_BRACKET));
out('S_NULLFIRST', scal('nullcol', 'SELECT c.Alpha AS alpha, c.Mid AS mid FROM M.E AS c'));
out('S_NOSQLALIAS', scal('view', 'SELECT * FROM M.V'));
out('R_NULLCOL', rowsOf('nullcol', E.Q_NULLCOL));

// alias reading
const A = q => (typeof H.oqlAliases === 'function' ? H.oqlAliases(q) : 'NOFN');
out('A_PLAIN', A('SELECT COUNT(*) AS n FROM System.Session'));
out('A_NESTED', A("SELECT COALESCE(c.A, 'x, y') AS a, (SELECT COUNT(o.ID) FROM M.O AS o WHERE o.X = c.ID) AS cnt, c/M.Assoc/M.T/Name FROM M.E AS c"));
out('A_DISTINCT', A('select distinct c.Name as "Label" from M.E as c'));
out('A_UNNAMED', A('SELECT COUNT(*) FROM M.E'));
out('A_NOFROM', A('SELECT 1 AS n'));
JSEOF

OUT="$(cd "$WORK/tests/e2e" && printf '%s' "$JS" | APP_PORT=1 MXCLI="$WORK/stub/mxcli" FIXDIR="$FIX" node - 2>&1)"
line() { printf '%s\n' "$OUT" | sed -n "s/^$1 //p"; }
[ -n "$(line P_NULLCOL)" ] || { echo "FAIL — harness could not require $SUT"; echo "$OUT" | tail -8; exit 1; }

echo "== T1: rows keyed by SELECT alias, in SELECT order, explicit nulls =="
[ "$(line P_NULLCOL)" = '{"rows":[["z1",null,"m1"],["z2","a2","m2"]],"objects":[{"zeta":"z1","alpha":null,"mid":"m1"},{"zeta":"z2","alpha":"a2","mid":"m2"}]}' ] \
  && ok "alphabetical keys back in SELECT order (zeta, alpha, mid); row 1's null alpha explicit" \
  || bad "rows not in SELECT order" "$(line P_NULLCOL)"
[ "$(line P_ALLNULL)" = '{"rows":[["z1",null,"m1"]],"objects":[{"zeta":"z1","alpha":null,"mid":"m1"}]}' ] \
  && ok "a column mxcli left out entirely (null in every row) keeps its slot — mid is not shifted left" \
  || bad "all-null column shifted the row (the #154 positional read)" "$(line P_ALLNULL)"
[ "$(line P_VIEW)" = '{"rows":[["7"]],"objects":[{"n":"7"}]}' ] \
  && ok "view answer: the ID key is not a column of SELECT … AS n" || bad "view's ID read as a column" "$(line P_VIEW)"
[ "$(line P_BRACKET)" = '{"rows":[["a]b}c\"d","2"]],"objects":[{"label":"a]b}c\"d","n":"2"}]}' ] \
  && ok "string value holding ] } and \" parses (string-aware slice)" || bad "bracket in a string broke the slice" "$(line P_BRACKET)"
[ "$(line P_MIXED)" = '[["7"]]' ] && ok "stdout + stderr (warning, row count) still parses" || bad "mixed streams misread" "$(line P_MIXED)"

echo "== T2: oqlScalar reads the FIRST alias, through the real spawn =="
[ "$(line S_VIEW)" = '"7"' ] && ok "COUNT over a view entity → 7, not the view row's ID" || bad "oqlScalar over a view read the ID" "$(line S_VIEW)"
[ "$(line S_BRACKET)" = '"a]b}c\"d"' ] && ok "first alias (label) of the bracket case, not null" || bad "bracket case lost" "$(line S_BRACKET)"
[ "$(line S_NULLFIRST)" = null ] && ok "first alias null in row 1 → null (no measurement), not the next column" || bad "null first alias read a neighbour" "$(line S_NULLFIRST)"
[ "$(line S_NOSQLALIAS)" = null ] && ok "SELECT * over a two-key answer → null, never a guessed column" || bad "guessed a column" "$(line S_NOSQLALIAS)"
[ "$(line R_NULLCOL)" = '[{"zeta":"z1","alpha":null,"mid":"m1"},{"zeta":"z2","alpha":"a2","mid":"m2"}]' ] \
  && ok "oqlRows → alias-keyed objects with every alias present" || bad "oqlRows wrong or missing" "$(line R_NULLCOL)"

echo "== T3: the SELECT list is read, not split on every comma =="
[ "$(line A_PLAIN)" = '["n"]' ] && ok "COUNT(*) AS n → n" || bad "plain alias" "$(line A_PLAIN)"
[ "$(line A_NESTED)" = '["a","cnt","Name"]' ] && ok "commas in parens/strings and a subquery's FROM ignored; bare path → its last segment" || bad "nested list misread" "$(line A_NESTED)"
[ "$(line A_DISTINCT)" = '["Label"]' ] && ok "lower-case keywords, DISTINCT, quoted alias" || bad "distinct/quoted alias" "$(line A_DISTINCT)"
[ "$(line A_UNNAMED)" = '[null]' ] && ok "an unnamed expression is null, not invented" || bad "unnamed column named" "$(line A_UNNAMED)"
[ "$(line A_NOFROM)" = '["n"]' ] && ok "SELECT without FROM" || bad "no-FROM select" "$(line A_NOFROM)"

echo ""
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
