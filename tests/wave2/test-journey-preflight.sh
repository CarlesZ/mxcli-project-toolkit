#!/usr/bin/env bash
# Usage: bash test-journey-preflight.sh [path-to-journey-runner.js]
#
# Fixture for project-tests/e2e/journey-runner.js's suite preflight and declared journey state
# (#286, #287 item 1), plus config.js's admin-credential resolution.
#
# The defect (field run 2026-10-12, 14 journeys): the admin credential defaulted to a value
# that was not the app's, every data rung got HTTP 403 and read INVALID, and the suite walked
# all 14 journeys anyway (first pass 305/339, 2 of 14 green, discarded). Two unset mock env
# vars made 3 journeys INVALID one by one; an undeclared order dependency made 6 of 14 INVALID.
#
# Golden input is CAPTURED, never invented:
#   fixtures/journey-preflight/mxcli-0.26.0-oql-messages.txt — mxcli's own auth/unreachable/
#     banner/row-count format strings, read out of the released binary (see its header).
#   fixtures/journey-preflight/docker-env.example — the .docker/.env template mxcli writes.
#   fixtures/run-local/run-local.json — the captured `mxcli run --local` handshake (reused;
#     its adminPass is replaced by a marker here, as test-stack-up-local.sh does).
# The success body ([{"n":"3"}]) is the column-keyed shape helpers.js documents for --json.
#
# Cases: unset TEST_PASS refuses before any login (#278); resetsData + --protect-state (#279);
# the landing judge counts outlines and focus box-shadows (#281; the in-page collector needs a
# browser and is not fixtured — the snapshot rows here are that collector's own output shape); 403 aborts the whole suite before any journey (pure + end-to-end through the real
# runner with a stub mxcli); missing env vars are ONE SETUP line; requires/leaves/consumes
# order the suite and name the unmet precondition; journeys without headers behave as before;
# the credential source is named and the credential never printed.
# Not fixtured: the browser half (login/logout) — needs a live app.

set -uo pipefail

SUT="${1:-}"
[ -z "$SUT" ] && SUT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/project-tests/e2e/journey-runner.js"
if [ ! -f "$SUT" ]; then
  echo "SKIP: subject not found at $SUT"
  echo "SCORE: 0/0 — nothing to test"
  exit 0
fi
command -v node >/dev/null 2>&1 || { echo "SKIP: node not installed"; exit 0; }
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FIX="$HERE/fixtures/journey-preflight"
MSGS="$FIX/mxcli-0.26.0-oql-messages.txt"
DENV="$FIX/docker-env.example"
RLJ="$HERE/fixtures/run-local/run-local.json"
for f in "$MSGS" "$DENV" "$RLJ"; do [ -f "$f" ] || { echo "FAIL — golden missing: $f"; exit 1; }; done
E2E="$(cd "$(dirname "$SUT")" && pwd)"
for f in helpers.js otel.js config.js settle.js; do
  [ -f "$E2E/$f" ] || { echo "FAIL — $f not beside $SUT"; exit 1; }
done
CFG="$E2E/project.config.template.js"
[ -f "$CFG" ] || CFG="$HERE/../../project-tests/e2e/project.config.template.js"

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  ok   — $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL — $1"; [ -n "${2:-}" ] && printf '%s\n' "$2" | sed 's/^/         got: /'; }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/journey-preflight.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/tests/e2e"; : > "$WORK/Fixture.mpr"
cp "$SUT" "$E2E/helpers.js" "$E2E/settle.js" "$E2E/otel.js" "$E2E/config.js" "$WORK/tests/e2e/"
cp "$CFG" "$WORK/tests/e2e/project.config.js"

# Probe texts, built from the captured format strings (verbs filled, nothing reworded).
fmt() { sed -n '/^--- formats ---$/,$p' "$MSGS" | grep -F "$1" | head -1; }
AUTH_FMT="$(fmt 'authentication failed')"; CONN_FMT="$(fmt 'cannot connect')"
BANNER_FMT="$(fmt 'Using project')"; ROWS_FMT="$(fmt 'rows)')"
echo "== T0: golden carries mxcli's own messages =="
[ -n "$AUTH_FMT" ] && [ -n "$CONN_FMT" ] && [ -n "$BANNER_FMT" ] && [ -n "$ROWS_FMT" ] \
  && ok "four format strings present in the capture" || { bad "capture lost a format string"; echo "PASS=$PASS FAIL=$FAIL"; exit 1; }
AUTH403="Error: ${AUTH_FMT/\%d/403}"
AUTH401="Error: ${AUTH_FMT/\%d/401}"
CONN="${CONN_FMT/\%s:\%d/localhost:8190}"; CONN="Error: $CONN"
OKOUT="$(printf '%s\n[{"n":"3"}]\n%s' "${BANNER_FMT/\%s/Fixture.mpr}" "${ROWS_FMT/\%d/1}")"
export AUTH403 AUTH401 CONN OKOUT

MARK="fixture-admin-marker-5d2"   # stands in for a real admin password; must never be printed

# ── pure functions, required in-process ────────────────────────────────────────────────────
IFS= read -r -d '' JS <<'JSEOF' || true
const R = require('./journey-runner.js');
const C = require('./config.js');
const out = (k, v) => console.log(`${k} ${typeof v === 'string' ? v : JSON.stringify(v)}`);
if (typeof R.preflight !== 'function' || typeof R.orderJourneys !== 'function') { console.log('NOFN'); process.exit(0); }
const E = process.env;

// classify
out('C403', R.classifyAdminProbe(E.AUTH403, 1));
out('C401', R.classifyAdminProbe(E.AUTH401, 1));
out('CCONN', R.classifyAdminProbe(E.CONN, 1));
out('COK', R.classifyAdminProbe(E.OKOUT, 0));
out('CJUNK', R.classifyAdminProbe('panic: something else', 2).state);

const data = { id: 'JD', steps: [{ name: 's', data: { creates: 'M.E' } }] };
const ui = { id: 'JU', steps: [{ name: 's', ui: { ready: '.x' } }] };
const admin = { adminHost: 'localhost', adminPort: '8190', adminToken: E.MARK, adminSource: '.docker/.env',
                user: 'demo_user', passFromEnv: true };
let calls = 0;
const probe = (r) => () => { calls++; return r; };

// 403 aborts, names the source and the remedy, never the credential
let p = R.preflight([data, ui], { env: {}, probe: probe(R.classifyAdminProbe(E.AUTH403, 1)), admin });
out('A403', { abort: p.abort, lines: p.lines, rows: p.rows.length });
p = R.preflight([data], { env: { ALLOW_NO_DATA_RUNG: '1' }, probe: probe(R.classifyAdminProbe(E.AUTH403, 1)), admin });
out('A403OVR', { abort: p.abort, rows: p.rows.length });
p = R.preflight([data], { env: {}, probe: probe(R.classifyAdminProbe(E.CONN, 1)), admin });
out('ACONN', { abort: p.abort, lines: p.lines });
// a tool error that quotes the token back must be redacted
p = R.preflight([data], { env: {}, probe: probe({ state: 'tool', detail: `spawn failed for token ${E.MARK}` }), admin });
out('ATOOL', { abort: p.abort, lines: p.lines });

// #278: TEST_PASS unset → abort before any login and before the probe; override proceeds
calls = 0;
p = R.preflight([data, ui], { env: {}, probe: probe(R.classifyAdminProbe(E.OKOUT, 0)), admin: { ...admin, passFromEnv: false } });
out('CRED', { abort: p.abort, calls, lines: p.lines, rows: p.rows.length });
p = R.preflight([ui], { env: { ALLOW_CONFIG_CREDENTIALS: '1' }, probe: probe(R.classifyAdminProbe(E.OKOUT, 0)), admin: { ...admin, passFromEnv: false } });
out('CREDOVR', { abort: p.abort, rows: p.rows.length });
// #302 follow-up: only the TEMPLATE PLACEHOLDER is refused; a project-set password runs
calls = 0;
p = R.preflight([data], { env: {}, probe: probe(R.classifyAdminProbe(E.OKOUT, 0)), admin: { ...admin, passFromEnv: false, passSource: 'project.config.js' } });
out('CRED_PROJ', { abort: p.abort, calls, cred: p.lines.some(l => l.includes('credentials')) });
p = R.preflight([data], { env: {}, probe: probe(R.classifyAdminProbe(E.OKOUT, 0)), admin: { ...admin, passFromEnv: false, passSource: 'template placeholder' } });
out('CRED_TPL', { abort: p.abort, line: p.lines[0] || '' });
// passwordSource: env wins, a project-set password is the project's, the template value is the placeholder
const ps = typeof C.passwordSource === 'function' ? C.passwordSource : () => 'NOFN';
out('PS', [
  ps({ env: { TEST_PASS: 'x' }, creds: { pass: 'Demo2025!' } }),
  ps({ env: { APP_PASS: 'x' }, creds: { pass: 'Real-Proj-Pass' } }),
  ps({ env: {}, creds: { pass: 'Real-Proj-Pass' } }),
  ps({ env: {}, creds: { pass: 'Demo2025!' } }),
  ps({ env: {}, creds: { pass: 'anything', source: 'template default' } }),
]);
// the shipped template's DEFAULT_PASS is the placeholder this list names
out('TPL_LISTED', (C.TEMPLATE_PASSWORDS || []).includes(E.TPL_PASS));

// #279: resetsData tag printed; --protect-state refuses tagged journeys only
const rs = { id: 'J-reset', resetsData: true, steps: [] };
p = R.preflight([rs, ui], { env: {}, probe: probe(R.classifyAdminProbe(E.OKOUT, 0)), admin, protectState: false });
out('RS', { abort: p.abort, lines: p.lines, rows: p.rows.length, skip: p.skip.size });
p = R.preflight([rs, ui], { env: {}, probe: probe(R.classifyAdminProbe(E.OKOUT, 0)), admin, protectState: true });
out('RSP', { abort: p.abort, lines: p.lines, rows: p.rows.length, skip: [...p.skip.keys()] });

// #281: landing judge — outline anywhere, box-shadow only when focused
out('L_CLEAN', R.judgeLanding([]));
out('L_OUTLINE', R.judgeLanding([{ el: 'a.mx-navigationtree', outlineStyle: 'solid', outlineWidth: '2px', boxShadow: 'none', focused: true }]));
out('L_FOCUSSHADOW', R.judgeLanding([{ el: 'a.nav-link', outlineStyle: 'none', outlineWidth: '0px', boxShadow: 'rgb(0, 95, 204) 0px 0px 0px 2px', focused: true }]));
out('L_CARD', R.judgeLanding([{ el: 'div.card', outlineStyle: 'none', outlineWidth: '0px', boxShadow: 'rgba(0, 0, 0, 0.1) 0px 1px 3px 0px', focused: false }]));
out('L_ZERO', R.judgeLanding([{ el: 'a', outlineStyle: 'auto', outlineWidth: '0px', boxShadow: 'none', focused: false }]));
out('L_ERR', R.judgeLanding({ error: 'Target closed' }));

// UI-only suite: no probe at all
calls = 0;
p = R.preflight([ui], { env: {}, probe: probe(R.classifyAdminProbe(E.AUTH403, 1)), admin });
out('AUI', { abort: p.abort, calls, lines: p.lines.length });

// sessions
p = R.preflight([data], { env: { JOURNEY_SESSION_CAP: '3' }, probe: probe(R.classifyAdminProbe(E.OKOUT, 0)), admin });
out('SCAP', { abort: p.abort, lines: p.lines });
p = R.preflight([data], { env: { JOURNEY_SESSION_CAP: '3', ALLOW_SESSION_CAP: '1' }, probe: probe(R.classifyAdminProbe(E.OKOUT, 0)), admin });
out('SCAPOVR', { abort: p.abort });
p = R.preflight([data], { env: {}, probe: probe(R.classifyAdminProbe(E.OKOUT, 0)), admin });
out('SOK', { abort: p.abort, lines: p.lines });

// env: one line however many journeys share the gap; unaffected journeys still run
const e1 = { id: 'J1', requiresEnv: ['MOCK_KEY'], steps: [] };
const e2 = { id: 'J2', requiresEnv: ['MOCK_KEY', 'MOCK_SECRET'], steps: [] };
const e3 = { id: 'J3', requiresEnv: ['MOCK_KEY'], steps: [] };
p = R.preflight([e1, e2, e3, ui], { env: { MOCK_KEY: '' }, probe: probe(R.classifyAdminProbe(E.OKOUT, 0)), admin });
out('ENV', { abort: p.abort, lines: p.lines, rows: p.rows.length, skip: [...p.skip.keys()] });
p = R.preflight([e1, e2, e3, ui], { env: { MOCK_KEY: 'x', MOCK_SECRET: 'y' }, probe: probe(R.classifyAdminProbe(E.OKOUT, 0)), admin });
out('ENVSET', { abort: p.abort, rows: p.rows.length, skip: p.skip.size });

// ordering — the field shape: J-advance moves the record on (consumes at-stage-1), J-review
// needs it there; file order put advance first. J-seed leaves it.
const adv = { id: 'J-advance', requires: ['at-stage-1'], consumes: ['at-stage-1'], leaves: ['at-stage-2'] };
const rev = { id: 'J-review', requires: ['at-stage-1'] };
const seed = { id: 'J-seed', leaves: ['at-stage-1'] };
const close = { id: 'J-close', requires: ['at-stage-2'] };
const plain = { id: 'J-plain' };
let o = R.orderJourneys([close, adv, rev, plain, seed]);
out('ORD', { order: o.order.map(j => j.id), cycle: o.cycle });

// tracker: a producer that FAILs leaves nothing; its dependants are named, not walked
let t = R.stateTracker([seed, rev, adv, close]);
out('G0', t.gate(seed));
t.settle(seed, [{ verdict: 'PASS' }, { verdict: 'FAIL' }], true);
out('GFAIL', t.gate(rev));
t = R.stateTracker([seed, rev, adv, close]);
t.settle(seed, [{ verdict: 'PASS' }], true);
out('GOK', t.gate(rev));
t.settle(rev, [{ verdict: 'PASS' }], true);
t.settle(adv, [{ verdict: 'PASS' }], true);
out('GADV', t.gate(close));
const rev2 = { id: 'J-review-2', requires: ['at-stage-1'] };
out('GCONS', t.gate(rev2));
t = R.stateTracker([seed, rev]);
t.settle(seed, [], false);
out('GSKIP', t.gate(rev));
// a token no journey here leaves is the fixture's job: trusted, reported once
t = R.stateTracker([rev]);
out('GASSUME', { gate: t.gate(rev), assumed: t.assumed() });

// back-compat: journeys with no headers — same order, same objects, no gate, no probe
const ex = require('./example.journey.json');
const a = { id: 'A', steps: [] }, b = { id: 'B', steps: [] }, c = { id: 'C', steps: [] };
o = R.orderJourneys([c, a, ex, b]);
out('BC_ORDER', { same: o.order[0] === c && o.order[1] === a && o.order[2] === ex && o.order[3] === b, cycle: o.cycle });
t = R.stateTracker([c, a, ex, b]);
out('BC_GATE', [c, a, ex, b].map(j => t.gate(j)));
out('BC_ASSUMED', t.assumed());
calls = 0;
p = R.preflight([a, b, c], { env: {}, probe: probe(R.classifyAdminProbe(E.AUTH403, 1)), admin });
out('BC_PRE', { abort: p.abort, lines: p.lines.length, rows: p.rows.length, calls });
out('BC_NEEDS', R.journeyNeedsAdmin(ex));

// credential resolution: source named, value never in it
const root = E.CRED_ROOT;
const mpr = require('path').join(root, 'Fixture.mpr');
const s = (r) => ({ port: r.port, source: r.source, tokenIsMark: r.token === E.MARK, leaks: r.source.includes(E.MARK) });
out('R_ENV', s(C.resolveAdmin({ env: { M2EE_ADMIN_PASS: E.MARK }, root, mprPath: mpr, appPort: '8180' })));
out('R_ENVPORT', C.resolveAdmin({ env: { M2EE_ADMIN_PASS: E.MARK, M2EE_ADMIN_PORT: '9999' }, root, mprPath: mpr, appPort: '8180' }).port);
out('R_RUNLOCAL', s(C.resolveAdmin({ env: {}, root, mprPath: mpr, appPort: '8180' })));
out('R_OTHERPORT', s(C.resolveAdmin({ env: {}, root, mprPath: mpr, appPort: '8080' })));
const bare = E.BARE_ROOT;
out('R_GUESS', s(C.resolveAdmin({ env: {}, root: bare, mprPath: require('path').join(bare, 'Fixture.mpr'), appPort: '8080' })));
JSEOF

# The credential layouts: one project with both a run-local handshake (appPort 8180) and a
# .docker/.env whose password is the marker; one bare project.
CRED="$WORK/cred"; BARE="$WORK/bare"; mkdir -p "$CRED/.mxcli" "$CRED/.docker" "$BARE"
: > "$CRED/Fixture.mpr"; : > "$BARE/Fixture.mpr"
sed -e "s/^  \"adminPass\": \"[^\"]*\"/  \"adminPass\": \"$MARK\"/" "$RLJ" > "$CRED/.mxcli/run-local.json"
sed -e "s/^M2EE_ADMIN_PASS=.*/M2EE_ADMIN_PASS=$MARK/" "$DENV" > "$CRED/.docker/.env"
cp "$(dirname "$SUT")/example.journey.json" "$WORK/tests/e2e/" 2>/dev/null \
  || cp "$HERE/../../project-tests/e2e/example.journey.json" "$WORK/tests/e2e/"

TPL_PASS="$(sed -n "s/^const DEFAULT_PASS = '\(.*\)';.*/\1/p" "$CFG" | head -1)"
OUT="$(cd "$WORK/tests/e2e" && printf '%s' "$JS" | env -u M2EE_ADMIN_PASS -u M2EE_ADMIN_PORT \
       APP_PORT=1 MARK="$MARK" TPL_PASS="$TPL_PASS" CRED_ROOT="$CRED" BARE_ROOT="$BARE" node - 2>&1)"
line() { printf '%s\n' "$OUT" | sed -n "s/^$1 //p"; }
if printf '%s\n' "$OUT" | grep -qx NOFN; then
  bad "journey-runner.js exports no preflight/orderJourneys — #286 not addressed"
  echo ""; echo "PASS=$PASS FAIL=$FAIL"; exit 1
fi
[ -n "$(line C403)" ] || { echo "FAIL — harness could not require $SUT"; echo "$OUT" | tail -8; exit 1; }

echo "== T1: mxcli's messages classify =="
[ "$(line C403)" = '{"state":"auth","http":403}' ] && ok "HTTP 403 → auth" || bad "403 misclassified" "$(line C403)"
[ "$(line C401)" = '{"state":"auth","http":401}' ] && ok "HTTP 401 → auth" || bad "401 misclassified" "$(line C401)"
[ "$(line CCONN)" = '{"state":"unreachable"}' ] && ok "cannot connect → unreachable" || bad "unreachable misclassified" "$(line CCONN)"
[ "$(line COK)" = '{"state":"ok","sessions":3}' ] && ok "banner + JSON + row count → ok, 3 sessions" || bad "success misread" "$(line COK)"
[ "$(line CJUNK)" = unknown ] && ok "anything else → unknown (not guessed)" || bad "junk classified" "$(line CJUNK)"

echo "== T2: 401/403 aborts the suite, one SETUP line, credential never printed =="
case "$(line A403)" in
  *'"abort":2'*'SETUP  admin: admin API at localhost:8190 refused the credential (HTTP 403); credential from .docker/.env'*M2EE_ADMIN_PASS*ABORTED*'"rows":1'*)
    ok "403 → abort 2, names host:port, the source and M2EE_ADMIN_PASS, one row" ;;
  *) bad "403 did not abort with a named source" "$(line A403)" ;;
esac
[ "$(line A403OVR)" = '{"abort":null,"rows":1}' ] && ok "ALLOW_NO_DATA_RUNG=1 proceeds, still records the SETUP row" || bad "override wrong" "$(line A403OVR)"
case "$(line ACONN)" in *'"abort":2'*'unreachable at localhost:8190'*) ok "unreachable admin API aborts too" ;; *) bad "unreachable did not abort" "$(line ACONN)" ;; esac
case "$(line ATOOL)" in *'<redacted>'*) ok "probe text quoting the token is redacted" ;; *) bad "token not redacted" "$(line ATOOL)" ;; esac
[ "$(line AUI)" = '{"abort":null,"calls":0,"lines":0}' ] && ok "UI-only suite never probes the admin API" || bad "UI-only suite probed/refused" "$(line AUI)"

echo "== T2b: unset TEST_PASS refuses before any login (#278) =="
case "$(line CRED)" in *'"abort":2,"calls":0'*'SETUP  credentials: TEST_PASS is unset'*demo_user*ALLOW_CONFIG_CREDENTIALS*'"rows":1'*) ok "aborts, names the user and the override, probe never called" ;; *) bad "unset TEST_PASS not refused" "$(line CRED)" ;; esac
[ "$(line CREDOVR)" = '{"abort":null,"rows":0}' ] && ok "ALLOW_CONFIG_CREDENTIALS=1 proceeds" || bad "override ignored" "$(line CREDOVR)"

echo "== T2b': only the template placeholder is refused (#302 follow-up) =="
[ "$(line CRED_PROJ)" = '{"abort":null,"calls":1,"cred":false}' ] && ok "password set in project.config.js → no refusal, probe runs" || bad "project-set password refused (breaks every project after sync)" "$(line CRED_PROJ)"
case "$(line CRED_TPL)" in *'"abort":2'*'placeholder password'*DEFAULT_PASS*) ok "template placeholder → refused, names DEFAULT_PASS as the fix" ;; *) bad "placeholder not refused" "$(line CRED_TPL)" ;; esac
[ "$(line PS)" = '["env","env","project.config.js","template placeholder","template placeholder"]' ] && ok "passwordSource: env wins; project value is the project's; template value / 'template default' is the placeholder" || bad "passwordSource wrong" "$(line PS)"
[ -n "$TPL_PASS" ] && [ "$(line TPL_LISTED)" = true ] && ok "the shipped template's DEFAULT_PASS is the listed placeholder" || bad "template DEFAULT_PASS not in TEMPLATE_PASSWORDS (got '$TPL_PASS')" "$(line TPL_LISTED)"

echo "== T2c: resetsData / --protect-state (#279) =="
case "$(line RS)" in *'"abort":null'*'SETUP  resetsData: J-reset reset or reload demo data'*'"rows":0,"skip":0'*) ok "tag printed at start, journey still runs without the flag" ;; *) bad "tag not printed / journey refused" "$(line RS)" ;; esac
case "$(line RSP)" in *'"abort":null'*'SETUP  protect-state: refused J-reset'*'"rows":1,"skip":["J-reset"]'*) ok "--protect-state refuses only the tagged journey, one row" ;; *) bad "--protect-state wrong" "$(line RSP)" ;; esac

echo "== T2d: landing judge — outlines and focus box-shadows (#281) =="
case "$(line L_CLEAN)" in *'"verdict":"PASS"'*) ok "nothing drawn → PASS" ;; *) bad "clean landing not PASS" "$(line L_CLEAN)" ;; esac
case "$(line L_OUTLINE)" in *'"verdict":"FAIL"'*'a.mx-navigationtree outline 2px solid'*) ok "an outline on the focused nav item → FAIL, named" ;; *) bad "outline missed (the #281 false green)" "$(line L_OUTLINE)" ;; esac
case "$(line L_FOCUSSHADOW)" in *'"verdict":"FAIL"'*'focus box-shadow'*) ok "non-inset focus box-shadow → FAIL" ;; *) bad "focus shadow missed" "$(line L_FOCUSSHADOW)" ;; esac
case "$(line L_CARD)" in *'"verdict":"PASS"'*) ok "a card's resting shadow is not a ring" ;; *) bad "resting shadow counted" "$(line L_CARD)" ;; esac
case "$(line L_ZERO)" in *'"verdict":"PASS"'*) ok "zero-width outline is not a ring" ;; *) bad "zero-width outline counted" "$(line L_ZERO)" ;; esac
case "$(line L_ERR)" in *'"verdict":"INVALID"'*'Target closed'*) ok "unread landing → INVALID, never PASS" ;; *) bad "unread landing not INVALID" "$(line L_ERR)" ;; esac

echo "== T3: session cap (#287) =="
case "$(line SCAP)" in *'"abort":2'*'3 live session(s), cap 3'*ALLOW_SESSION_CAP*) ok "live count at JOURNEY_SESSION_CAP refuses the run, names the override" ;; *) bad "cap not enforced" "$(line SCAP)" ;; esac
[ "$(line SCAPOVR)" = '{"abort":null}' ] && ok "ALLOW_SESSION_CAP=1 overrides" || bad "cap override ignored" "$(line SCAPOVR)"
case "$(line SOK)" in *'"abort":null'*'SETUP  sessions: 3 live'*JOURNEY_SESSION_CAP*) ok "no cap set: count reported with the warning" ;; *) bad "session count not reported" "$(line SOK)" ;; esac

echo "== T4: missing env vars are ONE setup line =="
case "$(line ENV)" in
  *'"abort":null'*'SETUP  env: missing MOCK_KEY (needed by J1, J2, J3); MOCK_SECRET (needed by J2)'*'3 journey(s) not walked'*'"rows":1'*'"skip":["J1","J2","J3"]'*)
    ok "two vars, three journeys → one line, one row, the UI journey still runs" ;;
  *) bad "env gap not collapsed to one line" "$(line ENV)" ;;
esac
[ "$(line ENVSET)" = '{"abort":null,"rows":0,"skip":0}' ] && ok "vars set → no SETUP row, nothing skipped" || bad "set vars still flagged" "$(line ENVSET)"

echo "== T5: requires / leaves / consumes order the suite =="
ORD="$(line ORD)"
node -e '
const o = JSON.parse(process.argv[1]).order, i = id => o.indexOf(id);
process.exit(i("J-seed") < i("J-review") && i("J-seed") < i("J-advance") && i("J-review") < i("J-advance")
  && i("J-advance") < i("J-close") && o.length === 5 ? 0 : 1);' "$ORD" \
  && ok "seed → review → advance → close (review before the journey that moves the record on)" \
  || bad "order violates declared state" "$ORD"
case "$ORD" in *'"cycle":null'*) ok "no false cycle on a self requires+consumes" ;; *) bad "self-edge read as cycle" "$ORD" ;; esac

echo "== T6: unmet precondition is named, with the journey that should have left it =="
[ "$(line G0)" = null ] && ok "a journey with no requires is never gated" || bad "producer gated" "$(line G0)"
case "$(line GFAIL)" in *'precondition not met: at-stage-1 (left by journey J-seed, which did not complete: 1 FAIL / 0 INVALID)'*'not a feature failure'*) ok "producer FAILed → dependant named, cause named" ;; *) bad "failed producer not named" "$(line GFAIL)" ;; esac
[ "$(line GOK)" = null ] && ok "clean producer → dependant runs" || bad "clean producer still gated" "$(line GOK)"
[ "$(line GADV)" = null ] && ok "leaves of a clean journey hold (at-stage-2)" || bad "leaves not recorded" "$(line GADV)"
case "$(line GCONS)" in *'at-stage-1 (consumed by journey J-advance)'*) ok "consumed state names the consumer" ;; *) bad "consumption not tracked" "$(line GCONS)" ;; esac
case "$(line GSKIP)" in *'left by journey J-seed, which was not walked'*) ok "producer not walked → said so" ;; *) bad "skipped producer not named" "$(line GSKIP)" ;; esac
[ "$(line GASSUME)" = '{"gate":null,"assumed":["at-stage-1"]}' ] && ok "token no journey leaves is trusted to the fixture and listed" || bad "assumed token mishandled" "$(line GASSUME)"

echo "== T7: back-compat — journeys without headers run exactly as before =="
[ "$(line BC_ORDER)" = '{"same":true,"cycle":null}' ] && ok "file order kept, same objects" || bad "header-less suite reordered" "$(line BC_ORDER)"
[ "$(line BC_GATE)" = '[null,null,null,null]' ] && ok "never gated" || bad "header-less journey gated" "$(line BC_GATE)"
[ "$(line BC_ASSUMED)" = '[]' ] && ok "nothing assumed" || bad "phantom tokens" "$(line BC_ASSUMED)"
[ "$(line BC_PRE)" = '{"abort":null,"lines":0,"rows":0,"calls":0}' ] && ok "no env, no data → preflight silent, no probe" || bad "preflight not silent" "$(line BC_PRE)"
[ "$(line BC_NEEDS)" = true ] && ok "the shipped example.journey.json needs the admin API (has a data rung)" || bad "example misread" "$(line BC_NEEDS)"

echo "== T8: credential source is named, the value never =="
[ "$(line R_ENV)" = '{"port":"8190","source":"M2EE_ADMIN_PASS env","tokenIsMark":true,"leaks":false}' ] \
  && ok "env wins over run-local.json and .docker/.env" || bad "env not first" "$(line R_ENV)"
[ "$(line R_ENVPORT)" = 9999 ] && ok "M2EE_ADMIN_PORT overrides the port" || bad "port override ignored" "$(line R_ENVPORT)"
case "$(line R_RUNLOCAL)" in '{"port":"8190","source":".mxcli/run-local.json (the run --local handshake for :8180)","tokenIsMark":true,"leaks":false}') ok "run --local handshake for the port under test: its adminPass + adminPort" ;; *) bad "run-local.json not read" "$(line R_RUNLOCAL)" ;; esac
[ "$(line R_OTHERPORT)" = '{"port":"8090","source":".docker/.env","tokenIsMark":true,"leaks":false}' ] \
  && ok "handshake for another port ignored → .docker/.env (ADMIN_PORT 8090)" || bad ".docker/.env not read" "$(line R_OTHERPORT)"
case "$(line R_GUESS)" in *'"port":"8090","source":"built-in guess'*'no credential configured"'*) ok "nothing configured → the guess is labelled as one" ;; *) bad "guess unlabelled" "$(line R_GUESS)" ;; esac

# ── end to end through the real runner, stub mxcli, no browser ─────────────────────────────
echo "== T9: real runner — 403 aborts before the first journey =="
mkdir -p "$WORK/stub"
cat > "$WORK/stub/mxcli" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$STUB_ARGV"
printf '%s\n' "$AUTH403" >&2
exit 1
EOF
chmod +x "$WORK/stub/mxcli"
J="$WORK/journeys"; mkdir -p "$J"
for id in J-one J-two; do
  printf '{"id":"%s","steps":[{"name":"save","data":{"creates":"M.E"}}]}\n' "$id" > "$J/$id.journey.json"
done
E2EOUT="$(cd "$WORK/tests/e2e" && env -u M2EE_ADMIN_PORT APP_PORT=1 TEST_PASS=fixture-pass M2EE_ADMIN_PASS="$MARK" MXCLI="$WORK/stub/mxcli" \
          STUB_ARGV="$WORK/argv" node journey-runner.js "$J/J-one.journey.json" "$J/J-two.journey.json" 2>&1)"; RC=$?
[ "$RC" -eq 2 ] && ok "exit 2 (instrument fault), not 1 (finding)" || bad "rc=$RC" "$(printf '%s' "$E2EOUT" | tail -6)"
[ "$(printf '%s\n' "$E2EOUT" | grep -c '^  SETUP  admin: admin API at localhost:11 refused the credential (HTTP 403); credential from M2EE_ADMIN_PASS env')" -eq 1 ] \
  && ok "one SETUP line naming the endpoint and the credential's source" || bad "SETUP line missing" "$E2EOUT"
printf '%s\n' "$E2EOUT" | grep -q '=== JOURNEY' && bad "a journey was walked after the 403" "$E2EOUT" || ok "no journey walked"
printf '%s\n' "$E2EOUT" | grep -q 'ABORTED at preflight — 0 of 2 journeys walked' && ok "summary says aborted, with the denominator" || bad "no abort summary" "$E2EOUT"
printf '%s\n' "$E2EOUT" | grep -qF "$MARK" && bad "the credential was printed" || ok "credential not in the output"
grep -qF -- "--token $MARK" "$WORK/argv" 2>/dev/null && ok "the probe used the env credential" || bad "probe did not use the env credential" "$(cat "$WORK/argv" 2>/dev/null)"
[ "$(wc -l < "$WORK/argv" | tr -d ' ')" = 1 ] && ok "exactly one probe call (no retry loop)" || bad "probe called $(wc -l < "$WORK/argv") times"
FJ="$WORK/tests/e2e/artifacts/journey-findings.json"
node -e 'const f=require(process.argv[1]); process.exit(f.aborted==="preflight" && f.results.length===1 && f.results[0].verdict==="INVALID" ? 0 : 1)' "$FJ" 2>/dev/null \
  && ok "findings slot overwritten with the aborted run (no stale file reads as this run)" || bad "findings file not written as aborted"
grep -qF "$MARK" "$FJ" 2>/dev/null && bad "credential written to the findings file" || ok "credential not in the findings file"

echo "== T10: real runner — missing env var, every journey affected → one SETUP line, no probe =="
rm -f "$WORK/argv"
for id in J-mock-a J-mock-b J-mock-c; do
  printf '{"id":"%s","requiresEnv":["MOCK_API_KEY","MOCK_API_SECRET"],"steps":[{"name":"s","data":{"creates":"M.E"}}]}\n' "$id" > "$J/$id.journey.json"
done
E2EOUT="$(cd "$WORK/tests/e2e" && env -u MOCK_API_KEY -u MOCK_API_SECRET APP_PORT=1 TEST_PASS=fixture-pass MXCLI="$WORK/stub/mxcli" STUB_ARGV="$WORK/argv" \
          node journey-runner.js "$J/J-mock-a.journey.json" "$J/J-mock-b.journey.json" "$J/J-mock-c.journey.json" 2>&1)"; RC=$?
[ "$RC" -eq 2 ] && ok "exit 2 when nothing is runnable" || bad "rc=$RC" "$(printf '%s' "$E2EOUT" | tail -6)"
[ "$(printf '%s\n' "$E2EOUT" | grep -c 'SETUP  env:')" -eq 1 ] && ok "exactly one SETUP env line for 3 journeys × 2 vars" || bad "not one line" "$E2EOUT"
printf '%s\n' "$E2EOUT" | grep -q 'INVL' && bad "per-journey INVALID lines printed" "$E2EOUT" || ok "no per-journey INVALID lines"
[ -f "$WORK/argv" ] && bad "admin probe ran although no journey could run" || ok "no admin probe spent on an unrunnable suite"

echo "== T11: real runner — TEST_PASS unset → refused before any login or probe (#278) =="
rm -f "$WORK/argv"
E2EOUT="$(cd "$WORK/tests/e2e" && env -u TEST_PASS -u APP_PASS -u ALLOW_CONFIG_CREDENTIALS APP_PORT=1 MXCLI="$WORK/stub/mxcli" \
          STUB_ARGV="$WORK/argv" node journey-runner.js "$J/J-one.journey.json" 2>&1)"; RC=$?
[ "$RC" -eq 2 ] && ok "exit 2" || bad "rc=$RC" "$(printf '%s' "$E2EOUT" | tail -6)"
[ "$(printf '%s\n' "$E2EOUT" | grep -c 'SETUP  credentials: TEST_PASS is unset')" -eq 1 ] && ok "one SETUP credentials line" || bad "no SETUP credentials line" "$E2EOUT"
printf '%s\n' "$E2EOUT" | grep -qiE 'login as|FAULTED|launch' && bad "a login was attempted" "$E2EOUT" || ok "no login attempted (browser never opened)"
[ -f "$WORK/argv" ] && bad "admin probe ran" || ok "no admin probe either"

echo "== T11b: real runner — TEST_PASS unset but DEFAULT_PASS set by the project → not refused =="
rm -f "$WORK/argv"
PROJ_CFG="$WORK/tests/e2e/project.config.js"; cp "$PROJ_CFG" "$WORK/cfg.bak"
sed -e "s/^const DEFAULT_PASS = '.*';/const DEFAULT_PASS = 'fixture-project-pass';/" "$WORK/cfg.bak" > "$PROJ_CFG"
E2EOUT="$(cd "$WORK/tests/e2e" && env -u TEST_PASS -u APP_PASS -u ALLOW_CONFIG_CREDENTIALS -u M2EE_ADMIN_PORT APP_PORT=1 M2EE_ADMIN_PASS="$MARK" \
          MXCLI="$WORK/stub/mxcli" STUB_ARGV="$WORK/argv" node journey-runner.js "$J/J-one.journey.json" 2>&1)"; RC=$?
printf '%s\n' "$E2EOUT" | grep -q 'SETUP  credentials' && bad "project-set password refused" "$E2EOUT" || ok "no credentials refusal"
[ -f "$WORK/argv" ] && ok "went on to the admin probe (the stub answers 403 → exit $RC)" || bad "probe never ran" "$E2EOUT"
cp "$WORK/cfg.bak" "$PROJ_CFG"

echo "== T11c: real runner — SIGINT after preflight writes the findings slot as aborted =="
printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$OKOUT"\n' > "$WORK/stub/mxcli-ok"
chmod +x "$WORK/stub/mxcli-ok"
# Hold the run where a real one waits on the browser: launchBrowser never resolves, and a timer
# keeps the event loop alive the way a live browser process does.
printf "const H = require('./helpers.js'); H.launchBrowser = () => new Promise(() => { setInterval(() => {}, 1 << 30); });\n" > "$WORK/tests/e2e/hold-browser.js"
FJ2="$WORK/tests/e2e/artifacts/journey-findings.json"
mkdir -p "$WORK/tests/e2e/artifacts"
printf '{"capturedAt":"STALE-PREVIOUS-RUN","results":[]}' > "$FJ2"
LOG="$WORK/sigint.log"
( cd "$WORK/tests/e2e" && exec env -u M2EE_ADMIN_PORT APP_PORT=1 TEST_PASS=fixture-pass M2EE_ADMIN_PASS="$MARK" MXCLI="$WORK/stub/mxcli-ok" \
    node -r ./hold-browser.js journey-runner.js "$J/J-one.journey.json" > "$LOG" 2>&1 ) &
PID=$!
for _ in $(seq 1 100); do grep -q 'SETUP  admin: OK' "$LOG" 2>/dev/null && break; sleep 0.1; done
sleep 0.5; kill -INT "$PID" 2>/dev/null; wait "$PID"; RC=$?
[ "$RC" -eq 2 ] && ok "SIGINT → exit 2" || bad "rc=$RC" "$(tail -5 "$LOG")"
node -e 'const f=require(process.argv[1]); process.exit(f.aborted==="signal SIGINT" && f.capturedAt!=="STALE-PREVIOUS-RUN" ? 0 : 1)' "$FJ2" 2>/dev/null \
  && ok "findings slot overwritten as aborted by SIGINT (no stale previous run left)" || bad "previous run's findings left in the slot" "$(head -c 200 "$FJ2")"
grep -q 'ABORTED by SIGINT' "$LOG" && ok "says ABORTED by SIGINT" || bad "no abort line" "$(tail -5 "$LOG")"

echo "== T12: real runner — --protect-state with every journey tagged → refused, no login =="
rm -f "$WORK/argv"
printf '{"id":"J-demo-reset","resetsData":true,"steps":[{"name":"s","data":{"creates":"M.E"}}]}\n' > "$J/J-demo-reset.journey.json"
E2EOUT="$(cd "$WORK/tests/e2e" && APP_PORT=1 TEST_PASS=fixture-pass MXCLI="$WORK/stub/mxcli" STUB_ARGV="$WORK/argv" \
          node journey-runner.js "$J/J-demo-reset.journey.json" --protect-state 2>&1)"; RC=$?
[ "$RC" -eq 2 ] && ok "exit 2, nothing walked" || bad "rc=$RC" "$(printf '%s' "$E2EOUT" | tail -6)"
printf '%s\n' "$E2EOUT" | grep -q 'SETUP  protect-state: refused J-demo-reset' && ok "refusal named" || bad "no refusal line" "$E2EOUT"
printf '%s\n' "$E2EOUT" | grep -q '=== JOURNEY' && bad "tagged journey walked" || ok "tagged journey not walked"

echo ""
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
