#!/usr/bin/env bash
# Fixture for bin/lib/ritual-template.sh — the short CLAUDE.local.md session-start ritual (#288)
# and sync-project.sh's exact-match heal of the long one.
#
# Usage: bash test-ritual-slim.sh [path-to-sync-project.sh]
#
# The subject is sync-project.sh, the heal's caller (init-project.sh writes the new text); the lib
# is located next to it, at lib/ritual-template.sh.
#
# Golden input (field-proof rule 1 — captured, never hand-written): fixtures/ritual-slim/
# CLAUDE.local.before.md is the verbatim CLAUDE.local.md that bin/init-project.sh on master
# (3a54675) wrote into a fresh scaffold, with the toolkit path replaced by @@TOOLKIT@@ so the
# fixture runs from any clone location.

set -uo pipefail

SYNC="${1:-}"
if [ -z "$SYNC" ]; then
  SYNC="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/bin/sync-project.sh"
fi
case "$SYNC" in /*) ;; *) SYNC="$PWD/$SYNC" ;; esac
BIN="$(dirname "$SYNC")"
SUT="$BIN/lib/ritual-template.sh"
if [ ! -f "$SUT" ]; then
  echo "SKIP: subject not found at $SUT (pre-change baseline has no ritual template)"
  echo "SCORE: 0/0 — nothing to test"
  exit 0
fi
GOLD="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fixtures/ritual-slim/CLAUDE.local.before.md"

PASS=0; FAIL=0
ok()   { PASS=$((PASS+1)); echo "  ok   — $1"; }
bad()  { FAIL=$((FAIL+1)); echo "  FAIL — $1"; [ -n "${2:-}" ] && echo "         got: $2"; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/ritualtest.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
TK="/opt/some clone/mxcli-project-toolkit"   # a space, on purpose: paths are not regex-safe

mk() { sed "s#@@TOOLKIT@@#$TK#g" "$GOLD" > "$1"; }
heal() { ( . "$SUT"; mxtk_ritual_heal "$1" "${2:-0}" ); }
section() { awk '/^## Session-start ritual/{p=1; print; next} p && /^## /{p=0} p' "$1"; }   # $(...) drops the trailing blank line
outside() { awk '/^## Session-start ritual/{p=1; next} p && /^## /{p=0} !p' "$1"; }

echo "T1 the captured old section heals to exactly the new text"
F="$TMP/t1.md"; mk "$F"; outside "$F" > "$TMP/t1.outside.before"
if heal "$F"; then ok "heal reported a change"; else bad "heal reported nothing to do on the golden input"; fi
want="$( . "$SUT"; mxtk_ritual_new "$TK")"
got="$(section "$F")"
[ "$got" = "$want" ] && ok "section equals mxtk_ritual_new" || bad "section differs from mxtk_ritual_new" "$(printf '%s' "$got" | head -3)"
outside "$F" > "$TMP/t1.outside.after"
cmp -s "$TMP/t1.outside.before" "$TMP/t1.outside.after" && ok "every other line byte-identical" || bad "lines outside the section changed"
grep -q -- '--approved-in-chat' "$F" && bad "ack procedure still in the always-loaded file" || ok "ack procedure no longer in the always-loaded file"
grep -qF "$TK/bin/gate-check.sh <project-root>\`" "$F" && ok "points at gate-check with the file's own toolkit path" || bad "gate-check pointer missing or path lost"
a=$(wc -c < "$F"); o=$(sed "s#@@TOOLKIT@@#$TK#g" "$GOLD" | wc -c)
[ "$a" -lt "$o" ] && ok "file shrank: $o -> $a bytes" || bad "file did not shrink ($o -> $a)"

echo "T2 idempotent"
cp "$F" "$TMP/t2.md"
if heal "$TMP/t2.md"; then bad "second heal reported a change"; else ok "second heal is a no-op"; fi
cmp -s "$F" "$TMP/t2.md" && ok "file unchanged" || bad "second heal changed the file"

echo "T3 a hand-edited section is left alone"
F="$TMP/t3.md"; mk "$F"
sed 's/There is no env-var auto-yes\./There is no env-var auto-yes, ever./' "$F" > "$F.x" && mv "$F.x" "$F"
cp "$F" "$TMP/t3.orig"
if heal "$F"; then bad "healed an edited section"; else ok "edited section not healed"; fi
cmp -s "$F" "$TMP/t3.orig" && ok "edited file untouched" || bad "edited file changed"

echo "T4 dry run reports and writes nothing"
F="$TMP/t4.md"; mk "$F"; cp "$F" "$TMP/t4.orig"
if heal "$F" 1; then ok "dry run reports the heal"; else bad "dry run reported nothing"; fi
cmp -s "$F" "$TMP/t4.orig" && ok "dry run wrote nothing" || bad "dry run changed the file"

echo "T5 section at end of file (no heading after it)"
F="$TMP/t5.md"; mk "$TMP/t5.full"
awk '/^## The toolkit is the process authority/{exit} {print}' "$TMP/t5.full" > "$F"
if heal "$F"; then ok "healed at EOF"; else bad "did not heal a trailing section"; fi
[ "$(section "$F")" = "$want" ] && ok "trailing section equals the new text" || bad "trailing section wrong"

echo "T6 callers are wired"
grep -q 'mxtk_ritual_heal' "$SYNC" && ok "sync-project.sh calls the heal" || bad "sync-project.sh never calls mxtk_ritual_heal"
grep -q 'mxtk_ritual_new' "$BIN/init-project.sh" && ok "init-project.sh writes the new text" || bad "init-project.sh does not use mxtk_ritual_new"
# The cut is only safe while gate-check's own notice still carries the agent procedure.
grep -q 'If you are an agent: run' "$BIN/gate-check.sh" && grep -q 'ack-protocol --approved-in-chat' "$BIN/gate-check.sh" \
  && ok "gate-check's notice still carries the ack procedure the ritual now defers to" \
  || bad "gate-check no longer prints the ack procedure — the short ritual points at nothing"

echo ""
echo "PASS=$PASS FAIL=$FAIL"
echo "SCORE: $PASS/$((PASS+FAIL))"
[ "$FAIL" -eq 0 ]
