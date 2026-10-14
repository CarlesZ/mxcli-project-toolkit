#!/usr/bin/env bash
# test-token-burn.sh — pin bin/token-burn.sh against a CAPTURED (then scrubbed) Claude Code
# transcript: tests/wave2/fixtures/token-burn/CAPTURE.md says what was captured, how it was
# scrubbed, and the expected sums computed independently of the instrument.
#
#   T1  no transcript tree → NOT AVAILABLE in brief, screen and json (available:false), exit 0
#   T2  --json: per-model arrays to the token, usage from each id's per-field max (= last record on this capture); 52 records dedupe to 22 messages; 1 synthetic
#       skipped; 2 files; subagent headline 61357
#   T3  the two-tree layout: records whose cwd is <root>/app count — moving them out of the
#       project drops the message count from 22 to 21
#   T4  --brief: the exact "Tokens this stage:" line for stage 2
#   T5  screen: synthetic count, stage-2 row, current-stage line, no UNMAPPED
#   T6  no PROJECT.md → every day UNMAPPED; brief prints the project total and says why
#   T7  a foreign slug dir only → NOT AVAILABLE with the --scan-all hint; --scan-all finds it
#   T8  the ancestor slug dir (session launched in the parent) is read by default
#   --- #296: opt-in cost / agent time / human prompts / windows ---
#   T9  without the new flags nothing new appears (screen + json; T1-T8 pin the rest)
#   T10 --rates: per-Mtok cost from a rates file, main vs subagent, a `*` catch-all
#   T11 --rates with no line for a model: INCOMPLETE, total marked `+`, complete:false — never 0
#   T12 --effort: agent working time and human prompt count over the captured main thread plus
#       effort/s-3.jsonl (every user-record class); --gap changes the cut-off; a later
#       record with zero usage for the same message.id leaves the real numbers intact
#   T13 --windows: per-window messages, headline, agent time, prompts
#   T14 malformed --rates / --windows file → exit 1 with the line number
#
#   tests/wave2/test-token-burn.sh /path/to/token-burn.sh

set -uo pipefail

SUT="${1:?usage: test-token-burn.sh /path/to/token-burn.sh}"
case "$SUT" in /*) ;; *) SUT="$PWD/$SUT" ;; esac
TOOLKIT="$(cd "$(dirname "$SUT")/.." && pwd)"
FIX="$TOOLKIT/tests/wave2/fixtures/token-burn"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/tb.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
PASS=0; FAIL=0

ok()  { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL %s\n     %s\n' "$1" "${2:-}"; }
has()   { case "$2" in *"$3"*) ok "$1" ;; *) bad "$1" "missing '$3' in: $2" ;; esac; }
hasnt() { case "$2" in *"$3"*) bad "$1" "unexpected '$3'" ;; *) ok "$1" ;; esac; }

[ -f "$FIX/transcripts/s-1.jsonl" ] || { echo "fixture missing"; exit 2; }

slug() { printf '%s' "$1" | sed 's/[^A-Za-z0-9]/-/g'; }

P="$WORK/proj"; mkdir -p "$P/app"
cp "$FIX/PROJECT.md" "$P/PROJECT.md"

# install the fixture transcripts under a slug dir, rewriting the scrubbed root to $P
install_tree() {   # $1 = config dir, $2 = slug dir name
  local d="$1/projects/$2"
  mkdir -p "$d/s-1/subagents"
  sed "s#/srv/example/proj#$P#g" "$FIX/transcripts/s-1.jsonl" > "$d/s-1.jsonl"
  sed "s#/srv/example/proj#$P#g" "$FIX/transcripts/s-1/subagents/agent-1.jsonl" > "$d/s-1/subagents/agent-1.jsonl"
}

CFG="$WORK/claude"; install_tree "$CFG" "$(slug "$P")"

# --- T1: no tree --------------------------------------------------------------------------
OUT="$(CLAUDE_CONFIG_DIR="$WORK/nowhere" bash "$SUT" "$P" --brief 2>&1)"; RC=$?
has "T1 brief NOT AVAILABLE" "$OUT" "Tokens this stage: NOT AVAILABLE"
[ "$RC" = 0 ] && ok "T1 brief exit 0" || bad "T1 brief exit 0" "rc=$RC"
OUT="$(CLAUDE_CONFIG_DIR="$WORK/nowhere" bash "$SUT" "$P" 2>&1)"; RC=$?
has "T1 screen NOT AVAILABLE" "$OUT" "NOT AVAILABLE"
[ "$RC" = 0 ] && ok "T1 screen exit 0" || bad "T1 screen exit 0" "rc=$RC"
OUT="$(CLAUDE_CONFIG_DIR="$WORK/nowhere" bash "$SUT" "$P" --json 2>&1)"
has "T1 json available:false" "$OUT" '"available": false'

# --- T2: json, exact sums ------------------------------------------------------------------
# the instrument pretty-prints (indent=1, one list element per line); fold the whitespace so a
# per-model array can be pinned as one literal (no python here — check-portability)
J="$(CLAUDE_CONFIG_DIR="$CFG" bash "$SUT" "$P" --json 2>&1 | tr -d '\n' | tr -s ' ' | sed 's/\[ /[/g; s/ \]/]/g')"
has "T2 fable-5-1 array" "$J" '"claude-fable-5-1": [288, 31365, 2607781, 15524, 9]'
# the subagent model's array, matched by its numbers (the model id is the captured one, see CAPTURE.md)
echo "$J" | grep -Eq '"claude-[a-z]+-5": \[26, 59772, 998476, 1559, 13\]' && ok "T2 subagent-model array (per-field max (= last record on this capture) per id: output 1559, the first record says 60)" || bad "T2 subagent-model array" "$J"
has "T2 22 messages"     "$J" '"messages": 22'
has "T2 52 records (dedupe)" "$J" '"records": 52'
has "T2 1 synthetic"     "$J" '"synthetic_skipped": 1'
has "T2 2 files"         "$J" '"files": 2'
has "T2 subagent headline (59858 when the first record was kept)" "$J" '"subagents": 61357'
has "T2 main headline"   "$J" '"main": 47177'
has "T2 current stage"   "$J" '"current_stage": "2"'

# --- T3: two-tree cwd counts ----------------------------------------------------------------
CFG3="$WORK/claude3"; d3="$CFG3/projects/$(slug "$P")"; mkdir -p "$d3/s-1/subagents"
sed "s#/srv/example/proj/app#$WORK/elsewhere#g; s#/srv/example/proj#$P#g" "$FIX/transcripts/s-1.jsonl" > "$d3/s-1.jsonl"
sed "s#/srv/example/proj#$P#g" "$FIX/transcripts/s-1/subagents/agent-1.jsonl" > "$d3/s-1/subagents/agent-1.jsonl"
J3="$(CLAUDE_CONFIG_DIR="$CFG3" bash "$SUT" "$P" --json 2>&1)"
has "T3 app/ records counted (22 -> 21 once moved out of the root)" "$J3" '"messages": 21'

# --- T4: brief -----------------------------------------------------------------------------
B="$(CLAUDE_CONFIG_DIR="$CFG" bash "$SUT" "$P" --brief 2>&1)"
printf '%s\n' "$B" | grep -Eqx 'Tokens this stage: 70k \([a-z]+-5 88% · fable-5-1 12% · 1438k cache-read · 2 days · stage 2\)' \
  && ok "T4 brief line exact" || bad "T4 brief line exact" "$B"

# --- T5: screen -----------------------------------------------------------------------------
S="$(CLAUDE_CONFIG_DIR="$CFG" bash "$SUT" "$P" 2>&1)"
has "T5 synthetic skipped" "$S" "1 synthetic skipped"
has "T5 22 messages from 52 records" "$S" "22 messages (from 52 records"
has "T5 current stage line" "$S" "register says current stage 2"
has "T5 subagent share" "$S" "subagents (Agent tool): 61k of headline (57%)"
# the caveat line legitimately explains what UNMAPPED means; no day or stage row may carry it
hasnt "T5 no UNMAPPED row" "$(echo "$S" | grep -v '^  caveat:')" "UNMAPPED"
echo "$S" | grep -Eq '^ *2 +2 +70k +1438k +17 ' && ok "T5 stage-2 row" || bad "T5 stage-2 row" "$(echo "$S" | grep -E '^ *2 ' | head -3)"
echo "$S" | grep -Eq '^ *1 +1 +39k +2168k +5 ' && ok "T5 stage-1 row" || bad "T5 stage-1 row" "$(echo "$S" | grep -E '^ *1 ' | head -3)"

# --- T6: no PROJECT.md ----------------------------------------------------------------------
P6="$WORK/proj6"; mkdir -p "$P6/app"
CFG6="$WORK/claude6"; d="$CFG6/projects/$(slug "$P6")"; mkdir -p "$d/s-1/subagents"
sed "s#/srv/example/proj#$P6#g" "$FIX/transcripts/s-1.jsonl" > "$d/s-1.jsonl"
sed "s#/srv/example/proj#$P6#g" "$FIX/transcripts/s-1/subagents/agent-1.jsonl" > "$d/s-1/subagents/agent-1.jsonl"
S6="$(CLAUDE_CONFIG_DIR="$CFG6" bash "$SUT" "$P6" 2>&1)"
has "T6 screen UNMAPPED" "$S6" "UNMAPPED"
B6="$(CLAUDE_CONFIG_DIR="$CFG6" bash "$SUT" "$P6" --brief 2>&1)"
has "T6 brief falls back to the project total" "$B6" "Tokens this stage: 109k ("
has "T6 brief says why" "$B6" "no Current stage line in PROJECT.md"

# --- T7: foreign slug only ------------------------------------------------------------------
CFG7="$WORK/claude7"; install_tree "$CFG7" "-somewhere-else-entirely"
B7="$(CLAUDE_CONFIG_DIR="$CFG7" bash "$SUT" "$P" --brief 2>&1)"; RC=$?
has "T7 NOT AVAILABLE with hint" "$B7" "try --scan-all"
[ "$RC" = 0 ] && ok "T7 exit 0" || bad "T7 exit 0" "rc=$RC"
J7="$(CLAUDE_CONFIG_DIR="$CFG7" bash "$SUT" "$P" --json --scan-all 2>&1)"
has "T7 --scan-all finds 22" "$J7" '"messages": 22'

# --- T8: ancestor slug dir ------------------------------------------------------------------
CFG8="$WORK/claude8"; install_tree "$CFG8" "$(slug "$WORK")"
J8="$(CLAUDE_CONFIG_DIR="$CFG8" bash "$SUT" "$P" --json 2>&1)"
has "T8 ancestor dir read by default" "$J8" '"messages": 22'

# --- #296 ----------------------------------------------------------------------------------
fold() { tr -d '\n' | tr -s ' ' | sed 's/\[ /[/g; s/ \]/]/g'; }

# T9: unchanged without the flags
hasnt "T9 screen has no COST section" "$S" "COST ("
hasnt "T9 screen has no agent time" "$S" "agent working time"
hasnt "T9 screen has no WINDOWS section" "$S" "WINDOWS ("
hasnt "T9 json has no cost key" "$J" '"cost":'
hasnt "T9 json has no effort key" "$J" '"effort":'
hasnt "T9 json has no windows key" "$J" '"windows":'

# T10: rates (made-up prices — the instrument carries none of its own)
RATES="$WORK/rates.txt"
printf '%s\n' '# test rates, per Mtok' 'currency EUR' 'claude-fable-*  2.00  2.50  0.20  10.00' '*  1.00  1.00  0.10  5.00' > "$RATES"
J10="$(CLAUDE_CONFIG_DIR="$CFG" bash "$SUT" "$P" --json --rates "$RATES" 2>&1 | fold)"
has "T10 total 0.9232"      "$J10" '"total": 0.9232'
has "T10 main 0.7558"       "$J10" '"main": 0.7558'
has "T10 subagents 0.1674"  "$J10" '"subagents": 0.1674'
has "T10 complete"          "$J10" '"complete": true'
has "T10 currency"          "$J10" '"currency": "EUR"'
has "T10 tokens unchanged"  "$J10" '"messages": 22'
S10="$(CLAUDE_CONFIG_DIR="$CFG" bash "$SUT" "$P" --rates "$RATES" 2>&1)"
echo "$S10" | grep -Eq '^TOTAL +0\.92$' && ok "T10 screen total" || bad "T10 screen total" "$(echo "$S10" | grep '^TOTAL')"
has "T10 subagent cost line" "$S10" "subagents (Agent tool): 0.17 EUR of 0.92"
B10="$(CLAUDE_CONFIG_DIR="$CFG" bash "$SUT" "$P" --brief --rates "$RATES" 2>&1)"
[ "$B10" = "$B" ] && ok "T10 --brief unchanged by --rates" || bad "T10 --brief unchanged by --rates" "$B10"

# T11: a model with no rate line
R11="$WORK/rates-partial.txt"; printf '%s\n' 'claude-fable-*  2.00  2.50  0.20  10.00' > "$R11"
J11="$(CLAUDE_CONFIG_DIR="$CFG" bash "$SUT" "$P" --json --rates "$R11" 2>&1 | fold)"
has "T11 complete:false" "$J11" '"complete": false'
has "T11 priced part only" "$J11" '"total": 0.7558'
S11="$(CLAUDE_CONFIG_DIR="$CFG" bash "$SUT" "$P" --rates "$R11" 2>&1)"
has "T11 INCOMPLETE named" "$S11" "INCOMPLETE — no rate line matches"
echo "$S11" | grep -Eq '^TOTAL +0\.76\+$' && ok "T11 total marked +" || bad "T11 total marked +" "$(echo "$S11" | grep '^TOTAL')"

# T12: effort — captured main thread + the user-record classes in effort/s-3.jsonl
CFG12="$WORK/claude12"; install_tree "$CFG12" "$(slug "$P")"
sed "s#/srv/example/proj#$P#g" "$FIX/effort/s-3.jsonl" > "$CFG12/projects/$(slug "$P")/s-3.jsonl"
J12="$(CLAUDE_CONFIG_DIR="$CFG12" bash "$SUT" "$P" --json --effort 2>&1 | fold)"
has "T12 4 human prompts (dup uuid once; meta, notification, peer, compact, tool result, <wrapper>, sidechain, foreign cwd excluded)" "$J12" '"human_prompts": 4'
has "T12 agent seconds 591 (220 captured + 371)" "$J12" '"agent_seconds": 591'
has "T12 a later zero-usage record of msg_e1 does not erase its usage (per-field max)" "$J12" '"2026-09-20": { "stage": "2", "usage": [121, 1500, 30000, 286, 6] }'
S12="$(CLAUDE_CONFIG_DIR="$CFG12" bash "$SUT" "$P" --effort 2>&1)"
has "T12 screen line" "$S12" "agent working time: 0h 10m (main thread, gaps <= 5 min, gaps ending at a human prompt excluded) · human prompts: 4"
J12g="$(CLAUDE_CONFIG_DIR="$CFG12" bash "$SUT" "$P" --json --gap 1 2>&1 | fold)"
has "T12 --gap 1 cuts the 114 s gap (477)" "$J12g" '"agent_seconds": 477'

# T13: windows
WIN="$WORK/windows.txt"
printf '%s\n' '# round boundaries' '2026-09-01 setup' '2026-09-17 round 1' '2026-09-18T02:00 wrap-up' > "$WIN"
S13="$(CLAUDE_CONFIG_DIR="$CFG12" bash "$SUT" "$P" --windows "$WIN" --rates "$RATES" 2>&1)"
echo "$S13" | grep -Eq '^setup +2026-09-01 +5 +39k +2168k +[0-9.]+ +0h 03m +0$' && ok "T13 setup row" || bad "T13 setup row" "$(echo "$S13" | grep '^setup')"
echo "$S13" | grep -Eq '^round 1 +2026-09-17 +13 +61k +998k +[0-9.]+ +0h 00m +0$' && ok "T13 round 1 row" || bad "T13 round 1 row" "$(echo "$S13" | grep '^round 1')"
echo "$S13" | grep -Eq '^wrap-up +2026-09-18T02:00 +10 +11k +[0-9]+k +[0-9.]+ +0h 07m +4$' && ok "T13 wrap-up row" || bad "T13 wrap-up row" "$(echo "$S13" | grep '^wrap-up')"
hasnt "T13 no empty before-first row" "$S13" "(before first window)"
J13="$(CLAUDE_CONFIG_DIR="$CFG12" bash "$SUT" "$P" --json --windows "$WIN" 2>&1 | fold)"
has "T13 json order" "$J13" '"order": ["setup", "round 1", "wrap-up"]'
has "T13 json wrap-up agent seconds 427" "$J13" '"agent_seconds": 427'

# T14: malformed config files are usage errors
printf '%s\n' 'claude-fable-* 2 2.5' > "$WORK/bad-rates.txt"
OUT="$(CLAUDE_CONFIG_DIR="$CFG" bash "$SUT" "$P" --rates "$WORK/bad-rates.txt" 2>&1)"; RC=$?
[ "$RC" = 1 ] && ok "T14 bad rates exit 1" || bad "T14 bad rates exit 1" "rc=$RC"
has "T14 bad rates names the line" "$OUT" "bad-rates.txt:1:"
printf '%s\n' 'next tuesday round 2' > "$WORK/bad-win.txt"
OUT="$(CLAUDE_CONFIG_DIR="$CFG" bash "$SUT" "$P" --windows "$WORK/bad-win.txt" 2>&1)"; RC=$?
[ "$RC" = 1 ] && ok "T14 bad windows exit 1" || bad "T14 bad windows exit 1" "rc=$RC"

echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" = 0 ]
