#!/usr/bin/env bash
# mdl-scan.sh — refuse an MDL script that contains a STOP-row pattern, before anyone applies it.
#
#   bin/mdl-scan.sh <script.mdl> [-p <app.mpr>]
#
# One rule per row of skills/learned-mdl-preflight.md's STOP table that a text pattern in the
# script identifies (issue #349). The rules are data: bin/lib/mdl-scan-rules.tsv, whose header
# documents the columns and the three rule kinds. Rows that need model state or judgement are
# not here; they stay prose in the skill, unmarked.
#
# Output: one line per hit, `STOP-<n> <file>:<line> <message> → <fix>`.
# Exit:   0 clean · 1 at least one hit · 2 usage error (no script, unreadable file, bad flag,
#         rules file missing).
#
# -p is accepted and checked, so a caller can pass the model the same way it passes it to
# `mxcli check`. No current rule reads it: every row that needs model state stayed prose
# (the PR for #349 lists them). A future rule that uses it must stay read-only.
#
# WHY. The STOP table is prose an agent reads, or skips. Every rule here was a script that
# passed `mxcli check`, cost a full apply, and failed only at mxbuild or on Studio Pro open
# (bug ids in the rules file). A text scan costs milliseconds; a failed apply costs 22-65 s
# plus the restore (iterative-build-loop.md, "Gate cost").
#
# HOW IT READS A SCRIPT. Comments (`--`, `//`, `/* */`) and `$$ ... $$` bodies are removed,
# string literals are kept (STOP-16 lives inside one), and the line is lowercased. Bracket
# depth is counted outside strings, so a customContent column's body is known by depth, not
# by indentation. It is a line scanner, not a parser: a one-line column whose body opens and
# holds the conditional on the header line itself is not seen as inside the column.
#
# Golden input: the bad MDL captured in bug-logs/mxcli-bugs.md for each rule, and the
# StyleGallery example (applied, 0 errors in mx check) as the clean corpus —
# tests/wave2/test-mdl-scan.sh, tests/wave2/bench-mdl-scan.sh. Plain bash 3.2 + POSIX awk.
set -u

usage() { echo "usage: bin/mdl-scan.sh <script.mdl> [-p <app.mpr>]" >&2; exit 2; }

SCRIPT=""; MPR=""
while [ $# -gt 0 ]; do
  case "$1" in
    -p) [ $# -ge 2 ] || usage; MPR="$2"; shift 2 ;;
    -h|--help) sed -n '2,13p' "$0"; exit 0 ;;
    -*) echo "mdl-scan: unknown option '$1'" >&2; usage ;;
    *) [ -z "$SCRIPT" ] || usage; SCRIPT="$1"; shift ;;
  esac
done
[ -n "$SCRIPT" ] || usage
[ -f "$SCRIPT" ] && [ -r "$SCRIPT" ] || { echo "mdl-scan: cannot read script: $SCRIPT" >&2; exit 2; }
if [ -n "$MPR" ] && [ ! -f "$MPR" ]; then echo "mdl-scan: -p: no such model: $MPR" >&2; exit 2; fi

RULES="${MDL_SCAN_RULES:-$(cd "$(dirname "$0")" && pwd)/lib/mdl-scan-rules.tsv}"
[ -r "$RULES" ] || { echo "mdl-scan: rules file missing: $RULES" >&2; exit 2; }

awk -F'\t' -v file="$SCRIPT" '
  FNR == NR {                                   # the rules file
    if ($0 ~ /^#/ || NF < 5) next
    n++; rid[n] = $1; rkind[n] = $2; rpat[n] = $3; rmsg[n] = $4; rfix[n] = $5
    next
  }
  function hit(i, ln) { printf "%s %s:%d %s → %s\n", rid[i], file, ln, rmsg[i], rfix[i]; hits++ }
  # strip(line): sets code (comments and $$-bodies removed, strings kept) and bare (strings
  # blanked too). inblock / indollar carry across lines.
  function strip(line,    m, i, c, c2, instr) {
    code = ""; bare = ""; m = length(line); i = 1; instr = 0
    while (i <= m) {
      c = substr(line, i, 1); c2 = substr(line, i, 2)
      if (inblock)  { if (c2 == "*/") { inblock = 0; i += 2 } else i++; continue }
      if (indollar) { if (c2 == "$$") { indollar = 0; i += 2 } else i++; continue }
      if (instr) {
        code = code c; bare = bare " "
        if (c == "\047") instr = 0
        i++; continue
      }
      if (c2 == "/*") { inblock = 1; i += 2; continue }
      if (c2 == "$$") { indollar = 1; i += 2; continue }
      if (c2 == "--" || c2 == "//") break
      if (c == "\047") instr = 1
      code = code c; bare = bare (instr ? " " : c)
      i++
    }
    code = tolower(code); bare = tolower(bare)
  }
  # A ContentParams value is fine when it is a quoted literal, or a bare (optionally
  # double-quoted) identifier, or an unquoted identifier path. Anything else is an expression.
  function bad_value(v) {
    sub(/^[[:space:]]+/, "", v); sub(/[[:space:],]+$/, "", v)
    if (v ~ /^\047([^\047]|\047\047)*\047$/) return 0
    if (v ~ /^"?[a-z_][a-z0-9_]*"?$/) return 0
    if (v ~ /^[a-z_][a-z0-9_.]*(\/[a-z_][a-z0-9_.]*)*$/) return 0
    return 1
  }
  function check_params(text, ln, i,    rest, p, q, v) {
    rest = text
    while (match(rest, /\{[0-9]+\}[[:space:]]*=/)) {
      rest = substr(rest, RSTART + RLENGTH)
      if (match(rest, /,[[:space:]]*\{[0-9]+\}[[:space:]]*=/)) v = substr(rest, 1, RSTART - 1)
      else { v = rest; sub(/\][^]]*$/, "", v) }
      if (bad_value(v)) { hit(i, ln); return }
    }
  }
  {
    strip($0)
    incc = (ccn > 0)                            # inside a customContent column body?
    for (i = 1; i <= n; i++) {
      if (rkind[i] == "line" && code ~ rpat[i]) hit(i, FNR)
      else if (rkind[i] == "customcontent" && incc && code ~ rpat[i]) hit(i, FNR)
      else if (rkind[i] == "contentparams") {
        if (cp_open) {                          # a ContentParams list still open from above
          cp_text = cp_text " " code
          if (index(bare, "]")) { check_params(cp_text, cp_line, i); cp_open = 0 }
        } else if (match(code, /contentparams[[:space:]]*:[[:space:]]*\[/)) {
          cp_text = substr(code, RSTART + RLENGTH); cp_line = FNR
          if (index(substr(bare, RSTART + RLENGTH), "]")) check_params(cp_text, cp_line, i)
          else cp_open = 1
        }
      }
    }
    if (bare ~ /^[[:space:]]*column[[:space:]]/) pending = 0   # a new column: forget a body-less one
    if (bare ~ /showcontentas[[:space:]]*:[[:space:]]*customcontent/) pending = 1
    m = length(bare)
    for (j = 1; j <= m; j++) {
      c = substr(bare, j, 1)
      if (c == "{") { depth++; if (pending) { cc[++ccn] = depth; pending = 0 } }
      else if (c == "}") { if (ccn > 0 && cc[ccn] == depth) ccn--; depth-- }
    }
  }
  END { exit (hits > 0) }
' "$RULES" "$SCRIPT"
