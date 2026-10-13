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

echo "== T4: denominator, stamped at HEAD -> PASS =="
printf '<p>Final LOOK: 38 of 38 pages, 4 of 4 roles</p>\nVALID AT: %s\n' "$NEW" > "$REP"
l="$(line)"
case "$l" in *PASS*) ok "current final LOOK is PASS" ;; *) bad "expected PASS, got: $l" ;; esac

echo "== T5: stamped before the last model commit -> owed again (STALE) =="
printf '<p>Final LOOK: 38 of 38 pages, 4 of 4 roles</p>\nVALID AT: %s\n' "$OLD" > "$REP"
l="$(line)"
case "$l" in *PENDING*) ok "stale final LOOK is PENDING" ;; *) bad "expected PENDING, got: $l" ;; esac
[ "$(stale)" -gt 0 ] && ok "STALE line names it" || bad "no STALE line for final-look"

echo "pass=$PASS fail=$FAIL"
[ "$FAIL" -eq 0 ]
