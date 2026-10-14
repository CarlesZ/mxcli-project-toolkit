#!/usr/bin/env bash
# test-build-plan-status-args.sh — project-bin/build-plan-status.sh takes flags and the path in any order.
#
# Usage: bash tests/wave2/test-build-plan-status-args.sh /path/to/build-plan-status.sh
#
# WHY (field report via PR #309, 2026-10-13): `$1` was read as the path, fell back to the git top
# level when it was a flag, then `shift` ran unconditionally. So `--json <root>` threw --json away
# and refused the real path ("unknown arg: <root>", exit 2), and the quiet variant — `--json` alone
# from inside a project — printed the table and silently wrote no build-plan.json.
#
# Covers: --json before the path writes the JSON (exit 0); --quiet before the path is quiet (exit
# 0); --json alone from inside the project writes the JSON; the documented path-first form still
# works; an unknown --flag still exits 2 naming it; a second path exits 2 instead of being ignored.
set -uo pipefail

SCRIPT="${1:?usage: bash tests/wave2/test-build-plan-status-args.sh /path/to/build-plan-status.sh}"
case "$SCRIPT" in /*) ;; *) SCRIPT="$PWD/$SCRIPT" ;; esac
WORK="$(mktemp -d "${TMPDIR:-/tmp}/bps-args.XXXXXX")"
WORK="$(cd "$WORK" && pwd -P)"
trap 'rm -rf "$WORK"' EXIT

# shellcheck disable=SC1091
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/bin/lib/portable.sh"
PY="$(resolve_py 2>/dev/null || true)"
[ -n "$PY" ] || { echo "SKIP: no Python 3 found; --json needs one."; echo "PASS=0 FAIL=0"; exit 0; }

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; [ -n "${2:-}" ] && printf '%s\n' "$2" | sed 's/^/  FAIL-detail: /'; }

new_project() {
  local p="$WORK/$1"
  mkdir -p "$p/architecture"
  ( cd "$p" && git init -q . )
  cat > "$p/architecture/build-plan.md" <<'MD'
# Build Plan

### Phase 1 — Home

| # | Kind | Step | Produces/Proves | Depends on | Skills | State |
|---|---|---|---|---|---|---|
| 1.1 | BUILD | `mdlsource/01-home.mdl` | home page | — | create-page | not built |
MD
  echo "$p"
}
JSON=architecture/build-plan.json

P="$(new_project flag-first)"
OUT="$(cd "$WORK" && bash "$SCRIPT" --json "$P" 2>&1)"; RC=$?
if [ "$RC" -eq 0 ] && [ -s "$P/$JSON" ]; then ok "--json <path>: exit 0, build-plan.json written"
else bad "--json <path> (rc=$RC, json=$([ -s "$P/$JSON" ] && echo yes || echo no))" "$OUT"; fi

P="$(new_project quiet-first)"
OUT="$(cd "$WORK" && bash "$SCRIPT" --quiet "$P" 2>&1)"; RC=$?
if [ "$RC" -eq 0 ] && [ -z "$OUT" ]; then ok "--quiet <path>: exit 0, nothing on stdout"
else bad "--quiet <path> (rc=$RC)" "$OUT"; fi

P="$(new_project flag-only)"
OUT="$(cd "$P" && bash "$SCRIPT" --json 2>&1)"; RC=$?
if [ "$RC" -eq 0 ] && [ -s "$P/$JSON" ]; then ok "--json alone inside the project: build-plan.json written"
else bad "--json alone (rc=$RC, json=$([ -s "$P/$JSON" ] && echo yes || echo no)) — the silent variant" "$OUT"; fi

P="$(new_project path-first)"
OUT="$(cd "$WORK" && bash "$SCRIPT" "$P" --json --quiet 2>&1)"; RC=$?
if [ "$RC" -eq 0 ] && [ -s "$P/$JSON" ]; then ok "<path> --json --quiet (documented order) still works"
else bad "<path> --json --quiet (rc=$RC)" "$OUT"; fi

P="$(new_project unknown)"
OUT="$(cd "$WORK" && bash "$SCRIPT" "$P" --bogus 2>&1)"; RC=$?
if [ "$RC" -eq 2 ] && printf '%s' "$OUT" | grep -q 'unknown arg: --bogus'; then ok "unknown --flag: exit 2, named"
else bad "unknown --flag (rc=$RC)" "$OUT"; fi

P="$(new_project twopaths)"
OUT="$(cd "$WORK" && bash "$SCRIPT" "$P" "$WORK/elsewhere" 2>&1)"; RC=$?
if [ "$RC" -eq 2 ] && printf '%s' "$OUT" | grep -q 'unexpected second path'; then ok "second path: exit 2, not silently ignored"
else bad "second path (rc=$RC)" "$OUT"; fi

printf '\n%s: %d passed, %d failed\n' "$(basename "$0")" "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
