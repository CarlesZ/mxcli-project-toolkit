#!/usr/bin/env bash
# baseline-lock.sh — the shared lock behind every ratchet baseline a person must approve.
#
# WHY (#348, 2026-10-14). `lint-gate.sh --update-baseline` took `--approved-in-chat` as the
# proof that the user said yes. The agent whose script caused the rise could type that flag
# itself, so "re-baselining is the user's call" was honour-system. A baseline that LOOSENS now
# moves only against a row in .claude/baseline-approvals.tsv whose sha256 is the exact
# proposed content — a row only bin/baseline-approve.sh writes, from a terminal, after a person
# reads the change and types `approve`. The agent cannot write that row through its normal
# tools: bin/install-claude-permissions.sh denies `*baseline-approv*` in Bash and edits to the
# approvals file (deny beats allow and auto mode in Claude Code).
#
# WHAT IT DOES NOT PROTECT AGAINST, said plainly: an agent that deliberately evades the deny
# rules (obfuscated shell, a script that writes the row), a harness with no deny rules whose
# agent terminal is a real TTY, or someone deleting both ledgers. It turns "the agent typed a
# flag" into "the agent forged a record", which is visible in git and named by gate-check.
#
# Covered baselines (kind -> file, relative to the project root):
#   lint         .claude/lint-baseline.json     project-bin/lint-gate.sh
#   conformance  docs/conformance/baseline.tsv  project-bin/conformance-check.sh
#
# Records:
#   .claude/baseline-approvals.tsv  ts kind sha256 by note   — written ONLY by baseline-approve.sh
#   .claude/baseline-writes.tsv     ts kind sha256 basis     — every write an instrument made
#                                   (basis: first | tighten | seed | approved)
#   .claude/baseline-pending/<kind>[.summary]  the refused proposal, for the person to review
# Commit all three with the baseline.
#
# Usage (instruments and gate-check call it; a person never needs to):
#   baseline-lock.sh file     <kind>                         print the baseline path (relative)
#   baseline-lock.sh sha      <file>                         print sha256 of a file
#   baseline-lock.sh verify   <root> <kind>                  print STATE<TAB>note, exit 0
#       NONE    no baseline and no record                    (a first write needs no approval)
#       GONE    no baseline, but records exist               (re-creating it needs approval)
#       PASS    the file on disk matches an approval or a recorded instrument write
#       FAIL    it matches neither: it moved outside the instrument, or without approval
#       MANUAL  a baseline with no record at all — it predates this lock; unverifiable
#   baseline-lock.sh approved <root> <kind> <sha>            exit 0 iff an approval row matches
#   baseline-lock.sh record   <root> <kind> <sha> <basis>    append a write row
#   baseline-lock.sh propose  <root> <kind> <file> <summary> save the proposal, print the ask
#
# Producer of the records: the two instruments above (writes, proposals) and
# project-bin/baseline-approve.sh (approvals). Consumer: those instruments and
# bin/gate-check.sh's "Baselines" line (toolkit copy, run against the project root).
set -uo pipefail

APPROVALS=".claude/baseline-approvals.tsv"
WRITES=".claude/baseline-writes.tsv"

_file() {
  case "$1" in
    lint)        echo ".claude/lint-baseline.json" ;;
    conformance) echo "docs/conformance/baseline.tsv" ;;
    *) echo "baseline-lock: unknown kind '$1' (lint | conformance)" >&2; return 2 ;;
  esac
}

_sha() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1
  elif command -v shasum >/dev/null 2>&1; then shasum -a 256 "$1" | cut -d' ' -f1
  else openssl dgst -sha256 "$1" | sed 's/^.*= *//'
  fi
}

_has() {  # _has <tsv> <kind> <sha> — a row for this kind and hash
  [ -f "$1" ] && awk -F'\t' -v k="$2" -v s="$3" '$2==k && $3==s {f=1} END {exit !f}' "$1"
}
_any() {  # _any <tsv> <kind> — any row for this kind
  [ -f "$1" ] && awk -F'\t' -v k="$2" '$2==k {f=1} END {exit !f}' "$1"
}
_now() { date -u +%Y-%m-%dT%H:%M:%SZ; }

cmd="${1:-}"; [ $# -gt 0 ] && shift
case "$cmd" in
  file)
    _file "$1" ;;
  sha)
    _sha "$1" ;;
  verify)
    root="$1"; kind="$2"; f="$(_file "$kind")" || exit 2
    a="$root/$APPROVALS"; w="$root/$WRITES"
    if [ ! -f "$root/$f" ]; then
      if _any "$a" "$kind" || _any "$w" "$kind"; then
        printf 'GONE\t%s is missing but was recorded before — re-creating it needs a person: bin/baseline-approve.sh %s\n' "$f" "$kind"
      else
        printf 'NONE\tno %s baseline yet\n' "$kind"
      fi
      exit 0
    fi
    s="$(_sha "$root/$f")"
    if _has "$a" "$kind" "$s"; then
      printf 'PASS\t%s matches a human approval\n' "$f"
    elif _has "$w" "$kind" "$s"; then
      printf 'PASS\t%s matches a recorded write (%s)\n' "$f" \
        "$(awk -F'\t' -v k="$kind" -v s="$s" '$2==k && $3==s {b=$4} END {print b}' "$w")"
    elif _any "$a" "$kind" || _any "$w" "$kind"; then
      printf 'FAIL\t%s moved without approval (sha %s is in neither %s nor %s) — a person reviews it and runs: bin/baseline-approve.sh %s --current\n' \
        "$f" "$(printf '%s' "$s" | cut -c1-12)" "$APPROVALS" "$WRITES" "$kind"
    else
      printf 'MANUAL\t%s has no approval or write record (it predates the lock) — cannot tell who moved it; the next instrument write starts the record\n' "$f"
    fi
    exit 0 ;;
  approved)
    _has "$1/$APPROVALS" "$2" "$3" ;;
  record)
    root="$1"; mkdir -p "$root/.claude"
    [ -f "$root/$WRITES" ] || printf 'ts\tkind\tsha256\tbasis\n' > "$root/$WRITES"
    printf '%s\t%s\t%s\t%s\n' "$(_now)" "$2" "$3" "$4" >> "$root/$WRITES"
    rm -f "$root/.claude/baseline-pending/$2" "$root/.claude/baseline-pending/$2.summary" ;;
  propose)
    root="$1"; kind="$2"; src="$3"; summary="$4"
    d="$root/.claude/baseline-pending"; mkdir -p "$d"
    cp "$src" "$d/$kind" && printf '%s\n' "$summary" > "$d/$kind.summary"
    echo "" >&2
    echo "   Moving this baseline is the user's call, and a flag the agent can type is not their" >&2
    echo "   answer. Show the user the change above, then ask THEM to run, in their own terminal:" >&2
    echo "       bin/baseline-approve.sh $kind" >&2
    echo "   (it shows the proposal and asks them to type 'approve'). Agents: do not run it —" >&2
    echo "   it is denied to you and refuses without a terminal. Then re-run the same command." >&2
    ;;
  *)
    sed -n '2,45p' "$0"; exit 2 ;;
esac
