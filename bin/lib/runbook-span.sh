#!/usr/bin/env bash
# runbook-span.sh — locate the runbook sections a stage session needs, by heading, never by a
# hard-coded line number. Source it; do not execute it.
#
# Callers: bin/gate-check.sh (the "Read for this gate" line), bin/runbook-slice.sh (prints the
# lines), bin/lib/skill-routing.sh (counts the slice's words for the per-role budget lines).
# One copy, so the three never disagree about where a section starts or ends.
#
# What a stage session needs is §1b (the Live Checklist Protocol, which applies to every stage)
# plus its own stage's section under §2. Stage headings are keyed on the " — " every one carries:
# "### Stage 0 runs in every entry mode" (under Entry Modes) also starts with "### Stage 0", and
# matched first without it.
#
# bash 3.2 (stock macOS) and POSIX awk.

# runbook_span <file> <start-regex> <end-regex> — "A–B" (1-based, inclusive) or ""
runbook_span() {
  awk -v h="$2" -v e="$3" '
    !start && $0 ~ h { start = NR; next }
    start && $0 ~ e   { end = NR - 1; exit }
    END { if (start) { if (!end) end = NR; printf "%d–%d", start, end } }' "$1" 2>/dev/null
}

# runbook_stage_token <stage-arg> — P, 0-7 as the runbook spells them ("build-ready" reads Stage
# 5's section; "p" is "P"). Prints nothing for anything else.
runbook_stage_token() {
  case "$1" in
    build-ready) echo "5" ;;
    p|P) echo "P" ;;
    0|1|2|3|4|5|6|7) echo "$1" ;;
    *) : ;;
  esac
}

# runbook_stage_span <file> <stage-token>  — the "A–B" span of "### Stage N — …"
runbook_stage_span() { runbook_span "$1" "^### Stage $2 — " "^###? "; }
# runbook_1b_span <file>                   — the "A–B" span of "## 1b. …"
runbook_1b_span()    { runbook_span "$1" "^## 1b\\." "^## "; }

# runbook_print_span <file> <"A–B"> — the lines themselves.
runbook_print_span() {
  local a b
  a="${2%%–*}"; b="${2##*–}"
  [ -n "$a" ] && [ -n "$b" ] || return 1
  sed -n "${a},${b}p" "$1"
}
