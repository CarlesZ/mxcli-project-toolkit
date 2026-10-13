#!/usr/bin/env bash
# test-test-scratch.sh — project-bin/test-scratch.sh runs `mxcli test` on a copy, under locks.
#
# Usage: bash tests/wave2/test-test-scratch.sh [path-to-test-scratch.sh]
#
# WHY (#278, field run 2026-10-12): one `mxcli test` run unlocked in the live repo broke the
# running app (NoClassDefFoundError) with the .mpr unchanged; the fix that worked — scratch copy
# plus a lock on the fixed test ports — lived only in a private helper.
#
# Covers: the fake mxcli runs in the scratch dir with -p on the scratch .mpr, never the live one;
# the copy leaves out .mxcli (the live app's run --local record), .git and deployment; the port
# lock is held during the run and released after; a second run while the first holds the ports
# is refused; a dead holder's port lock is taken over; a live exec.sh on the project refuses the
# copy; --attach and -p are refused; mxcli's exit code is passed through; the copy is deleted.
# No real mxcli: a stub records its cwd and argv.
set -uo pipefail
TOOLKIT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SUBJECT="${1:-$TOOLKIT/project-bin/test-scratch.sh}"
case "$SUBJECT" in /*) ;; *) SUBJECT="$PWD/$SUBJECT" ;; esac
WORK="$(mktemp -d "${TMPDIR:-/tmp}/tscratch.XXXXXX")" || exit 2
WORK="$(cd "$WORK" && pwd -P)"
BG=""
trap 'for p in $BG; do kill -KILL "$p" 2>/dev/null; done; rm -rf "$WORK"' EXIT
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  ok   — $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL — $1"; }
has() { case "$2" in *"$3"*) ok "$1" ;; *) bad "$1 — missing '$3' in: $(printf '%s' "$2" | tail -3)" ;; esac; }
echo "== subject: $SUBJECT"

P="$WORK/proj"; mkdir -p "$P/bin" "$P/mprcontents" "$P/.mxcli" "$P/deployment/run" "$P/tests" "$WORK/tmp"
printf 'model\n' > "$P/Fixture.mpr"; printf 'unit\n' > "$P/mprcontents/a.mxunit"
printf '{"pid": 1}\n' > "$P/.mxcli/run-local.json"; printf 'x\n' > "$P/deployment/run/big"
printf 'test\n' > "$P/tests/a.test.mdl"
cp "$TOOLKIT/project-bin/_common.sh" "$P/bin/"; cp "$SUBJECT" "$P/bin/test-scratch.sh"
cat > "$P/mxcli" <<'STUB'
#!/usr/bin/env bash
{ echo "cwd=$(pwd -P)"; echo "args=$*"; ls -A; ls "${TMPDIR:-/tmp}" | grep -c mxtk-test-ports; } > "$REC"
sleep "${STUB_SLEEP:-0}"
echo "TESTRUNNER injected" >> Fixture.mpr      # what a real test run does to ITS model
exit "${STUB_RC:-0}"
STUB
chmod +x "$P/mxcli" "$P/bin/test-scratch.sh"
export TMPDIR="$WORK/tmp" MXTK_TEST_PORTS="$(( 30000 + RANDOM % 20000 )) $(( 30000 + RANDOM % 20000 ))"
run() { ( cd "$P" && REC="$WORK/rec.$1" ./bin/test-scratch.sh "${@:2}" ) 2>&1; }

echo "-- a scratch run"
OUT="$(run a -- tests/a.test.mdl --local)"; RC=$?
[ "$RC" -eq 0 ] && ok "exit 0" || bad "exit $RC: $OUT"
R="$(cat "$WORK/rec.a" 2>/dev/null)"
case "$R" in *"cwd=$WORK/tmp/Fixture-test."*) ok "mxcli ran in the scratch copy" ;; *) bad "mxcli cwd: $(printf '%s' "$R" | head -1)" ;; esac
case "$R" in *"-p $WORK/tmp/Fixture-test."*"/Fixture.mpr"*) ok "-p points at the scratch .mpr" ;; *) bad "args: $(printf '%s' "$R" | sed -n 2p)" ;; esac
printf '%s' "$R" | grep -qx '.mxcli' && bad "the live run --local record was copied" || ok ".mxcli (live app record) not copied"
printf '%s' "$R" | grep -qx 'deployment' && bad "deployment/ was copied" || ok "deployment/ not copied"
[ "$(printf '%s' "$R" | tail -1)" = 1 ] && ok "port lock held during the run" || bad "no port lock during the run"
[ "$(cat "$P/Fixture.mpr")" = model ] && ok "live .mpr untouched" || bad "live .mpr was written"
ls "$WORK/tmp" | grep -q 'mxtk-test-ports' && bad "port lock left behind" || ok "port lock released"
ls "$WORK/tmp" | grep -q 'Fixture-test' && bad "scratch copy left behind" || ok "scratch copy deleted"
[ -f "$P/.mpr-snapshots/.exec.lock" ] && bad "exec lock left behind" || ok "exec lock released"

echo "-- exit code passes through"
OUT="$(STUB_RC=4 run b -- tests/a.test.mdl)"; RC=$?
[ "$RC" -eq 4 ] && ok "mxcli exit 4 → 4" || bad "exit $RC"

echo "-- second run while the first holds the ports"
( cd "$P" && STUB_SLEEP=4 REC="$WORK/rec.c" exec ./bin/test-scratch.sh -- tests/a.test.mdl ) >/dev/null 2>&1 &
H=$!; BG="$BG $H"
for i in $(seq 1 40); do [ -f "$WORK/rec.c" ] && break; sleep 0.1; done
OUT="$(run d -- tests/a.test.mdl)"; RC=$?
[ "$RC" -eq 3 ] && ok "refused (exit 3)" || bad "exit $RC"
has "names the holder" "$OUT" "held by PID $H"
[ -f "$WORK/rec.d" ] && bad "the refused run ran mxcli" || ok "the refused run ran nothing"
kill -KILL "$H" 2>/dev/null; wait "$H" 2>/dev/null

echo "-- dead holder's port lock is taken over (the SIGKILL above left it)"
ls "$WORK/tmp" | grep -q 'mxtk-test-ports' && ok "[setup] stale port lock present" || bad "[setup] no stale lock"
rm -f "$P/.mpr-snapshots/.exec.lock"
OUT="$(run e -- tests/a.test.mdl)"; RC=$?
[ "$RC" -eq 0 ] && has "taken over out loud" "$OUT" "taking it over" || bad "stale port lock blocked (exit $RC)"

echo "-- a live exec.sh on this project refuses the copy"
mkdir -p "$P/.mpr-snapshots"; bash -c 'exec -a "bash ./bin/exec.sh mdlsource/x.mdl" sleep 20' & E=$!; BG="$BG $E"
sleep 0.2; printf '%s %s x.mdl\n' "$E" "$(date +%s)" > "$P/.mpr-snapshots/.exec.lock"
OUT="$(run f -- tests/a.test.mdl)"; RC=$?
[ "$RC" -eq 3 ] && ok "refused (exit 3)" || bad "exit $RC"
[ -f "$WORK/rec.f" ] && bad "ran during a live exec" || ok "nothing copied or run"
kill -KILL "$E" 2>/dev/null; wait "$E" 2>/dev/null; rm -f "$P/.mpr-snapshots/.exec.lock"

echo "-- refusals"
OUT="$(run g -- tests/a.test.mdl --attach)"; RC=$?
[ "$RC" -eq 3 ] && has "--attach refused" "$OUT" "LIVE app" || bad "--attach exit $RC"
OUT="$(run h -- tests/a.test.mdl -p Other.mpr)"; RC=$?
[ "$RC" -eq 2 ] && ok "-p refused" || bad "-p exit $RC"

echo ""
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
