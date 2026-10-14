#!/usr/bin/env bash
# Usage: bash test-named-controls.sh [path-to-named-controls.js]
#
# Fixture for project-tests/e2e/named-controls.js and journey-runner.js's named-control
# warning and --out= (#159). The runner beside the subject is the one exercised.
#
# The defect (card-disbursement requirements-driven build, 2026-09-26): a journey passed every
# rung and its --positive-control proved every rung, while its claim was true only by accident.
# Its named control read NOT PROVEN. A named control is PROVEN only when the runner exits 1,
# every check whose name contains mustFail is FAIL (at least one), and nothing else is red.
#
# Golden input is CAPTURED: fixtures/journey-control/walk-run.json is that build's real walk
# (79 rows, all PASS), trimmed to rung/name/verdict. Each case derives a control run from it by
# editing single rows, the shape each control outcome takes in the field. No field run of
# named-controls.js against a live app has been made from the toolkit copy yet.

set -uo pipefail

SUT="${1:-}"
[ -z "$SUT" ] && SUT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/project-tests/e2e/named-controls.js"
if [ ! -f "$SUT" ]; then
  echo "SKIP: subject not found at $SUT"
  echo "SCORE: 0/0 — nothing to test"
  exit 0
fi
command -v node >/dev/null 2>&1 || { echo "SKIP: node not installed"; exit 0; }
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FIX="$HERE/fixtures/journey-control"
[ -f "$FIX/walk-run.json" ] || { echo "FAIL — golden capture missing under $FIX"; exit 1; }
E2E="$(cd "$(dirname "$SUT")" && pwd)"
for f in journey-runner.js helpers.js settle.js otel.js config.js; do
  [ -f "$E2E/$f" ] || { echo "FAIL — $f not beside $SUT"; exit 1; }
done
CFG="$E2E/project.config.template.js"
[ -f "$CFG" ] || CFG="$HERE/../../project-tests/e2e/project.config.template.js"

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  ok   — $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL — $1"; [ -n "${2:-}" ] && echo "         got: $2"; }

# The runner and config resolve a project at require time: an .mpr two levels up.
WORK="$(mktemp -d "${TMPDIR:-/tmp}/named-controls.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/tests/e2e" "$WORK/journeys/controls" "$WORK/stub"; : > "$WORK/Fixture.mpr"
cp "$SUT" "$E2E/journey-runner.js" "$E2E/helpers.js" "$E2E/settle.js" "$E2E/otel.js" "$E2E/config.js" "$WORK/tests/e2e/"
cp "$CFG" "$WORK/tests/e2e/project.config.js"

echo "== judge(): the three PROVEN rules over the captured walk =="
IFS= read -r -d '' JS <<'EOF' || true
const fix = process.argv[2];
const N = require('./named-controls.js');
const walk = require(fix + '/walk-run.json');
const clone = () => JSON.parse(JSON.stringify(walk.results));
const name = walk.results[walk.results.length - 1].name;    // the claim this control targets
const say = (k, code, rows, mf = name) => { const v = N.judge(code, rows, mf); console.log(`${k} ${v.verdict} | ${v.why}`); };
let r = clone(); r[r.length - 1].verdict = 'FAIL';            say('PROVEN', 1, r);
say('EXIT0', 0, clone());                                      // claim held: app satisfied it
r = clone(); r[r.length - 1].verdict = 'FAIL';                 say('EXIT2', 2, r);
r = clone(); r[r.length - 1].verdict = 'FAIL';                 say('NOMATCH', 1, r, 'no check is named this');
r = clone(); r[r.length - 1].verdict = 'INVALID';              say('NAMEDINV', 1, r);
r = clone(); r[r.length - 1].verdict = 'FAIL'; r[0].verdict = 'FAIL';    say('ELSEFAIL', 1, r);
r = clone(); r[r.length - 1].verdict = 'FAIL'; r[0].verdict = 'INVALID'; say('ELSEINV', 1, r);
EOF
OUT="$(cd "$WORK/tests/e2e" && printf '%s' "$JS" | APP_PORT=1 node - "$FIX" 2>&1)"
line() { printf '%s\n' "$OUT" | sed -n "s/^$1 //p"; }
[ -n "$(line PROVEN)" ] || { echo "FAIL — harness could not require $SUT"; echo "$OUT" | tail -5; exit 1; }
case "$(line PROVEN)"   in 'PROVEN |'*) ok "exit 1 + named check FAIL + nothing else red → PROVEN" ;; *) bad "proven control not PROVEN" "$(line PROVEN)" ;; esac
case "$(line EXIT0)"    in 'NOT PROVEN |'*'exited 0'*) ok "runner exit 0 (app satisfied the claim) → NOT PROVEN" ;; *) bad "exit 0 accepted" "$(line EXIT0)" ;; esac
case "$(line EXIT2)"    in 'NOT PROVEN |'*'exited 2'*) ok "runner exit 2 (preflight abort) → NOT PROVEN" ;; *) bad "exit 2 accepted" "$(line EXIT2)" ;; esac
case "$(line NOMATCH)"  in 'NOT PROVEN |'*'no check name contains'*) ok "mustFail matching no check → NOT PROVEN" ;; *) bad "zero named checks accepted" "$(line NOMATCH)" ;; esac
case "$(line NAMEDINV)" in 'NOT PROVEN |'*'INVALID'*) ok "named check INVALID, not FAIL → NOT PROVEN" ;; *) bad "INVALID named check accepted" "$(line NAMEDINV)" ;; esac
case "$(line ELSEFAIL)" in 'NOT PROVEN |'*'red elsewhere'*) ok "rule 3: a FAIL elsewhere → NOT PROVEN" ;; *) bad "red elsewhere accepted" "$(line ELSEFAIL)" ;; esac
case "$(line ELSEINV)"  in 'NOT PROVEN |'*'red elsewhere'*) ok "rule 3: an INVALID elsewhere → NOT PROVEN" ;; *) bad "INVALID elsewhere accepted" "$(line ELSEINV)" ;; esac

echo "== runControl(): persona gate, --out= handoff, stale file =="
# A stub runner stands in for journey-runner.js: it writes the captured walk with the last row
# FAILed to the --out= path, and exits 1. STUB_MODE=nofile exits 1 and writes nothing.
cat > "$WORK/stub/runner.js" <<'EOF'
const fs = require('fs');
const out = (process.argv.find(a => a.startsWith('--out=')) || '').slice(6);
fs.appendFileSync(process.env.STUB_ARGV, process.argv.slice(2).join(' ') + '\n');
if (process.env.STUB_MODE !== 'nofile') {
  const w = JSON.parse(fs.readFileSync(process.env.WALK, 'utf8'));
  w.results[w.results.length - 1].verdict = 'FAIL';
  fs.writeFileSync(out, JSON.stringify(w));
}
process.exit(1);
EOF
LAST="$(node -e 'const w=require(process.argv[1]); console.log(w.results[w.results.length-1].name)' "$FIX/walk-run.json")"
mk() { node -e 'const [f,id,p,mf]=process.argv.slice(1); const j={id,title:"control",steps:[{name:"s"}],control:{of:"J-01",mustFail:mf}}; if(p!=="-") j.persona=p; require("fs").writeFileSync(f,JSON.stringify(j))' "$@"; }
mk "$WORK/journeys/controls/C-ok.json" C-ok demo_user "$LAST"
mk "$WORK/journeys/controls/C-who.json" C-who Reviewer "$LAST"
IFS= read -r -d '' JS2 <<'EOF' || true
const [runner, art, dir] = process.argv.slice(2);
const N = require('./named-controls.js');
const fs = require('fs');
const show = (k, r) => console.log(`${k} ${r.verdict} | ${r.why}`);
show('RUN', N.runControl(dir + '/C-ok.json', { user: 'demo_user', artifactsDir: art, runner }));
console.log('OUTFILE ' + fs.existsSync(art + '/control-C-ok.json'));
show('WHO', N.runControl(dir + '/C-who.json', { user: 'demo_user', artifactsDir: art, runner }));
fs.writeFileSync(art + '/control-C-ok.json', JSON.stringify({ results: [] }));   // stale file
process.env.STUB_MODE = 'nofile';
show('STALE', N.runControl(dir + '/C-ok.json', { user: 'demo_user', artifactsDir: art, runner }));
EOF
mkdir -p "$WORK/art"; : > "$WORK/argv"
OUT="$(cd "$WORK/tests/e2e" && printf '%s' "$JS2" | APP_PORT=1 WALK="$FIX/walk-run.json" STUB_ARGV="$WORK/argv" \
       node - "$WORK/stub/runner.js" "$WORK/art" "$WORK/journeys/controls" 2>&1)"
case "$(line RUN)" in 'PROVEN |'*) ok "spawned runner exit 1 + findings at --out= → PROVEN" ;; *) bad "runControl did not prove a proven control" "$OUT" ;; esac
grep -q -- "--out=$WORK/art/control-C-ok.json" "$WORK/argv" && ok "runner is passed --out=<artifacts>/control-<id>.json" \
  || bad "--out= not passed as control-<id>.json" "$(cat "$WORK/argv")"
case "$(line WHO)" in 'FAULT |'*'not run'*) ok "persona ≠ run user → FAULT, runner not spawned" ;; *) bad "persona mismatch not a FAULT" "$(line WHO)" ;; esac
[ "$(grep -c 'C-who' "$WORK/argv")" -eq 0 ] || bad "runner was spawned for a persona-mismatched control"
case "$(line STALE)" in 'NOT PROVEN |'*'wrote no findings'*) ok "a stale findings file from an earlier run is not read" ;; *) bad "stale findings file read" "$(line STALE)" ;; esac

echo "== journey-runner.js: named-control gaps (warn-only) =="
IFS= read -r -d '' JS3 <<'EOF' || true
const dir = process.argv[2];
const R = require('./journey-runner.js');
if (typeof R.namedControlGaps !== 'function') { console.log('NOFN'); process.exit(0); }
const g = R.namedControlGaps([
  { id: 'J-01', claim: 'a case waits while upstream is offline' },
  { id: 'J-02' },
  { id: 'J-03', claim: 'x' },
  { id: 'C-ok', control: { of: 'J-01', mustFail: 'x' } },
], R.findControls([dir + '/J-01.journey.json']));
console.log('GAPS ' + JSON.stringify(g));
EOF
OUT="$(cd "$WORK/tests/e2e" && printf '%s' "$JS3" | APP_PORT=1 node - "$WORK/journeys" 2>&1)"
if printf '%s\n' "$OUT" | grep -qx NOFN; then bad "journey-runner.js exports no namedControlGaps"; else
  G="$(line GAPS)"
  case "$G" in *'J-01'*) bad "J-01 has a claim and a control in controls/, still flagged" "$G" ;; *) ok "claim + control in controls/ → no gap" ;; esac
  case "$G" in *'J-02: no \"claim\"'*'J-02: no named control'*) ok "no claim and no control → both named" ;; *) bad "J-02 gaps missing" "$G" ;; esac
  case "$G" in *'J-03: no \"claim\"'*) bad "J-03 has a claim, flagged anyway" "$G" ;; *'J-03: no named control'*) ok "claim without control → control gap only" ;; *) bad "J-03 control gap missing" "$G" ;; esac
  case "$G" in *'C-ok'*) bad "a control file was itself checked" "$G" ;; *) ok "control files are not themselves checked" ;; esac
fi

echo "== real runner: --out= and the WARN line, through a preflight abort =="
# TEST_PASS unset aborts in preflight before any login or probe (#278) and writes aborted
# findings, so this exercises --out= and the warning without an app.
node -e 'require("fs").writeFileSync(process.argv[1], JSON.stringify({id:"J-02",steps:[{name:"s"}]}))' "$WORK/journeys/J-02.journey.json"
E2EOUT="$(cd "$WORK/tests/e2e" && env -u TEST_PASS -u APP_PASS -u ALLOW_CONFIG_CREDENTIALS APP_PORT=1 \
          node journey-runner.js "$WORK/journeys/J-02.journey.json" "--out=$WORK/art/custom.json" 2>&1)"; RC=$?
[ "$RC" -eq 2 ] && ok "preflight abort exit 2 (fixture precondition)" || bad "expected preflight exit 2" "rc=$RC $(printf '%s' "$E2EOUT" | tail -3)"
[ -f "$WORK/art/custom.json" ] && ok "findings written to the --out= path" || bad "no findings at --out= path" "$(printf '%s' "$E2EOUT" | grep findings)"
[ ! -f "$WORK/tests/e2e/artifacts/journey-findings.json" ] && ok "default slot untouched under --out=" || bad "default slot written under --out="
[ "$(printf '%s\n' "$E2EOUT" | grep -c 'WARN   named control: J-02')" -eq 2 ] && ok "two WARN lines for J-02 (no claim, no control)" \
  || bad "WARN lines missing" "$(printf '%s\n' "$E2EOUT" | grep -i 'named control')"

echo ""
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
