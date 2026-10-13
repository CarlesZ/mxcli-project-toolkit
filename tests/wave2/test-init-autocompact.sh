#!/bin/bash
# test-init-autocompact.sh — init-project.sh must warn about a large auto-compact window (#167).
#
# Field finding (2026-09-29): a lead session left at a 1M auto-compact window averaged 363-466k
# context per call; the cost gap to a comparable build was context re-read per call, not call
# count. The fix is an advisory line, never a written setting. This fixture checks the four
# states by execution: nothing set, env var 1M, settings.json 250000 (ok), settings.json 1000000.
# Setting names (CLAUDE_CODE_AUTO_COMPACT_WINDOW, "autoCompactWindow", CLAUDE_CONFIG_DIR) were
# read out of the Claude Code 2.1.x CLI binary, and the per-model settings shape below is the
# shape a real ~/.claude/settings.json carried — not invented.
#
# Usage: bash test-init-autocompact.sh [path-to-init-project.sh]
# Fails against master's init-project.sh (no auto-compact line at all).
# Cases 5-8 (unparseable, string, 20-digit, project+user) were added after review of the first cut.

export MXTK_LEAKGUARD_DENYFILE="${TMPDIR:-/tmp}/mxtk-fixture-denylist.$$"
export MXTK_NO_GUIDE=1
SUBJECT="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../bin" && pwd)/init-project.sh}"
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  ok   — $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL — $1"; }

WORK=$(mktemp -d "${TMPDIR:-/tmp}/initac.XXXXXX") || exit 2
trap 'rm -rf "$WORK" "$MXTK_LEAKGUARD_DENYFILE"' EXIT

run() {   # $1 = case name, $2 = env value for CLAUDE_CODE_AUTO_COMPACT_WINDOW ("" = unset)
  local c="$1" envv="$2"
  mkdir -p "$WORK/home-$c/.claude" "$WORK/proj-$c"   # pre-made dirs/files are kept
  if [ -n "$envv" ]; then
    env CLAUDE_CODE_AUTO_COMPACT_WINDOW="$envv" CLAUDE_CONFIG_DIR="$WORK/home-$c/.claude" \
      bash "$SUBJECT" "$WORK/proj-$c" </dev/null > "$WORK/out-$c" 2>&1
  else
    env -u CLAUDE_CODE_AUTO_COMPACT_WINDOW CLAUDE_CONFIG_DIR="$WORK/home-$c/.claude" \
      bash "$SUBJECT" "$WORK/proj-$c" </dev/null > "$WORK/out-$c" 2>&1
  fi
  echo $?
}

echo "== subject: $SUBJECT"

rc=$(run none "")
[ "$rc" -eq 0 ] && ok "no setting: scaffold exits 0" || bad "no setting: scaffold exited $rc"
grep -q 'Recommended: /autocompact 250k' "$WORK/out-none" \
  && ok "no setting: recommends /autocompact 250k" || bad "no setting: no auto-compact recommendation"

rc=$(run env1m "1M")
[ "$rc" -eq 0 ] && ok "env 1M: scaffold still exits 0 (advice, not a gate)" || bad "env 1M: scaffold exited $rc"
grep -q 'WARNING: auto-compact window is above 250k: 1M (CLAUDE_CODE_AUTO_COMPACT_WINDOW)' "$WORK/out-env1m" \
  && ok "env 1M: warns and names the source" || bad "env 1M: no warning naming the env var"

mkdir -p "$WORK/home-ok/.claude"
printf '{\n  "modelSettings": {\n    "some-model": {\n      "autoCompactWindow": 250000\n    }\n  }\n}\n' \
  > "$WORK/home-ok/.claude/settings.json"
run ok "" >/dev/null
grep -q 'Auto-compact window: 250000 (autoCompactWindow in .*at or below 250k' "$WORK/out-ok" \
  && ok "settings 250000: reported ok" || bad "settings 250000: not reported as ok"
grep -q 'WARNING: auto-compact' "$WORK/out-ok" && bad "settings 250000: warned anyway" || ok "settings 250000: no warning"

mkdir -p "$WORK/home-big/.claude"
printf '{"autoCompactWindow":1000000}\n' > "$WORK/home-big/.claude/settings.json"
run big "" >/dev/null
grep -q 'WARNING: auto-compact window is above 250k: 1000000 (autoCompactWindow in' "$WORK/out-big" \
  && ok "settings 1000000: warns" || bad "settings 1000000: no warning"

rc=$(run garbage "1.5M")
[ "$rc" -eq 0 ] && ok "unparseable env value: scaffold exits 0" || bad "unparseable env value: scaffold exited $rc (must never fail on advice)"
grep -q 'unparseable: 1.5M' "$WORK/out-garbage" \
  && ok "unparseable env value: reported as unparseable" || bad "unparseable env value: not reported (silence reads as 'none set')"
grep -q 'none set' "$WORK/out-garbage" && bad "unparseable env value: printed 'none set' — false" || ok "unparseable env value: no false 'none set'"

# A string value in settings ("1M") is a value, not an absence.
mkdir -p "$WORK/home-str/.claude"
printf '{"autoCompactWindow": "1M"}\n' > "$WORK/home-str/.claude/settings.json"
run str "" >/dev/null
grep -q 'WARNING: auto-compact window is above 250k: "1M"' "$WORK/out-str" \
  && ok "settings string \"1M\": warns" || bad "settings string \"1M\": no warning"

# A 20-digit number must not reach shell arithmetic (stderr noise / overflow).
mkdir -p "$WORK/home-huge/.claude"
printf '{"autoCompactWindow": 99999999999999999999}\n' > "$WORK/home-huge/.claude/settings.json"
run huge "" >/dev/null
grep -q 'WARNING: auto-compact window is above 250k: 99999999999999999999' "$WORK/out-huge" \
  && ok "20-digit value: warns" || bad "20-digit value: no warning"
grep -qiE 'value too great|syntax error|integer expression' "$WORK/out-huge" \
  && bad "20-digit value: arithmetic error leaked to output" || ok "20-digit value: no arithmetic error"

# Project settings ok, user settings 1M: BOTH are read, and the worse one warns.
mkdir -p "$WORK/home-both/.claude" "$WORK/proj-both/.claude"
printf '{"autoCompactWindow":250000}\n' > "$WORK/proj-both/.claude/settings.json"
printf '{"autoCompactWindow":1000000}\n' > "$WORK/home-both/.claude/settings.json"
run both "" >/dev/null
grep -q 'WARNING: auto-compact window is above 250k: 1000000' "$WORK/out-both" \
  && ok "project 250k + user 1M: user value still warns" || bad "project 250k + user 1M: user value not read once the project had one"

# Never writes a setting.
if grep -rqs 'autoCompactWindow' $(ls -d "$WORK"/proj-*/.claude 2>/dev/null | grep -v '/proj-both/') 2>/dev/null; then
  bad "init wrote an autoCompactWindow setting into the project — it must only advise"
else ok "nothing written: no autoCompactWindow in any scaffolded .claude/"; fi

echo "== $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
