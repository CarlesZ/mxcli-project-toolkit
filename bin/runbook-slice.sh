#!/usr/bin/env bash
# runbook-slice.sh — print the part of the conversion runbook a helper at one stage needs:
# §1b (the Live Checklist Protocol, every stage) plus that stage's section under §2.
#
#   bin/runbook-slice.sh 5             # §1b + "### Stage 5 — Build"
#   bin/runbook-slice.sh build-ready   # same as 5
#   bin/runbook-slice.sh --spans 5     # only the line spans, as gate-check.sh prints them
#
# WHY (2026-10-14). skills/conversion-runbook.md is ~14k words. Its own "how to read this" rule
# says a session reads §1b plus its stage's section, and gate-check.sh prints those line spans —
# but a helper (mdl, gate, test, review) never runs a gate, so it never saw the spans and opened
# the whole file: 26% of an mdl helper's Stage 5 reading. This prints the ~1.5k words instead, the
# same way bin/bug-lookup.sh turned the bug ledger into a lookup. Sections are found by heading
# (bin/lib/runbook-span.sh, shared with gate-check.sh), never by line number.
#
# Exit: 0 printed · 1 usage · 2 runbook or heading not found
set -eu
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "$ROOT/bin/lib/runbook-span.sh"
RB="${MXTK_RUNBOOK:-$ROOT/skills/conversion-runbook.md}"

SPANS_ONLY=0
if [ "${1:-}" = "--spans" ]; then SPANS_ONLY=1; shift; fi
case "${1:-}" in
  ""|-h|--help) sed -n '2,8p' "$0" | sed 's/^# \{0,1\}//'; exit 1 ;;
esac
ST="$(runbook_stage_token "$1")"
[ -n "$ST" ] || { echo "runbook-slice: unknown stage '$1' (P, 0-7 or build-ready)" >&2; exit 1; }
[ -f "$RB" ] || { echo "runbook-slice: no runbook at $RB" >&2; exit 2; }

S1B="$(runbook_1b_span "$RB")"
SST="$(runbook_stage_span "$RB" "$ST")"
if [ -z "$S1B" ] || [ -z "$SST" ]; then
  echo "runbook-slice: could not locate '## 1b.' or '### Stage $ST — ' in $RB — read §1b and your stage's §2 section there" >&2
  exit 2
fi

if [ "$SPANS_ONLY" -eq 1 ]; then
  printf 'skills/conversion-runbook.md §1b lines %s + Stage %s lines %s\n' "$S1B" "$ST" "$SST"
  exit 0
fi
printf '<!-- skills/conversion-runbook.md §1b (lines %s) + Stage %s (lines %s), printed by bin/runbook-slice.sh -->\n\n' "$S1B" "$ST" "$SST"
runbook_print_span "$RB" "$S1B"
echo
runbook_print_span "$RB" "$SST"
