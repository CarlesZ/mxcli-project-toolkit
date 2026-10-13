#!/usr/bin/env bash
# test-restore-mpr-arg.sh — project-bin/restore-mpr.sh accepts what its usage line promises.
#
# Usage: bash tests/wave2/test-restore-mpr-arg.sh [path-to-restore-mpr.sh]
#
# WHY (field report via PR #309, 2026-10-13): the usage line said `[timestamp]`, and snapshot-mpr.sh
# names snapshots by timestamp, but the argument was used as given AFTER `cd "$MODEL_DIR"` — so
# `restore-mpr.sh 20261013-120000` failed with "snapshot ... is missing App.mpr" during a crash
# recovery, pointing the user at a healthy snapshot. Only the full path worked.
#
# Snapshots are made by the real producer (project-bin/snapshot-mpr.sh), never hand-built, on both
# layouts (model at the root; model under app/ — CLAUDE.md "Both layouts").
# Covers, per layout: bare timestamp restores; absolute path restores; no argument restores the
# newest; an unknown name exits 1 naming .mpr-snapshots and listing what exists — never "missing
# <mpr>". Plus: a path relative to the CALLER's directory resolves before the script's own cd.
set -uo pipefail

TOOLKIT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SUBJECT="${1:-$TOOLKIT/project-bin/restore-mpr.sh}"
case "$SUBJECT" in /*) ;; *) SUBJECT="$PWD/$SUBJECT" ;; esac
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  ok   — $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL — $1"; }
echo "== subject: $SUBJECT"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/restorearg.XXXXXX")" || exit 2
WORK="$(cd "$WORK" && pwd -P)"
trap 'rm -rf "$WORK"' EXIT

# $1 = project dir, $2 = model subdir ("" or "app")
mkproj() {
  local P="$1" M="$1${2:+/$2}"
  mkdir -p "$P/bin" "$M/mprcontents/aa"
  cp "$TOOLKIT/project-bin/_common.sh" "$TOOLKIT/project-bin/snapshot-mpr.sh" "$P/bin/"
  cp "$SUBJECT" "$P/bin/restore-mpr.sh"
  chmod +x "$P/bin/"*.sh
  printf 'index v2\n' > "$M/App.mpr"
  printf 'unit\n' > "$M/mprcontents/aa/one.mxunit"
  ( cd "$P" && git init -q . 2>/dev/null; PROJECT_ROOT="$P" ./bin/snapshot-mpr.sh >/dev/null 2>&1 )
  ls -d "$P/.mpr-snapshots"/*/ 2>/dev/null | head -1
}
dirty() { printf 'CHANGED\n' >> "$1/App.mpr"; }
clean() { [ "$(cat "$1/App.mpr")" = "index v2" ]; }

for layout in single two-tree; do
  echo "-- layout: $layout"
  P="$WORK/$layout"; sub=""; [ "$layout" = two-tree ] && sub="app"
  M="$P${sub:+/$sub}"
  SNAP="$(mkproj "$P" "$sub")"
  [ -n "$SNAP" ] || { bad "$layout: snapshot-mpr.sh produced no snapshot"; continue; }
  TS="$(basename "$SNAP")"

  dirty "$M"
  OUT="$(cd "$P" && PROJECT_ROOT="$P" ./bin/restore-mpr.sh "$TS" 2>&1)"; RC=$?
  if [ "$RC" -eq 0 ] && clean "$M"; then ok "$layout: bare timestamp '$TS' restores"
  else bad "$layout: bare timestamp failed (rc=$RC): $(printf '%s' "$OUT" | head -3)"; fi

  dirty "$M"
  OUT="$(cd "$P" && PROJECT_ROOT="$P" ./bin/restore-mpr.sh "$SNAP" 2>&1)"; RC=$?
  if [ "$RC" -eq 0 ] && clean "$M"; then ok "$layout: absolute snapshot path restores"
  else bad "$layout: absolute path failed (rc=$RC): $(printf '%s' "$OUT" | head -3)"; fi

  dirty "$M"
  OUT="$(cd "$P" && PROJECT_ROOT="$P" ./bin/restore-mpr.sh ".mpr-snapshots/$TS" 2>&1)"; RC=$?
  if [ "$RC" -eq 0 ] && clean "$M"; then ok "$layout: caller-relative '.mpr-snapshots/$TS' restores"
  else bad "$layout: caller-relative path failed (rc=$RC): $(printf '%s' "$OUT" | head -3)"; fi

  dirty "$M"
  OUT="$(cd "$P" && PROJECT_ROOT="$P" ./bin/restore-mpr.sh 2>&1)"; RC=$?
  if [ "$RC" -eq 0 ] && clean "$M"; then ok "$layout: no argument restores the newest"
  else bad "$layout: no-argument restore failed (rc=$RC): $(printf '%s' "$OUT" | head -3)"; fi

  dirty "$M"
  OUT="$(cd "$P" && PROJECT_ROOT="$P" ./bin/restore-mpr.sh 19990101-000000 2>&1)"; RC=$?
  if [ "$RC" -eq 1 ] && printf '%s' "$OUT" | grep -q "no snapshot named '19990101-000000'" \
     && printf '%s' "$OUT" | grep -q "$TS" && ! printf '%s' "$OUT" | grep -q 'is missing' && ! clean "$M"; then
    ok "$layout: unknown name exits 1, names it, lists '$TS', model untouched"
  else bad "$layout: unknown name (rc=$RC): $(printf '%s' "$OUT" | head -4)"; fi
done

printf '\n%s: %d passed, %d failed\n' "$(basename "$0")" "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
