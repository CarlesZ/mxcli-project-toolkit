#!/usr/bin/env bash
# Fixture for #358: close-task.sh must resolve checkpoint.sh, never print it bare.
#
# usage: test-close-task-checkpoint.sh /path/to/project-bin/close-task.sh
#
# checkpoint.sh lives in the toolkit at claude-hooks/bin/ and reaches ~/.claude/bin only via
# the opt-in `bin/install-claude-hooks.sh --basic`. The old "### Then" block printed
# `checkpoint.sh --write` unconditionally, so a project without the hooks got a command that
# did not exist. Lookup order: PATH, ~/.claude/bin, $MXTK_ROOT/claude-hooks/bin.
#
# T1  found on PATH          -> prints that full path
# T2  found in ~/.claude/bin -> prints that full path (fake HOME)
# T3  found in toolkit       -> prints $MXTK_ROOT/claude-hooks/bin/checkpoint.sh
# T4  PATH beats ~/.claude/bin and toolkit
# T5  not found              -> install pointer, rest of the block still printed,
#                               exit code unchanged (0 on a clean project)
# T6  not found, writes owed -> still exit 1 (owed-write semantics kept)

set -uo pipefail

SUT="${1:?usage: test-close-task-checkpoint.sh /path/to/project-bin/close-task.sh}"
case "$SUT" in /*) ;; *) SUT="$PWD/$SUT" ;; esac
[ -f "$SUT" ] || { echo "no such file: $SUT" >&2; exit 2; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

pass=0; fail=0
ok()  { pass=$((pass+1)); echo "  PASS $1"; }
bad() { fail=$((fail+1)); echo "  FAIL $1"; [ -n "${2:-}" ] && printf '%s\n' "$2" | sed 's/^/       | /'; }

# A project that is not a git repo, with the script installed as bin/close-task.sh (no
# toolkit next to it, so the "installed-from" fallback cannot resolve a toolkit root).
PROJ="$TMP/proj"; mkdir -p "$PROJ/bin"
cp "$SUT" "$PROJ/bin/close-task.sh"; chmod +x "$PROJ/bin/close-task.sh"

# A clean PATH: system tools only, no checkpoint.sh.
SYSPATH="/usr/bin:/bin"
mk_ckpt() { mkdir -p "$1"; printf '#!/bin/sh\nexit 0\n' > "$1/checkpoint.sh"; chmod +x "$1/checkpoint.sh"; }

EMPTYHOME="$TMP/home-empty"; mkdir -p "$EMPTYHOME"
NOTK="$TMP/no-toolkit"; mkdir -p "$NOTK"

run() { # $1=HOME $2=PATH $3=MXTK_ROOT [args...]
  local h="$1" p="$2" m="$3"; shift 3
  ( cd "$PROJ" && env -i HOME="$h" PATH="$p" MXTK_ROOT="$m" GIT_CEILING_DIRECTORIES="$TMP" \
      bash "$PROJ/bin/close-task.sh" "$@" 2>&1 )
}

echo "T1 found on PATH"
mk_ckpt "$TMP/pathbin"
out=$(run "$EMPTYHOME" "$TMP/pathbin:$SYSPATH" "$NOTK")
grep -qF "    $TMP/pathbin/checkpoint.sh --write" <<<"$out" && ok "T1 prints PATH hit" || bad "T1 prints PATH hit" "$(grep -n -A2 '### Then' <<<"$out")"

echo "T2 found in ~/.claude/bin"
H2="$TMP/home2"; mk_ckpt "$H2/.claude/bin"
out=$(run "$H2" "$SYSPATH" "$NOTK")
grep -qF "    $H2/.claude/bin/checkpoint.sh --write" <<<"$out" && ok "T2 prints ~/.claude/bin hit" || bad "T2 prints ~/.claude/bin hit" "$(grep -n -A2 '### Then' <<<"$out")"

echo "T3 found in toolkit claude-hooks/bin"
TK="$TMP/toolkit"; mk_ckpt "$TK/claude-hooks/bin"
out=$(run "$EMPTYHOME" "$SYSPATH" "$TK")
grep -qF "    $TK/claude-hooks/bin/checkpoint.sh --write" <<<"$out" && ok "T3 prints toolkit hit" || bad "T3 prints toolkit hit" "$(grep -n -A2 '### Then' <<<"$out")"

echo "T4 lookup order"
out=$(run "$H2" "$TMP/pathbin:$SYSPATH" "$TK")
grep -qF "    $TMP/pathbin/checkpoint.sh --write" <<<"$out" && ok "T4a PATH wins" || bad "T4a PATH wins" "$(grep -n -A2 '### Then' <<<"$out")"
out=$(run "$H2" "$SYSPATH" "$TK")
grep -qF "    $H2/.claude/bin/checkpoint.sh --write" <<<"$out" && ok "T4b ~/.claude/bin beats toolkit" || bad "T4b ~/.claude/bin beats toolkit" "$(grep -n -A2 '### Then' <<<"$out")"

echo "T5 not found"
out=$(run "$EMPTYHOME" "$SYSPATH" "$NOTK"); rc=$?
grep -qF "checkpoint.sh not installed — run $NOTK/bin/install-claude-hooks.sh --basic, or skip: RESUME.md is the resume source" <<<"$out" \
  && ok "T5a install pointer printed" || bad "T5a install pointer printed" "$(grep -n -A2 '### Then' <<<"$out")"
grep -qE '^ +checkpoint\.sh --write' <<<"$out" && bad "T5b no bare checkpoint.sh line" "$(grep -n 'checkpoint.sh --write' <<<"$out")" || ok "T5b no bare checkpoint.sh line"
grep -qF 'OVERWRITE docs/progress/RESUME.md' <<<"$out" && grep -qF 'Shared toolkit:' <<<"$out" \
  && ok "T5c rest of the block still printed" || bad "T5c rest of the block still printed"
[ "$rc" = 0 ] && ok "T5d exit 0 on a clean project" || bad "T5d exit 0 on a clean project (got $rc)"

echo "T6 not found, writes owed"
run "$EMPTYHOME" "$SYSPATH" "$NOTK" --add "exec 010-foo.mdl" >/dev/null
out=$(run "$EMPTYHOME" "$SYSPATH" "$NOTK"); rc=$?
[ "$rc" = 1 ] && ok "T6 exit 1 when writes owed" || bad "T6 exit 1 when writes owed (got $rc)"

echo
echo "test-close-task-checkpoint: $pass passed, $fail failed"
[ "$fail" = 0 ]
