#!/usr/bin/env bash
# The "## Change log" section of a project's PROJECT.md — ONE copy of its template and ONE parser.
#
# init-project.sh writes the empty section, sync-project.sh appends it to a project that predates
# it, and gate-check.sh reads it back. Same one-copy arrangement as intake-template.sh and
# ritual-template.sh: two hand-kept copies of a template have drifted before.
#
# WHY IT EXISTS (2026-10-13). Across 12 mid-build changes on real projects, 12 went straight into
# MDL and 0 updated a BRD, build plan or wireframe; the drift-sync marker that should have caught
# them was never written once, and its absence is undetectable, so every gate passed on silence.
# The change log makes the ask itself the record: one row per piece of feedback, written BEFORE
# any edit, so "nothing logged" and "logged but never applied" become countable.
# The method is skills/change-intake.md; this file is only the table and its reader.
#
# PRODUCER for the consumer (CLAUDE.md "Shipping an instrument" rule 5): the section is written by
# bin/init-project.sh (every new project) and bin/sync-project.sh (every existing one, after a
# toolkit pull) — both mandatory chain steps. Rows are written by the lead per change-intake.md.
#
# WARN-ONLY. gate-check.sh reports what mxtk_change_log_scan counts as a WARN line and never
# blocks on it. change-intake.md says when that changes, and why not yet.
#
# Sourced, never executed. Callers are `set -euo pipefail`, so keep this side-effect free.

# Usage: mxtk_change_log_section
mxtk_change_log_section() {
  cat <<'EOF'
## Change log

Feedback and change requests, one row each, written BEFORE any edit (`skills/change-intake.md`). Status: open → refined → agreed → applied → proven, or rejected (reason); Closed-by cites the commit, journey or test. Escape a `|` inside the ask as `\|`.

| CR | Date | Source | Verbatim ask | Class | Size | Entry artifact | Status | Closed-by |
|---|---|---|---|---|---|---|---|---|
EOF
}

# CRLF (2026-10-13 review of #306): a PROJECT.md saved on Windows ends every line in \r, so
# '^## +change log *$' never matched — gate-check reported "no section" and sync-project.sh
# appended a SECOND empty one; the scan likewise read 0 rows. Both readers drop a trailing \r
# first, as gate-check.sh does for every table it reads (tr -d '\r'). awk, not tr | grep -q:
# under the callers' pipefail an early-exiting grep -q can SIGPIPE the producer and turn a hit
# into a miss.
#
# Usage: mxtk_change_log_has_section <PROJECT.md>   — rc 0 when the heading is present
mxtk_change_log_has_section() {
  [ -f "$1" ] || return 1
  awk '{ sub(/\r$/, "") } tolower($0) ~ /^## +change log *$/ { found = 1; exit } END { exit !found }' "$1"
}

# Usage: mxtk_change_log_scan <PROJECT.md>
# Prints one SUMMARY line, then one ROW line per change request that still owes something:
#   SUMMARY<TAB>total<TAB>open<TAB>refined<TAB>agreed<TAB>no_evidence<TAB>unrecognised
#   ROW<TAB>CR-NN<TAB>status<TAB>what it owes<TAB>first 60 chars of the ask
# Only rows inside the "## Change log" section whose first cell is CR-<digits> count. Cells are
# read from the RIGHT (Status is second-to-last, Closed-by last), so an ask containing an
# unescaped pipe still yields the right status — the ask is the cell people type freely.
# HTML comments are skipped, as gate-check.sh's reg_field does: an example row in a comment must
# never count.
mxtk_change_log_scan() {
  [ -f "$1" ] || { printf 'SUMMARY\t0\t0\t0\t0\t0\t0\n'; return 0; }
  awk '
    function trim(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
    function clean(s) { gsub(/[*`]/, "", s); return trim(s) }
    function owe(id, st, why) { rows = rows sprintf("ROW\t%s\t%s\t%s\t%s\n", id, st, why, ask) }
    { sub(/\r$/, "") }                          # CRLF register: see mxtk_change_log_has_section
    /<!--/ { incomment = 1 }
    incomment { if ($0 ~ /-->/) incomment = 0; next }
    /^## / { insec = (tolower($0) ~ /^## +change log *$/); next }
    !insec { next }
    !/^[ \t]*\|/ { next }
    {
      line = $0
      gsub(/\\\|/, "\001", line)                 # escaped pipes inside a cell: hide, restore below
      sub(/^[ \t]*\|/, "", line)
      sub(/\|[ \t]*$/, "", line)
      n = split(line, c, "|")
      id = clean(c[1])
      if (id !~ /^CR-[0-9]+$/) next              # header, separator, prose
      total++
      ask = (n >= 4) ? clean(c[4]) : ""
      gsub(/\001/, "|", ask)
      if (length(ask) > 60) ask = substr(ask, 1, 57) "..."
      if (n < 3) { unk++; owe(id, "?", "too few cells to read a status"); next }
      # Status = first word of the second-to-last cell, letters only ("agreed 2026-10-13",
      # "rejected - out of scope", "**proven**" all read). No dash in a bracket expression:
      # an em-dash there is a multibyte trap on BSD awk.
      st = tolower(clean(c[n - 1]))
      sub(/^[^a-z]+/, "", st); sub(/[^a-z].*$/, "", st)
      cb = clean(c[n])
      empty_cb = (cb == "" || cb == "-" || cb == "—" || cb == "–" || tolower(cb) == "n/a")
      if (st == "open")         { op++; owe(id, st, "not yet restated or agreed") }
      else if (st == "refined") { rf++; owe(id, st, "waiting for the user to agree or reject") }
      else if (st == "agreed")  { ag++; owe(id, st, "agreed; entry artifact not yet updated") }
      else if (st == "applied" || st == "proven") {
        if (empty_cb) { ne++; owe(id, st, "no Closed-by evidence") }
      }
      else if (st != "rejected") { unk++; owe(id, (st == "" ? "(blank)" : st), "unrecognised status") }
    }
    END {
      printf "SUMMARY\t%d\t%d\t%d\t%d\t%d\t%d\n", total, op, rf, ag, ne, unk
      printf "%s", rows
    }
  ' "$1"
}
