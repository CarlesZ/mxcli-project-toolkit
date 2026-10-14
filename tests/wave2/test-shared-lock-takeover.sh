#!/usr/bin/env bash
# test-shared-lock-takeover.sh — exec.sh and test-scratch.sh share .mpr-snapshots/.exec.lock; contending
# on one DEAD-holder lock, they must never both hold it.
#
# Usage: bash tests/wave2/test-shared-lock-takeover.sh [path-to-test-scratch.sh] [path-to-exec.sh]
#
# WHY (review of #304, PR #324): both scripts take the same per-project lock and both take over a dead
# holder's lock. Each was made safe on its own by a serialised takeover (an O_EXCL `<lock>.takeover`,
# re-read, remove only the exact stale line). Two private protocols would not exclude EACH OTHER: the
# takeover file name and the compare-then-remove rule must be the same in both scripts.
#
# How: the lock code is lifted from each script (exec.sh: exec_lock_live .. the LOCK_TAKEN check;
# test-scratch.sh: holder_live .. take_lock) into two small contender scripts whose names contain
# "exec.sh" / "test-scratch.sh", so each script's liveness check recognises the other as a holder.
# Rounds of 5 + 5 contenders start together on a lock whose holder pid is dead; each holder marks
# itself in a shared dir while it holds the lock. Two marks at once = two holders = FAIL.
# When the given exec.sh has no exec_lock_takeover yet (PR #324 unmerged), its block comes from the
# verbatim copy in fixtures/mxtest-guard/exec-lock-block.sh, and says so.
set -uo pipefail
TOOLKIT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TS="${1:-$TOOLKIT/project-bin/test-scratch.sh}"; EX="${2:-$TOOLKIT/project-bin/exec.sh}"
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  ok   — $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL — $1"; }
WORK="$(mktemp -d "${TMPDIR:-/tmp}/sharedlock.XXXXXX")" || exit 2
trap 'rm -rf "$WORK"' EXIT
echo "== test-scratch: $TS"

BLOCK="$WORK/exec-block.sh"
awk '/^exec_lock_live\(\) \{/ {p=1} p {print} p && /^if \[ "\$LOCK_TAKEN" != 1 \]; then$/ {e=1} e && /^fi$/ {exit}' "$EX" > "$BLOCK"
if grep -q '^exec_lock_takeover() {' "$BLOCK"; then echo "== exec.sh lock block: $EX"
else
  sed '1,4d' \
    "$TOOLKIT/tests/wave2/fixtures/mxtest-guard/exec-lock-block.sh"  > "$BLOCK"
  echo "== exec.sh lock block: verbatim copy from PR #324 ($EX has no exec_lock_takeover yet)"
fi
grep -q '^exec_lock_takeover() {' "$BLOCK" && ok "[setup] exec.sh lock block lifted" || { bad "[setup] no exec.sh lock block"; echo "PASS=$PASS FAIL=$FAIL"; exit 1; }
awk '/^holder_live\(\) \{/ {p=1} /^release\(\) \{/ {p=0} p' "$TS" > "$WORK/ts-block.sh"
grep -q '^take_lock() {' "$WORK/ts-block.sh" && ok "[setup] test-scratch take_lock lifted" || { bad "[setup] no take_lock in $TS"; echo "PASS=$PASS FAIL=$FAIL"; exit 1; }

LOCK="$WORK/.exec.lock"; HOLD="$WORK/holding"; mkdir -p "$HOLD"
hold() {  # body shared by both contenders: mark, look for another mark, unmark
  cat <<'H'
touch "$HOLD/$$"; n=$(ls "$HOLD" | wc -l | tr -d ' ')
[ "$n" -gt 1 ] && echo "OVERLAP $$ with $(ls "$HOLD" | tr '\n' ' ')" >> "$WORK/overlaps"
echo "$ROLE $$" >> "$WORK/holders"; sleep 0.3; rm -f "$HOLD/$$"
H
}
{ echo 'LOCK="$1"; LOG_NAME="exec-contender"; ROLE=exec'; cat "$BLOCK"; hold
  echo '_own="$(head -1 "$LOCK" 2>/dev/null)"; [ "${_own%% *}" = "$$" ] && rm -f "$LOCK"'; } > "$WORK/contender-exec.sh"
{ echo 'LOCK="$1"; ROLE=scratch'; cat "$WORK/ts-block.sh"
  echo 'take_lock "$LOCK" "the exec lock" >/dev/null 2>&1 || exit 1'; hold
  echo '_own="$(head -1 "$LOCK" 2>/dev/null)"; [ "${_own%% *}" = "$$" ] && rm -f "$LOCK"'; } > "$WORK/contender-test-scratch.sh"

sleep 0 & DEAD=$!; wait "$DEAD"   # a pid that is certainly not running now
ROUNDS=4
for r in $(seq 1 "$ROUNDS"); do
  printf '%s %s exec.sh\n' "$DEAD" "$(date +%s)" > "$LOCK"; rm -f "$LOCK.takeover"
  PIDS=""
  for i in 1 2 3 4 5; do
    WORK="$WORK" HOLD="$HOLD" bash "$WORK/contender-exec.sh" "$LOCK" >/dev/null 2>&1 & PIDS="$PIDS $!"
    WORK="$WORK" HOLD="$HOLD" bash "$WORK/contender-test-scratch.sh" "$LOCK" >/dev/null 2>&1 & PIDS="$PIDS $!"
  done
  for p in $PIDS; do wait "$p"; done
done
N="$(wc -l < "$WORK/holders" 2>/dev/null | tr -d ' ')"
[ "${N:-0}" -ge "$ROUNDS" ] && ok "the dead holder's lock was taken over in every round ($N holds over $ROUNDS rounds)" || bad "only ${N:-0} holds in $ROUNDS rounds"
grep -q '^exec ' "$WORK/holders" 2>/dev/null && grep -q '^scratch ' "$WORK/holders" 2>/dev/null \
  && ok "both scripts won the lock at some point (they really contended)" || echo "  note: one script won every round: $(cut -d' ' -f1 "$WORK/holders" 2>/dev/null | sort | uniq -c | tr '\n' ' ')"
if [ -s "$WORK/overlaps" ]; then bad "two holders at once: $(head -3 "$WORK/overlaps" | tr '\n' ' ')"; else ok "never two holders at once"; fi
[ -e "$LOCK.takeover" ] && bad "takeover file left behind" || ok "no takeover file left behind"

echo ""
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
