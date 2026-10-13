#!/usr/bin/env bash
# Usage: bash test-journey-liveness.sh [path-to-journey-runner.js]
#
# Fixture for the journey runner's liveness checks: rung 2's negative-only span claim
# (traceRung + otel.js liveness, the trace-negative positive-control mutant — #150) and the
# app probe between journeys (probeApp / appGate / flagAppDown — #285), and the loud INVALID
# for a spans block that declares neither `ordered` nor `mustNotFire` (#150 item 3).
#
# #150 (card-disbursement requirements-driven build, 2026-09-26): a step whose whole proof is
# "the reset microflow did NOT run" (Cancel on a confirmation) captures zero spans. The runner
# read every empty capture as INVALID "Jaeger down or OTel off", so the claim could never pass,
# and the control run's trace-negative mutant needed an `ordered` list, so the claim could
# never be shown able to fail either. Now: zero spans + evidence tracing is live → the claim is
# judged; no evidence → INVALID; the mutant injects the forbidden name after the liveness check.
# #285 (field run 2026-10-12): a watch rebuild took the runtime down mid-suite and every later
# journey FAILed as if the features were broken.
#
# Golden input: fixtures/otel-capture/jaeger-trace-refused-arm.json — a real Jaeger
# /api/traces response (Mendix 11.13.0 → Jaeger v1.76, see test-otel-capture-until.sh), fed
# through the real otel.js capture()/liveness() with fetch stubbed. The app probe runs against
# a real local HTTP server and a closed port; a Mendix runtime that is down refuses the
# connection, which is the closed-port case. Not fixtured: the main loop's wiring (needs a
# browser and a live app).

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
GOLDEN="$HERE/fixtures/otel-capture/jaeger-trace-refused-arm.json"
[ -f "$GOLDEN" ] || { echo "FAIL — golden capture missing: $GOLDEN"; exit 1; }
E2E="$(cd "$(dirname "$SUT")" && pwd)"
for f in helpers.js otel.js config.js settle.js; do
  [ -f "$E2E/$f" ] || { echo "FAIL — $f not beside $SUT"; exit 1; }
done
CFG="$E2E/project.config.template.js"
[ -f "$CFG" ] || CFG="$HERE/../../project-tests/e2e/project.config.template.js"

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  ok   — $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL — $1"; [ -n "${2:-}" ] && printf '%s\n' "$2" | sed 's/^/         got: /'; }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/journey-liveness.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/tests/e2e"; : > "$WORK/Fixture.mpr"
cp "$SUT" "$E2E/helpers.js" "$E2E/settle.js" "$E2E/otel.js" "$E2E/config.js" "$WORK/tests/e2e/"
cp "$CFG" "$WORK/tests/e2e/project.config.js"

IFS= read -r -d '' JS <<'JSEOF' || true
const fs = require('fs');
const http = require('http');
const E = process.env;
const full = JSON.parse(fs.readFileSync(E.GOLDEN, 'utf8'));
const empty = { data: [] };
let body = full, fail = false;
const realFetch = globalThis.fetch.bind(globalThis);
global.fetch = async (url, opts) => {
  if (String(url).includes('/api/traces')) {
    if (fail) { const e = new Error('fetch failed'); e.code = 'ECONNREFUSED'; throw e; }
    return { json: async () => body };
  }
  return realFetch(url, opts);
};
const R = require('./journey-runner.js');
const O = require('./otel.js');
const out = (k, v) => console.log(`${k} ${typeof v === 'string' ? v : JSON.stringify(v)}`);
if (typeof R.traceRung !== 'function' || typeof O.liveness !== 'function') { console.log('NOFN'); process.exit(0); }

(async () => {
  // capture() over the golden, the way the runner calls it (fast retries)
  const cap = async () => O.capture(0, { retries: 1, waitMs: 1 });
  const isMf = s => s.tags.some(t => t.key === 'mx.microflow.name');
  const goldSpans = await cap();
  const noMf = goldSpans.filter(s => !s.tags['mx.microflow.name']);

  // liveness() itself
  body = full;  out('L_LIVE', await O.liveness(0));
  body = empty; out('L_QUIET', (await O.liveness(0)).ok);
  fail = true;  out('L_DOWN', await O.liveness(0)); fail = false;
  body = full;  out('L_LATER', (await O.liveness(Date.now())).ok);   // spans older than `since`
  out('L_NAMED', (await O.liveness(0, { name: 'POST /*', spans: noMf })).ok);
  out('L_NAMEDMISS', (await O.liveness(0, { name: 'Microflow X.DS_Page', spans: noMf })).ok);

  // traceRung, driven with the golden capture
  const run = async (step, spans, liveOk) => {
    const rows = [];
    await R.traceRung(step, { t0: 0, since: 0, rec: (n, v, d) => rows.push(`${v} ${n}${d ? ' :: ' + d : ''}`),
      capture: async () => spans,
      live: liveOk === undefined ? O.liveness : async (s, o) => (liveOk ? { ok: true, detail: 'live (stub)' } : { ok: false, detail: 'dead (stub)' }) });
    return rows;
  };
  const neg = { name: 'Cancel reset', spans: { ordered: [], mustNotFire: ['ACT_Settings_ResetAll'] } };
  body = full;
  out('T_NEG_EMPTY_LIVE', await run(neg, [], undefined));            // golden says tracing is live
  body = empty;
  out('T_NEG_EMPTY_DEAD', await run(neg, [], undefined));            // Jaeger answers, nothing since
  fail = true; out('T_NEG_EMPTY_DOWN', await run(neg, [], undefined)); fail = false;
  out('T_NEG_SPANS_CLEAN', await run(neg, noMf, false));             // spans present: they are the evidence
  const negHit = { name: 'Cancel arm', spans: { mustNotFire: ['ACT_MockScenario_Arm'] } };
  out('T_NEG_HIT', await run(negHit, goldSpans, false));
  const negDecl = { name: 'Cancel', spans: { mustNotFire: ['ACT_Settings_ResetAll'], liveness: 'POST /*' } };
  out('T_DECL_OK', await run(negDecl, noMf, undefined));
  const negDeclMiss = { name: 'Cancel', spans: { mustNotFire: ['ACT_Settings_ResetAll'], liveness: 'Microflow X.DS_Page' } };
  out('T_DECL_MISS', await run(negDeclMiss, noMf, undefined));
  const pos = { name: 'Arm', spans: { ordered: ['MockServices.ACT_MockScenario_Arm'] } };
  out('T_POS_EMPTY', await run(pos, [], true));                      // positive claim: empty is INVALID, liveness not consulted
  // #150 item 3: a spans block declaring nothing is a loud INVALID, never a silent skip
  out('T_NOTHING', await run({ name: 'Save', spans: { ordered: [] } }, goldSpans, true));
  out('T_LEGACY', await run({ name: 'Save', spans: [{ mf: 'M.ACT_Save', status: 'OK' }] }, goldSpans, true));
  out('T_NOSPANS', await run({ name: 'Save' }, goldSpans, true));
  out('T_POS_OK', (await run(pos, goldSpans, false)).map(r => r.split(' :: ')[0]));

  // the trace-negative mutant for a negative-only journey
  const jNeg = { id: 'J-neg', steps: [{ name: 'Cancel reset', ui: { ready: '.x' }, spans: { mustNotFire: ['ACT_Settings_ResetAll'] } }] };
  const mNeg = R.controlMutants(jNeg).find(m => m.rung === 'trace-negative');
  out('M_SUPPORTED', { supported: mNeg.supported, inject: mNeg.supported && mNeg.journey.steps[0].spans._controlInjectFired });
  const mRows = await run(mNeg.journey.steps[0], [], true);
  out('M_LIVE', { rows: mRows, caught: mRows.some(r => r.startsWith('FAIL') && mNeg.expectFail({ name: r.split(' :: ')[0].slice(5) })) });
  out('M_DEAD', await run(mNeg.journey.steps[0], [], false));
  const jPos = { id: 'J-pos', steps: [{ name: 'Arm', spans: { ordered: ['MockServices.ACT_MockScenario_Arm'] } }] };
  const mPos = R.controlMutants(jPos).find(m => m.rung === 'trace-negative');
  out('M_POS', { supported: mPos.supported, mustNot: mPos.journey.steps[0].spans.mustNotFire, inject: mPos.journey.steps[0].spans._controlInjectFired || null });
  out('M_NONE', R.controlMutants({ id: 'J', steps: [{ name: 's' }] }).find(m => m.rung === 'trace-negative').supported);
  out('F_SAMPLE', [R.forbiddenSample('Mod.ACT_X'), R.forbiddenSample('^Mod\\.ACT_X$'), R.forbiddenSample('(')]);

  // #285: app probe against a real server and a closed port
  let status = 200;
  const srv = http.createServer((q, s) => { s.statusCode = status; s.end('x'); });
  await new Promise(r => srv.listen(0, '127.0.0.1', r));
  const url = `http://127.0.0.1:${srv.address().port}/`;
  out('A_UP', await R.probeApp(url));
  status = 302; out('A_REDIRECT', (await R.probeApp(url)).up);
  status = 503; out('A_503', await R.probeApp(url));
  srv.closeAllConnections && srv.closeAllConnections();
  await new Promise(r => srv.close(r));
  // a port nothing listens on: bind one, release it, probe it (no pooled socket to reuse)
  const gone = http.createServer();
  await new Promise(r => gone.listen(0, '127.0.0.1', r));
  const goneUrl = `http://127.0.0.1:${gone.address().port}/`;
  await new Promise(r => gone.close(r));
  out('A_REFUSED', await R.probeApp(goneUrl, { timeoutMs: 2000 }));
  const seq = (...ups) => { let i = 0; return async () => ({ up: ups[i++], detail: 'stub' }); };
  out('G_RECOVER', await R.appGate(url, { probe: seq(false, false, true), waitMs: 0 }));
  out('G_DOWN', await R.appGate(url, { probe: seq(false, false, false), waitMs: 0 }));
  const rows = [{ verdict: 'PASS', detail: '' }, { verdict: 'FAIL', detail: 'x' }, { verdict: 'INVALID', detail: '' }];
  out('G_FLAG', { n: R.flagAppDown(rows, 'ECONNREFUSED'), rows });
})().catch(e => { console.log(`ERR ${e.stack}`); process.exit(3); });
JSEOF

OUT="$(cd "$WORK/tests/e2e" && printf '%s' "$JS" | APP_PORT=1 GOLDEN="$GOLDEN" JAEGER_URL=http://jaeger.invalid node - 2>&1)"
line() { printf '%s\n' "$OUT" | sed -n "s/^$1 //p"; }
if printf '%s\n' "$OUT" | grep -qx NOFN; then
  bad "journey-runner.js exports no traceRung / otel.js no liveness — #150 not addressed"
  echo ""; echo "PASS=$PASS FAIL=$FAIL"; exit 1
fi
[ -n "$(line G_FLAG)" ] || { echo "FAIL — harness did not finish"; echo "$OUT" | tail -12; exit 1; }

echo "== T1: otel.js liveness() =="
case "$(line L_LIVE)" in '{"ok":true,"detail":"tracing live: 8 span(s)'*) ok "golden trace since the journey start → live, 8 spans counted" ;; *) bad "golden not read as live" "$(line L_LIVE)" ;; esac
[ "$(line L_QUIET)" = false ] && ok "Jaeger answers with nothing → not live" || bad "empty Jaeger read as live" "$(line L_QUIET)"
case "$(line L_DOWN)" in '{"ok":false,"detail":"Jaeger unreachable'*ECONNREFUSED*) ok "Jaeger refusing → not live, says unreachable" ;; *) bad "unreachable Jaeger mishandled" "$(line L_DOWN)" ;; esac
[ "$(line L_LATER)" = false ] && ok "spans older than the journey start do not count" || bad "stale spans counted" "$(line L_LATER)"
[ "$(line L_NAMED)" = true ] && [ "$(line L_NAMEDMISS)" = false ] && ok "a declared liveness span is looked for in the step capture" || bad "declared liveness span" "$(line L_NAMED) / $(line L_NAMEDMISS)"

echo "== T2: rung 2, negative-only claim (#150) =="
case "$(line T_NEG_EMPTY_LIVE)" in '["PASS Cancel reset: tracing live :: tracing live: 8 span(s)'*'","PASS [MF] NEGATIVE: Cancel reset: ACT_Settings_ResetAll did not run :: none ran"]') ok "zero step spans + live tracing → the claim is judged: PASS, with the liveness row" ;; *) bad "correct Cancel still unjudgeable" "$(line T_NEG_EMPTY_LIVE)" ;; esac
case "$(line T_NEG_EMPTY_DEAD)" in '["INVALID Cancel reset: spans :: negative-only claim (ACT_Settings_ResetAll must not run) with no liveness evidence: Jaeger answered, but '*'emitted no span'*) ok "zero spans, service silent → INVALID, never PASS" ;; *) bad "dead tracing passed a negative claim" "$(line T_NEG_EMPTY_DEAD)" ;; esac
case "$(line T_NEG_EMPTY_DOWN)" in '["INVALID Cancel reset: spans :: '*'Jaeger unreachable'*) ok "zero spans, Jaeger down → INVALID naming Jaeger" ;; *) bad "Jaeger down not named" "$(line T_NEG_EMPTY_DOWN)" ;; esac
case "$(line T_NEG_SPANS_CLEAN)" in *'PASS [GUARD] Cancel reset: capture non-empty'*'PASS [MF] NEGATIVE: Cancel reset: ACT_Settings_ResetAll did not run'*) ok "spans present without the forbidden one → PASS (the capture is its own evidence)" ;; *) bad "clean capture misjudged" "$(line T_NEG_SPANS_CLEAN)" ;; esac
case "$(line T_NEG_HIT)" in *'FAIL [MF] NEGATIVE: Cancel arm: ACT_MockScenario_Arm did not run :: MockServices.ACT_MockScenario_Arm'*) ok "forbidden microflow in the golden capture → FAIL naming it" ;; *) bad "forbidden microflow not caught" "$(line T_NEG_HIT)" ;; esac
case "$(line T_DECL_OK)" in *'PASS Cancel: tracing live :: liveness span POST /* captured'*'PASS [MF] NEGATIVE: Cancel: ACT_Settings_ResetAll did not run'*) ok "declared spans.liveness present → judged" ;; *) bad "declared liveness ignored" "$(line T_DECL_OK)" ;; esac
case "$(line T_DECL_MISS)" in '["INVALID Cancel: spans :: '*'declared liveness span Microflow X.DS_Page not captured'*) ok "declared spans.liveness absent → INVALID" ;; *) bad "missing declared liveness passed" "$(line T_DECL_MISS)" ;; esac
[ "$(line T_POS_EMPTY)" = '["INVALID Arm: spans :: zero spans captured — Jaeger down or OTel off. Trace rung did NOT run."]' ] \
  && ok "positive claim with zero spans → INVALID as before" || bad "positive-claim behaviour changed" "$(line T_POS_EMPTY)"
[ "$(line T_POS_OK)" = '["PASS [GUARD] Arm: capture non-empty","PASS [MF] Arm: ordered","PASS [MF] Arm: no ERROR at any level"]' ] \
  && ok "positive claim over the golden → unchanged rows" || bad "positive-claim rows changed" "$(line T_POS_OK)"

case "$(line T_NOTHING)" in '["INVALID Save: spans :: spans block declares neither `ordered` nor `mustNotFire`'*) ok "spans block with neither field → loud INVALID (#150 item 3)" ;; *) bad "empty spans block skipped silently" "$(line T_NOTHING)" ;; esac
case "$(line T_LEGACY)" in '["INVALID Save: spans :: '*) ok "array-shaped spans (a shape the runner does not read) → INVALID" ;; *) bad "unreadable spans shape skipped" "$(line T_LEGACY)" ;; esac
[ "$(line T_NOSPANS)" = '[]' ] && ok "no spans block → no trace rows (nothing claimed)" || bad "a step without spans produced trace rows" "$(line T_NOSPANS)"

echo "== T3: trace-negative positive control for a negative-only claim =="
[ "$(line M_SUPPORTED)" = '{"supported":true,"inject":["ACT_Settings_ResetAll"]}' ] && ok "mutant supported, injects the forbidden name" || bad "negative-only journey still has no trace-negative mutant" "$(line M_SUPPORTED)"
case "$(line M_LIVE)" in *'"caught":true}') ok "with tracing live the injected name turns 'did not run' red — the targeted check" ;; *) bad "mutant not caught by its targeted check" "$(line M_LIVE)" ;; esac
case "$(line M_DEAD)" in '["INVALID '*) ok "with tracing dead the mutant is INVALID — injection cannot vouch for a dead pipeline" ;; *) bad "mutant faked a proof over dead tracing" "$(line M_DEAD)" ;; esac
[ "$(line M_POS)" = '{"supported":true,"mustNot":["ACT_MockScenario_Arm"],"inject":null}' ] && ok "positive-claim journey: mutant unchanged (first ordered name, no injection)" || bad "positive mutant changed" "$(line M_POS)"
[ "$(line M_NONE)" = false ] && ok "no span claim at all → still unsupported" || bad "phantom mutant" "$(line M_NONE)"
[ "$(line F_SAMPLE)" = '["Mod.ACT_X","Mod.ACT_X",null]' ] && ok "regex pattern → a name it matches; invalid regex → null" || bad "forbiddenSample" "$(line F_SAMPLE)"

echo "== T4: app probe between journeys (#285) =="
[ "$(line A_UP)" = '{"up":true,"detail":"HTTP 200"}' ] && ok "HTTP 200 → up" || bad "200 not up" "$(line A_UP)"
[ "$(line A_REDIRECT)" = true ] && ok "a redirect (login page) is up" || bad "redirect read as down" "$(line A_REDIRECT)"
[ "$(line A_503)" = '{"up":false,"detail":"HTTP 503"}' ] && ok "HTTP 503 → down" || bad "5xx read as up" "$(line A_503)"
[ "$(line A_REFUSED)" = '{"up":false,"detail":"ECONNREFUSED"}' ] && ok "refused connection (runtime stopped) → down, ECONNREFUSED" || bad "refused not down" "$(line A_REFUSED)"
[ "$(line G_RECOVER)" = '{"up":true,"detail":"stub","tries":3}' ] && ok "a restart in progress is waited out (3 tries)" || bad "gate gave up early" "$(line G_RECOVER)"
[ "$(line G_DOWN)" = '{"up":false,"detail":"stub","tries":3}' ] && ok "down after every try → APP-DOWN" || bad "gate passed a dead app" "$(line G_DOWN)"
case "$(line G_FLAG)" in '{"n":1,'*'"verdict":"FAIL","detail":"x  [APP-DOWN after this journey: ECONNREFUSED'*'"appDown":true}'*) ok "only FAIL rows are flagged APP-DOWN, verdict kept" ;; *) bad "flagging wrong" "$(line G_FLAG)" ;; esac

echo ""
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
