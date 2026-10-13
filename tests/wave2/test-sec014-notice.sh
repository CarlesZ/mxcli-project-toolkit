#!/usr/bin/env bash
# Fixture for bin/lib/sec014-notice.sh and its one caller, bin/sync-project.sh: an installed
# SEC014 with no `external_roles` in .claude/lint-config.yaml is reported once per sync, as a
# sync warning, instead of as a `_rule` blindness finding that would fail every exec (#229
# pattern; review of PR #312).
#
# Usage: bash test-sec014-notice.sh [path-to-sync-project.sh]
#
# The lint-config.yaml bodies below start from the file `mxcli init` writes (v0.26.0, captured
# 2026-10-13 into an empty directory): its `rules: {}` and the commented CONV009 example. A
# commented `# external_roles:` must not count as configured.
# Keep bash-3.2 compatible.

set -uo pipefail
SYNC="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/bin/sync-project.sh}"
case "$SYNC" in /*) ;; *) SYNC="$PWD/$SYNC" ;; esac
SUT="$(dirname "$SYNC")/lib/sec014-notice.sh"

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  ok   — $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL — $1"; [ -n "${2:-}" ] && echo "         got: $2"; }

if [ ! -f "$SUT" ]; then
  bad "bin/lib/sec014-notice.sh missing — nothing tells a project SEC014 is unconfigured"
  echo "PASS=$PASS FAIL=$FAIL"; exit 1
fi

TMP="$(mktemp -d "${TMPDIR:-/tmp}/sec014n.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
STOCK_CFG='# mxcli lint configuration.
excludeModules:
  - System

# Per-rule overrides. Examples:
#
# rules:
#   CONV009:            # max microflow objects
#     severity: warning
#     options:
#       maxObjects: 20
rules: {}
'
mkp() { # name, install-rule(0/1), config-text-or-NONE
  d="$TMP/$1"; mkdir -p "$d/.claude/lint-rules"
  [ "$2" = 1 ] && : > "$d/.claude/lint-rules/sec014_external_role_write.star"
  [ "$3" != NONE ] && printf '%s' "$3" > "$d/.claude/lint-config.yaml"
  echo "$d"
}
notice() { ( . "$SUT"; mxtk_sec014_notice "$1" ); }

echo "== the notice =="
p=$(mkp a 1 "$STOCK_CFG"); out=$(notice "$p"); rc=$?
[ $rc -eq 0 ] && ok "a rule installed, stock config -> notice owed" || bad "a no notice (rc=$rc)"
case "$out" in *"rules:"*"SEC014:"*"options:"*"external_roles:"*) ok "a notice shows the exact config path" ;; *) bad "a config path missing" "$out" ;; esac
case "$out" in *'"none"'*"user's answer"*"PROJECT.md"*) ok "a \"none\" is named as a user decision recorded in PROJECT.md" ;; *) bad "a none-is-a-decision missing" "$out" ;; esac
case "$out" in *"--update-baseline"*"--approved-in-chat"*) ok "a tells to re-baseline right after configuring" ;; *) bad "a re-baseline hint missing" "$out" ;; esac

p=$(mkp b 1 NONE); notice "$p" >/dev/null && ok "b rule installed, no lint-config.yaml -> notice owed" || bad "b no notice without a config file"
p=$(mkp c 1 "${STOCK_CFG}#   SEC014:
#     options:
#       external_roles: \"X\"
"); notice "$p" >/dev/null && ok "c commented external_roles does not count" || bad "c commented line counted as configured"
p=$(mkp d 1 'rules:
  SEC014:
    options:
      external_roles: "Partner"
'); out=$(notice "$p"); rc=$?
[ $rc -eq 1 ] && [ -z "$out" ] && ok "d external_roles set -> silent" || bad "d notice despite configuration" "$out"
p=$(mkp e 1 'rules:
  SEC014:
    options:
      external_roles: "none"
'); notice "$p" >/dev/null && bad "e \"none\" still nagged" || ok "e \"none\" (a recorded decision) -> silent"
p=$(mkp f 0 "$STOCK_CFG"); notice "$p" >/dev/null && bad "f notice without the rule installed" || ok "f rule not installed -> silent"

echo "== wired into sync-project.sh =="
if grep -q 'lib/sec014-notice.sh' "$SYNC" && grep -q 'mxtk_sec014_notice "\$PROJECT_DIR"' "$SYNC"; then
  ok "sync-project.sh sources the lib and calls it"
else bad "sync-project.sh does not call mxtk_sec014_notice"; fi
# The call sits inside the WIRED lint block, after the rules are installed.
blk=$(awk '/mxtk_install_lint_rules "\$\(cd/{f=1} f{print} f&&/^fi$/{exit}' "$SYNC")
case "$blk" in *mxtk_sec014_notice*) ok "the call runs after mxtk_install_lint_rules, in the same WIRED block" ;; *) bad "the call is not in the lint install block" ;; esac
# Its output goes through warn(), so the sync counts it and does not end "all up to date".
case "$blk" in *"warn \$_sec014_msg"*) ok "the notice is a sync warning (counted, not just printed)" ;; *) bad "the notice bypasses warn()" ;; esac
bash -n "$SYNC" && ok "sync-project.sh parses" || bad "sync-project.sh does not parse"

echo
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
