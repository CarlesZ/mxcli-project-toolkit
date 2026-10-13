#!/usr/bin/env bash
# Usage: bash tests/wave2/test-obligation-final-look.sh [path-to-gate-check.sh | path-to-obligation-check.sh]
#
# test-obligation-final-look.sh — the `final-look` row in bin/lib/obligations.tsv: one whole-app
# LOOK report, owed last, re-owed after any later model commit.
#
# WHY (#283): on a 20-task UX-fix run over three apps (2026-10-12) a later task undid an earlier
# status fix on four pages. Every per-task review passed; only a read-only whole-app LOOK, run
# after the last task, found it — and nothing owed that pass. The row makes it owed; "final" is
# enforced by the existing VALID AT rule (_ob_stale), not by new code.
#
# Review of #303 (2026-10-13), T4-T10: the final LOOK owes the same PROOF-OF-LOOK lines as the
# per-module LOOK (module-review.md § "The final LOOK" requires them; only ob=look was checked);
# an unstamped final report is FAULT (with no VALID AT it could never go stale, so it would pass
# forever); and the row is NOT YET DUE until the register's Current stage reaches its from-stage
# (6) — it read PENDING from the day PROJECT.md existed. Module rows keep their verdicts.
# Subject: obligation-check.sh. Producer of the report: module-review.md § "The final LOOK".
set -uo pipefail
ARG="${1:?usage: test-obligation-final-look.sh /path/to/bin/gate-check.sh (or lib/obligation-check.sh)}"
case "$(basename "$ARG")" in
  obligation-check.sh) OBCHECK="$ARG" ;;
  *) OBCHECK="$(cd "$(dirname "$ARG")" && pwd)/lib/obligation-check.sh" ;;
esac
[ -r "$OBCHECK" ] || { echo "no obligation-check.sh at $OBCHECK"; exit 2; }
WORK="$(mktemp -d "${TMPDIR:-/tmp}/ob-final.XXXXXX")"
trap '[ -n "${KEEP:-}" ] || rm -rf "$WORK"' EXIT
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; }

P="$WORK/p"; mkdir -p "$P/architecture/modules/ModuleX" "$P/mdlsource" "$P/design/ui-reviews"
git -C "$P" init -q . 2>/dev/null
git -C "$P" config user.email t@t; git -C "$P" config user.name t
echo a > "$P/mdlsource/a.mdl"; git -C "$P" add mdlsource/a.mdl; git -C "$P" commit -qm one
OLD="$(git -C "$P" rev-parse --short HEAD)"
echo b >> "$P/mdlsource/a.mdl"; git -C "$P" commit -qam two
NEW="$(git -C "$P" rev-parse --short HEAD)"
REP="$P/design/ui-reviews/final-look-2026-10-12.html"
line()  { "$OBCHECK" "$P" 2>&1 | grep -E '^Obligation final-look ' | head -1; }
stale() { "$OBCHECK" "$P" 2>&1 | grep -E '^Obligation final-look ' | grep -c 'STALE'; }

echo "== T1: no report -> PENDING, owner review-agent =="
l="$(line)"
case "$l" in *PENDING*review-agent*) ok "no report is PENDING" ;; *) bad "expected PENDING, got: $l" ;; esac

echo "== T2: a per-module ui-review report does not discharge the final LOOK =="
printf '<p>ModuleX: 3 of 3 pages reviewed</p>\nVALID AT: %s\n' "$NEW" > "$P/design/ui-reviews/ui-review-2026-10-12.html"
l="$(line)"
case "$l" in *PENDING*) ok "module report ignored" ;; *) bad "module report discharged final-look: $l" ;; esac

echo "== T3: final-look report with no denominator -> FAULT =="
printf '<p>Whole app looked at, all fine.</p>\nVALID AT: %s\n' "$NEW" > "$REP"
l="$(line)"
case "$l" in *FAULT*DENOMINATOR*) ok "no denominator is FAULT" ;; *) bad "expected FAULT, got: $l" ;; esac

mkdir -p "$P/design/ui-reviews/shots"
head -c 20000 /dev/urandom > "$P/design/ui-reviews/shots/home.png"   # written after both commits
PROOF='<pre>PROOF-OF-LOOK: ModuleX.Home = shots/home.png</pre>'

echo "== T4: denominator, stamped at HEAD, proof on disk -> PASS =="
printf '<p>Final LOOK: 1 of 1 pages, 1 of 1 roles</p>\nVALID AT: %s\n%s\n' "$NEW" "$PROOF" > "$REP"
l="$(line)"
case "$l" in *PASS*) ok "current final LOOK is PASS" ;; *) bad "expected PASS, got: $l" ;; esac

echo "== T5: stamped before the last model commit -> owed again (STALE) =="
printf '<p>Final LOOK: 1 of 1 pages, 1 of 1 roles</p>\nVALID AT: %s\n%s\n' "$OLD" "$PROOF" > "$REP"
l="$(line)"
case "$l" in *PENDING*) ok "stale final LOOK is PENDING" ;; *) bad "expected PENDING, got: $l" ;; esac
[ "$(stale)" -gt 0 ] && ok "STALE line names it" || bad "no STALE line for final-look"

echo "== T6: stamped at HEAD, denominator, but no PROOF-OF-LOOK line -> FAULT =="
printf '<p>Final LOOK: 1 of 1 pages, 1 of 1 roles</p>\nVALID AT: %s\n' "$NEW" > "$REP"
l="$(line)"
case "$l" in *FAULT*PROOF-OF-LOOK*) ok "final LOOK without screenshots is FAULT" ;; *) bad "expected FAULT (no proof), got: $l" ;; esac

echo "== T7: denominator and proof but no VALID AT -> FAULT naming the stamp =="
printf '<p>Final LOOK: 1 of 1 pages, 1 of 1 roles</p>\n%s\n' "$PROOF" > "$REP"
l="$(line)"
case "$l" in *FAULT*"NO VALID AT"*) ok "unstamped final LOOK is FAULT" ;; *) bad "expected FAULT (no VALID AT), got: $l" ;; esac

echo "== T8: register at Stage 5 -> final-look NOT YET DUE (owed from 6) =="
rm -f "$REP"
printf '# PROJECT.md\n\n## Current stage\n\n**Stage 5 — Build**, in progress (derived by gate-check on 2026-10-13; re-run it rather than editing this line).\n' > "$P/PROJECT.md"
l="$(line)"
case "$l" in *"NOT YET DUE"*) ok "final-look not owed before stage 6" ;; *) bad "expected NOT YET DUE, got: $l" ;; esac

echo "== T9: register at Stage 6, or all gates passed -> owed (PENDING) =="
printf '# PROJECT.md\n\n## Current stage\n\n**Stage 6 — Test**, in progress.\n' > "$P/PROJECT.md"
l="$(line)"
case "$l" in *PENDING*) ok "owed at stage 6" ;; *) bad "expected PENDING at stage 6, got: $l" ;; esac
printf '# PROJECT.md\n\n## Current stage\n\n**All gates passed** — through Stage 7 (Cutover)\n' > "$P/PROJECT.md"
l="$(line)"
case "$l" in *PENDING*) ok "owed when all gates passed" ;; *) bad "expected PENDING after all gates, got: $l" ;; esac
printf '# PROJECT.md\n\n## Current stage\n\nWe are somewhere in the build.\n' > "$P/PROJECT.md"
l="$(line)"
case "$l" in *PENDING*) ok "unreadable stage keeps the old verdict (owed)" ;; *) bad "unreadable stage changed the verdict: $l" ;; esac

echo "== T10: module rows keep their verdicts at Stage P =="
mod() { "$OBCHECK" "$P" 2>&1 | grep -E '^Obligation (look|sweep|journeys|fidelity|dispatch) ' | sed -E 's/ +/ /g'; }
rm -f "$P/PROJECT.md"; before="$(mod)"
printf '# PROJECT.md\n\n## Current stage\n\n**Stage P — Kickoff**, in progress.\n' > "$P/PROJECT.md"
after="$(mod)"
[ -n "$before" ] && [ "$before" = "$after" ] && ok "module verdicts identical with and without a Stage P register" \
  || bad "module verdicts changed: before=[$before] after=[$after]"
l="$("$OBCHECK" "$P" 2>&1 | grep -E '^Obligation skeleton ')"
case "$l" in *"NOT YET DUE"*) ok "project row from stage 5 not due at Stage P" ;; *) bad "skeleton at Stage P: $l" ;; esac

echo "pass=$PASS fail=$FAIL"
[ "$FAIL" -eq 0 ]
