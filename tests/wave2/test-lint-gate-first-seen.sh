#!/usr/bin/env bash
# Fixture for project-bin/lint-gate.sh FIRST-SEEN handling and exec.sh's row for it.
#
# Usage: bash test-lint-gate-first-seen.sh [path-to-lint-gate.sh]
#
# Review of #305 (Lint Batch 3), 2026-10-13: a rule sync-project.sh installs after the baseline
# has no baseline count, so lint-gate compared it against 0 and its first hit was a "rise" —
# every exec logged LINT ROSE and exited 1 until someone re-baselined, and TXT001/TXT002 fire on
# ordinary text (TBD, XXX, v1.2, "12 Oct 2026"). Now such a rule is FIRST-SEEN: reported, rc 0.
#
# Rules under test are the toolkit's real .star files (their `RULE_ID = "..."` line is what
# lint-gate reads). Lint output goes through LINT_JSON, using the key set of a real
# `mxcli lint --format json` capture (same builder as test-lint-gate-accept.sh). No mxcli/.mpr.
set -uo pipefail
TK="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
GATE="${1:-$TK/project-bin/lint-gate.sh}"
EXEC="$TK/project-bin/exec.sh"
. "$TK/bin/lib/portable.sh"
require_py
WORK="$(mktemp -d "${TMPDIR:-/tmp}/lint-first-seen.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; [ -n "${2:-}" ] && printf '%s\n' "$2" | sed 's/^/       /'; }

P="$WORK/proj"; mkdir -p "$P/bin" "$P/.claude/lint-rules"
cp "$GATE" "$P/bin/lint-gate.sh"; [ -f "$TK/project-bin/_common.sh" ] && cp "$TK/project-bin/_common.sh" "$P/bin/"
printf 'mpr' > "$P/App.mpr"; printf '#!/bin/sh\nexit 0\n' > "$P/mxcli"; chmod +x "$P/mxcli" "$P/bin/lint-gate.sh"
R="$P/.claude/lint-rules"
cp "$TK/lint-rules/conv010_act_microflow_content.star" "$TK/lint-rules/ux001_confirm_before_destructive.star" "$R/"

v() { i=0; while [ "$i" -lt "$3" ]; do
  printf '{"ruleId":"%s","severity":"%s","message":"finding %s","module":"Orders","document":"Doc%s","documentType":"microflow","documentId":"id-%s-%s","suggestion":"s"},' \
    "$1" "$2" "$i" "$i" "$1" "$i"; i=$((i+1)); done; }
mk() { printf '{"violations":[%s{"ruleId":"MPR001","severity":"warning","message":"m","module":"Orders","document":"E","documentType":"entity","documentId":"x","suggestion":"s"}],"summary":{}}' "$1" > "$WORK/lint.json"; }
gate() { (cd "$P" && LINT_JSON="$WORK/lint.json" bash bin/lint-gate.sh "$@"); }
fn="$WORK/run_lint_gate.sh"; sed -n '/^run_lint_gate() {/,/^}/p' "$EXEC" > "$fn"
exec_detail() { (cd "$P" && PROJECT_ROOT="$P" LINT_JSON="$WORK/lint.json" bash -c ". '$fn'; LINT_RC=0; run_lint_gate >/dev/null; echo \"\$LINT_RC|\$LINT_DETAIL\""); }
verdict() { "$PY" -c 'import json,sys;print(json.load(open(sys.argv[1]))["verdict"])' "$P/.claude/loop/lint-last.json"; }

echo "F0 baseline before the new rule is installed (UX001 installed, zero findings)"
mk "$(v CONV010 warning 4)$(v CONV009 info 2)"
out=$(gate --update-baseline 2>&1); rc=$?
[ "$rc" -eq 0 ] && ok "baseline written" || bad "rc=$rc" "$out"
"$PY" -c 'import json,sys;d=json.load(open(sys.argv[1]));sys.exit(0 if d.get("star_rules")==["CONV010","UX001"] else 1)' "$P/.claude/lint-baseline.json" \
  && ok "baseline records star_rules [CONV010, UX001]" || bad "star_rules wrong" "$(cat "$P/.claude/lint-baseline.json")"

echo "F1 sync installs TXT001; its findings are FIRST-SEEN, rc 0"
cp "$TK/lint-rules/txt001_build_words_in_user_text.star" "$R/"
mk "$(v CONV010 warning 4)$(v CONV009 info 2)$(v TXT001 info 5)"
out=$(gate 2>&1); rc=$?
[ "$rc" -eq 0 ] && ok "rc 0" || bad "first-seen rule treated as a failure (rc $rc)" "$out"
case "$out" in *"FIRST-SEEN TXT001"*"5 finding(s) — new rule, first seen: review and re-baseline with --reason"*) ok "first-seen line names TXT001 and its count" ;; *) bad "no first-seen line" "$out" ;; esac
case "$out" in *"FAIL —"*) bad "reported as a rise" "$out" ;; *) ok "not reported as a rise" ;; esac
[ "$(verdict)" = PASS-FIRST-SEEN ] && ok "lint-last verdict PASS-FIRST-SEEN" || bad "verdict $(verdict)"
d=$(exec_detail)
case "$d" in "0|lint unchanged vs baseline; FIRST-SEEN: TXT001 (5)"*) ok "exec row: ${d#*|}" ;; *) bad "exec row does not carry FIRST-SEEN" "$d" ;; esac

echo "F2 an existing rule rising next to it is still a rise"
mk "$(v CONV010 warning 6)$(v CONV009 info 2)$(v TXT001 info 5)"
out=$(gate 2>&1); rc=$?
[ "$rc" -eq 1 ] && ok "rc 1" || bad "rc=$rc" "$out"
case "$out" in *"CONV010  warning  4 -> 6"*) ok "CONV010 4 -> 6 reported" ;; *) bad "rise missing" "$out" ;; esac
case "$(printf '%s\n' "$out" | sed -n '/^FAIL/,$p')" in *TXT001*) bad "TXT001 listed among the rises" "$out" ;; *) ok "TXT001 not listed as a rise" ;; esac

echo "F3 a built-in rule absent from the baseline (was clean) is a rise, not first-seen"
mk "$(v CONV010 warning 4)$(v CONV009 info 2)$(v MDL001 info 1)"
out=$(gate 2>&1); rc=$?
[ "$rc" -eq 1 ] && case "$out" in *"MDL001"*"0 -> 1"*) true ;; *) false ;; esac && ok "MDL001 0 -> 1 is a rise" || bad "built-in hit not a rise (rc $rc)" "$out"

echo "F4 a .star rule known at baseline with zero findings is a rise when it fires"
mk "$(v CONV010 warning 4)$(v CONV009 info 2)$(v UX001 warning 1)"
out=$(gate 2>&1); rc=$?
[ "$rc" -eq 1 ] && case "$out" in *"UX001"*"0 -> 1"*) true ;; *) false ;; esac && ok "UX001 0 -> 1 is a rise" || bad "known clean rule not ratcheted (rc $rc)" "$out"

echo "F5 re-baselining a first-seen rule needs --reason; afterwards it is a normal rule"
mk "$(v CONV010 warning 4)$(v CONV009 info 2)$(v TXT001 info 5)"
out=$(gate --update-baseline 2>&1); rc=$?
[ "$rc" -eq 2 ] && ok "refused without --reason" || bad "accepted without a reason (rc $rc)" "$out"
out=$(gate --update-baseline --reason "TXT001 reviewed: 5 placeholder labels, fixed in slice 4" 2>&1); rc=$?
[ "$rc" -eq 0 ] && ok "accepted with --reason" || bad "rc=$rc" "$out"
mk "$(v CONV010 warning 4)$(v CONV009 info 2)$(v TXT001 info 7)"
out=$(gate 2>&1); rc=$?
[ "$rc" -eq 1 ] && case "$out" in *"TXT001"*"5 -> 7"*) true ;; *) false ;; esac && ok "TXT001 5 -> 7 is now a rise" || bad "baselined rule not ratcheted (rc $rc)" "$out"

echo "F6 a baseline written before star_rules existed: file mtime decides"
"$PY" - "$P/.claude/lint-baseline.json" <<'PY'
import json,sys
d=json.load(open(sys.argv[1])); d.pop("star_rules",None); d["counts"].pop("TXT001",None)
json.dump(d,open(sys.argv[1],"w"))
PY
"$PY" -c 'import os,sys,time;t=time.time();os.utime(sys.argv[1],(t-3600,t-3600));os.utime(sys.argv[2],(t-60,t-60));os.utime(sys.argv[3],(t-7200,t-7200))' \
  "$P/.claude/lint-baseline.json" "$R/txt001_build_words_in_user_text.star" "$R/ux001_confirm_before_destructive.star"
mk "$(v CONV010 warning 4)$(v CONV009 info 2)$(v TXT001 info 3)"
out=$(gate 2>&1); rc=$?
[ "$rc" -eq 0 ] && case "$out" in *"FIRST-SEEN TXT001"*) true ;; *) false ;; esac && ok "star newer than baseline -> first-seen" || bad "legacy newer star not first-seen (rc $rc)" "$out"
mk "$(v CONV010 warning 4)$(v CONV009 info 2)$(v UX001 warning 1)"
out=$(gate 2>&1); rc=$?
[ "$rc" -eq 1 ] && ok "star older than baseline -> rise" || bad "legacy older star not ratcheted (rc $rc)" "$out"

echo ""
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
