#!/usr/bin/env bash
# test-status-existing-app.sh — bin/status.sh in existing-app-change mode (#301) and the manual
# Studio Pro step count (#298).
#
# Usage: bash tests/wave2/test-status-existing-app.sh bin/status.sh
#
# GOLDEN INPUT IS THE REAL SCAFFOLD. Every PROJECT.md here is written by the real
# bin/init-project.sh (agent stubs with their unfilled slots included); the fixture adds only an
# "Entry mode:" line, a BUILD-LOG and the sections under test. The baseline is status.sh as it was
# at BASE_REF (the commit before this change), run from the SAME toolkit copy as the subject, so the
# two outputs differ only by the script.
#
#   T1  pipeline project (migration), --brief and full: byte-identical to the baseline, with the
#       agent-slot and done- stall WATCH items present in both (control: the noise is real there)
#   T2  pipeline project carrying a "## Rounds" section: still byte-identical (the section is
#       read in existing-app-change mode only)
#   T3  existing-app-change, rounds recorded: ROUND line is the LAST row, with stories and the
#       delivered count; full screen carries it too
#   T4  existing-app-change: no "agent slots unfilled" / "done- stalled" in WATCH, NEXT does not
#       point at done-; the baseline on the same project DID print them (so the case can fail)
#   T5  existing-app-change, no Rounds section: the ROUND line says none recorded and where to add it
#   T6  Rounds table without a Stories column: no stories part, no crash
#   T7  docs/manual-steps.md: unticked Done lines counted, ticked ones in the total, the fenced
#       example ignored — on --brief STATE and on the full screen
#   T8  the shipped template copied as-is counts 0 of 0 (its example is fenced)

export MXTK_LEAKGUARD_DENYFILE="${TMPDIR:-/tmp}/mxtk-fixture-denylist.$$"
export MXTK_NO_GUIDE=1
export MXTK_SYNC_SKIP_CLONE_CHECK=1
set -uo pipefail

SUT="${1:?usage: test-status-existing-app.sh /path/to/bin/status.sh}"
case "$SUT" in /*) ;; *) SUT="$PWD/$SUT" ;; esac
SRC="$(cd "$(dirname "$SUT")/.." && pwd)"
BASE_REF="${BASE_REF:-b9cf37c44884a74a357b7b14bc595ea78304a0b2}"
W="$(mktemp -d "${TMPDIR:-/tmp}/statusea.XXXXXX")" || exit 2
trap 'rm -rf "$W"; rm -f "$MXTK_LEAKGUARD_DENYFILE"' EXIT
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; [ -n "${2:-}" ] && printf '%s\n' "$2" | sed 's/^/  FAIL-detail: /'; }

# One toolkit copy, not a git checkout, so the toolkit sha reads "?" for both scripts alike.
mkdir -p "$W/tk"
(cd "$SRC" && tar --exclude=.git --exclude=node_modules -cf - .) | (cd "$W/tk" && tar -xf -)
cp "$SUT" "$W/tk/bin/status.sh"
HAVE_BASE=0
if git -C "$SRC" show "$BASE_REF:bin/status.sh" > "$W/tk/bin/status-baseline.sh" 2>/dev/null; then
  chmod +x "$W/tk/bin/status-baseline.sh"; HAVE_BASE=1
fi
NEW="$W/tk/bin/status.sh"; OLD="$W/tk/bin/status-baseline.sh"

mkproj() {  # mkproj <name> <entry mode text>
  local d="$W/$1"; mkdir -p "$d/mdlsource" "$d/docs"; : > "$d/Fixture.mpr"
  "$W/tk/bin/init-project.sh" "$d" >/dev/null 2>&1
  # Entry mode the way a register records it, right under the Current stage heading.
  awk -v m="$2" '{print} /^## Current stage/ {getline; print; print ""; print "Entry mode: " m " CONFIRMED"}' \
    "$d/PROJECT.md" > "$d/PROJECT.md.new" && mv "$d/PROJECT.md.new" "$d/PROJECT.md"
  # Three gate-passed scripts, none renamed done- — the "done- stalled" condition.
  local s
  # Header and row shape as project-bin/exec.sh log_build() writes them (gate column = GATE_STATE).
  { echo "| when (ISO-8601 local) | script | gate | result | detail |"; echo "|---|---|---|---|---|"; } > "$d/docs/BUILD-LOG.md"
  for s in 010-a 020-b 030-c; do
    echo "-- $s" > "$d/mdlsource/$s.mdl"
    echo "| 2026-10-13T10:00:00+0200 | \`$s.mdl\` | pass | ✅ applied | $s.mdl; lint ok |" >> "$d/docs/BUILD-LOG.md"
  done
  echo "$d"
}
# The doctor receipt's age ("0 min ago") can tick over between the two runs; it is the only
# wall-clock text on the screen, so it is masked for the byte comparison and nothing else is.
norm() { sed -E 's/[0-9]+ (min|h|days) ago/N \1 ago/g'; }
add_rounds() {  # add_rounds <proj>  (table on stdin) — appended as its own section
  { printf '\n## Rounds\n\n'; cat; } >> "$1/PROJECT.md"
}

echo "== bin/status.sh — existing-app-change rounds (#301) + manual steps (#298) =="

# --- T1 / T2: pipeline modes are untouched -------------------------------------------------------
P="$(mkproj pipe "migration")"
if [ "$HAVE_BASE" = 1 ]; then
  for mode in --brief ""; do
    o="$("$OLD" "$P" $mode 2>&1 | norm)"; n="$("$NEW" "$P" $mode 2>&1 | norm)"
    [ "$o" = "$n" ] && ok "T1 pipeline project ${mode:-full}: byte-identical to baseline" \
                    || bad "T1 pipeline project ${mode:-full} output changed" "$(diff <(echo "$o") <(echo "$n"))"
  done
  case "$o" in *"agent slots unfilled"*"done- stalled"*|*"done- stalled"*"agent slots unfilled"*) ok "T1 control: the pipeline screen carries agent-slot + done- stall WATCH items";;
    *) bad "T1 control: expected both WATCH items on the pipeline project (fixture no longer exercises them)" "$o";; esac
  printf '| Round | Title | Stories | State |\n|---|---|---|---|\n| 1 | Export fixes | S-1 | in test |\n' | add_rounds "$P"
  for mode in --brief ""; do
    o="$("$OLD" "$P" $mode 2>&1 | norm)"; n="$("$NEW" "$P" $mode 2>&1 | norm)"
    [ "$o" = "$n" ] && ok "T2 pipeline project with a Rounds section ${mode:-full}: byte-identical" \
                    || bad "T2 Rounds section changed a pipeline screen (${mode:-full})" "$(diff <(echo "$o") <(echo "$n"))"
  done
else
  bad "T1/T2 NOT RUN: baseline $BASE_REF not in this checkout's history (fetch full history)"
fi

# --- T3 / T4: existing-app-change with rounds ------------------------------------------------
E="$(mkproj eac "Change an existing app")"
printf '%s\n' '| Round | Title | Stories | State |' '|---|---|---|---|' \
  '| 1 | Export fixes | S-101, S-102 | delivered |' \
  '| 2 | Approval rework | S-110, S-111 | in test |' | add_rounds "$E"
b="$("$NEW" "$E" --brief 2>&1)"
exp='ROUND   Round 2: Approval rework — in test · stories: S-110, S-111 · 1 of 2 round(s) delivered'
printf '%s\n' "$b" | grep -qxF "$exp" && ok "T3 --brief ROUND line is the last row, with stories and delivered count" \
  || bad "T3 --brief ROUND line" "$b"
[ "$(printf '%s\n' "$b" | sed -n 2p | cut -c1-5)" = "ROUND" ] && ok "T3 ROUND sits right under WHERE" || bad "T3 ROUND line position" "$b"
f="$("$NEW" "$E" 2>&1)"
printf '%s\n' "$f" | grep -qF 'ROUND     Round 2: Approval rework — in test' && ok "T3 full screen carries the ROUND line" || bad "T3 full screen ROUND line" "$f"
case "$b$f" in *"agent slots unfilled"*) bad "T4 agent-slot noise still printed in existing-app mode" "$b";; *) ok "T4 no agent-slot WATCH item";; esac
case "$b$f" in *"done- stalled"*|*"not done-"*) bad "T4 done- noise still printed in existing-app mode" "$b";; *) ok "T4 no done- stall in WATCH or NEXT";; esac
if [ "$HAVE_BASE" = 1 ]; then
  o="$("$OLD" "$E" --brief 2>&1)"
  case "$o" in *"agent slots unfilled"*) ok "T4 control: the baseline printed the agent-slot noise on this same project";;
    *) bad "T4 control: baseline did not print agent-slot noise — case cannot fail" "$o";; esac
  case "$o" in *ROUND*) bad "T4 control: baseline already has a ROUND line?" "$o";; *) ok "T4 control: the baseline has no ROUND line";; esac
fi

# --- T5: no Rounds section -------------------------------------------------------------------
E2="$(mkproj eac-none "existing-app-change")"
b="$("$NEW" "$E2" --brief 2>&1)"
printf '%s\n' "$b" | grep -q '^ROUND   none recorded — add a row to PROJECT.md "## Rounds"' && ok "T5 no rounds: says none recorded and where" || bad "T5 no-rounds line" "$b"

# --- T6: no Stories column ------------------------------------------------------------------
E3="$(mkproj eac-nostories "Change an existing app")"
printf '%s\n' '| Round | Title | State |' '|---|---|---|' '| 1 | Login tweak | building |' | add_rounds "$E3"
b="$("$NEW" "$E3" --brief 2>&1)"
printf '%s\n' "$b" | grep -qxF 'ROUND   Round 1: Login tweak — building · 0 of 1 round(s) delivered' && ok "T6 no Stories column: no stories part" || bad "T6 no-Stories-column ROUND line" "$b"

# --- T7: manual steps count ----------------------------------------------------------------
cat > "$E/docs/manual-steps.md" <<'EOF'
# Manual Studio Pro steps

```markdown
- [ ] Done — example, fenced, must not count
```

### MS-01 — a
- [x] Done — by hand (commit abc1234)
### MS-02 — b
- [ ] Done — pending
### MS-03 — c
- [ ] **Done** — pending
Not a step: - [ ] Done mid-line
EOF
b="$("$NEW" "$E" --brief 2>&1)"
printf '%s\n' "$b" | grep '^STATE' | grep -qF '· manual steps pending 2 of 3' && ok "T7 --brief STATE: manual steps pending 2 of 3" || bad "T7 --brief manual count" "$b"
f="$("$NEW" "$E" 2>&1)"
printf '%s\n' "$f" | grep -qF 'manual steps pending 2 of 3 (docs/manual-steps.md)' && ok "T7 full screen: manual count with its file" || bad "T7 full manual count" "$f"

# --- T8: the shipped template counts nothing ------------------------------------------------
cp "$W/tk/templates/manual-steps.md" "$E2/docs/manual-steps.md" 2>/dev/null
b="$("$NEW" "$E2" --brief 2>&1)"
printf '%s\n' "$b" | grep -qF 'manual steps pending 0 of 0' && ok "T8 template copied as-is: 0 of 0" || bad "T8 template count" "$b"

# --- T9: NEXT never names an obligation owed only at a later stage (review of #303) ----------
# A scaffold always has gate-check "Needs attention" items, which win NEXT before the obligation
# rule is reached. tk2's gate-check.sh runs the REAL gate-check and drops only that block and its
# count, so the obligation lines status.sh reads are real output, not typed here.
mkdir -p "$W/tk2"; (cd "$W/tk" && tar -cf - .) | (cd "$W/tk2" && tar -xf -)
mv "$W/tk2/bin/gate-check.sh" "$W/tk2/bin/gate-check-real.sh"
cat > "$W/tk2/bin/gate-check.sh" <<'WRAP'
#!/usr/bin/env bash
"$(dirname "$0")/gate-check-real.sh" "$@" 2>/dev/null \
  | awk '/^Needs attention/{s=1;next} /^Next up:|^Approved over a failing gate:/{s=0} !s' \
  | sed -E 's/[0-9]+ need attention/0 need attention/'
WRAP
chmod +x "$W/tk2/bin/gate-check.sh"
P9="$W/ob"; mkdir -p "$P9"; : > "$P9/Fixture.mpr"; "$W/tk2/bin/init-project.sh" "$P9" >/dev/null 2>&1
setstage() { awk -v st="$2" '/^## Current stage/{print; getline; print ""; getline; print st; next} {print}' "$1/PROJECT.md" > "$1/p.new" && mv "$1/p.new" "$1/PROJECT.md"
             grep -q '^Entry mode:' "$1/PROJECT.md" || printf '\nEntry mode: migration\n' >> "$1/PROJECT.md"; }
nextof() { "$1" "$2" --brief 2>/dev/null | sed -n 's/^NEXT    //p'; }
setstage "$P9" "**Stage 3 — Architecture & Design**, in progress."
grep -q '^\*\*Stage 3' "$P9/PROJECT.md" || bad "T9 setup: stage line not written" "$(sed -n '1,15p' "$P9/PROJECT.md")"
n="$(nextof "$W/tk2/bin/status.sh" "$P9")"
case "$n" in "discharge:"*) ok "T9 Stage 3: NEXT still discharges what is owed now";; *) bad "T9 Stage 3: expected a discharge NEXT" "$n";; esac
case "$n" in *final-look*|*skeleton*|*coherence*) bad "T9 Stage 3: NEXT names an obligation first owed at Stage 5/6" "$n";; *) ok "T9 Stage 3: no Stage 5/6 obligation in NEXT";; esac
case "$n" in *workflow-count*) ok "T9 Stage 3: a Stage 3 obligation stays in NEXT";; *) bad "T9 Stage 3: Stage 3 obligation dropped" "$n";; esac
f="$("$W/tk2/bin/status.sh" "$P9" 2>/dev/null)"
printf '%s\n' "$f" | grep -q 'obligations pending:.*final-look' && ok "T9 the screen still lists final-look under obligations pending" || bad "T9 obligations pending line lost final-look" "$f"
setstage "$P9" "**Stage 1 — Analysis**, in progress."
n="$(nextof "$W/tk2/bin/status.sh" "$P9")"
case "$n" in "discharge:"*) bad "T9 Stage 1: every pending obligation is above Stage 1, NEXT should fall through" "$n";; *) ok "T9 Stage 1: NEXT is not a discharge line (falls through to the later rules)";; esac
if [ "$HAVE_BASE" = 1 ]; then
  cp "$OLD" "$W/tk2/bin/status-baseline.sh"
  o="$(nextof "$W/tk2/bin/status-baseline.sh" "$P9")"
  case "$o" in *final-look*) ok "T9 control: the baseline told a Stage 1 project to discharge final-look";; *) bad "T9 control: baseline did not name final-look — case cannot fail" "$o";; esac
fi

echo "SCORE: $PASS/$((PASS+FAIL))"
[ "$FAIL" -eq 0 ]
