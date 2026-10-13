#!/usr/bin/env bash
# script-owners.sh — which mdlsource/ scripts create or restate each document.
#
#   bin/script-owners.sh docs   <script.mdl>   one row per document the script creates or restates:
#                                              KIND <tab> Module.Name <tab> line <tab> create|modify|replace
#   bin/script-owners.sh report [project-root] every document owned by more than one script, with
#                                              its scripts in run order, then a summary line
#   bin/script-owners.sh count  [project-root] "<multi-owner> <documents>" — gate-check.sh reads it
#   bin/script-owners.sh check  <script.mdl> [project-root]
#                                              exit 1 when the script restates a document that
#                                              another script also owns and no supersedes header
#                                              settles who wins; exec.sh calls this before a write
#
# A document is a microflow, nanoflow, page or snippet named by a `create`, `create or modify`
# or `create or replace` statement. `alter page` / `alter snippet` is NOT ownership: it edits in
# place, which is the write this script steers people towards.
#
# WHY (#269, field evidence 2026-10-05..09, mxcli v0.25.0). Three toolkit-built apps counted
# 99 of 579, 130 of 357 and 38 of 159 documents created by more than one script — worst case a
# published-API microflow restated in 5 scripts. Re-running an older script (a replay, a rebuild
# from a fresh .mpr, an agent "re-applying slice 2") silently puts back every change the later
# scripts made: the older body is valid MDL, so check, mxbuild and lint all stay green. Nothing
# recorded which script owns a document. #261 is the same loss inside one batch (a script
# drafted from a DESCRIBE taken before an earlier script ran) — describe-baseline.sh covers that.
#
# HOW A SCRIPT SAYS WHO WINS. Header comments, anywhere in the file, basenames or paths:
#   -- supersedes: 05-orders.mdl, 07-orders-fix.mdl    (in the NEW script: it owns these docs now)
#   -- superseded-by: 12-orders-v2.mdl                 (in the OLD script: do not replay me)
# `check` on script S, for each document S restates that another script O also restates:
#   S supersedes O (either header says so)  → fine, S is the owner
#   O supersedes S                          → CONFLICT: replaying S reverts O's later work
#   neither header                          → CONFLICT: two unrecorded owners; the row says
#                                             whether O sorts before S (S is a new restatement
#                                             that needs a supersedes header) or after it
#                                             (S is an older script being replayed)
# Run order is the path order under mdlsource/ (LC_ALL=C sort), which is how numbered scripts
# are run. A script outside mdlsource/ (a scratch file) owns nothing; every owner is "other".
#
# Not a parser: the same comment/string/$$-body blanking and bracket depth as exec.sh's change
# class lexer, then only statement heads at depth 0 are read, so a caption saying "create page"
# or a widget line never counts. Unlike that lexer, a string literal may span lines (a real
# `find($Clean, '<newline>')` in skills/agents-examples/single-call.example.mdl hid the next
# microflow from a per-line lexer: the open quote left the bracket depth at 1). Golden input is real MDL: mxcli v0.23.0 DESCRIBE captures
# (tests/wave2/fixtures/context-pack/capture/describe/), the shipped StyleGallery mdlsource tree
# and skills/agents-examples/*.mdl (tests/wave2/test-script-owners.sh). `*.test.mdl` files are
# skipped: they are microflow tests, not build steps.
#
# Producer for every consumer (CLAUDE.md "Shipping an instrument" rule 5): the input is the
# project's own mdlsource/, written by every build step; the consumers are exec.sh (check, every
# MDL write) and gate-check.sh (count, every gate run). Read-only: it never edits a script.
# Plain bash + awk: bash 3.2, BSD awk, Git Bash.
set -u

usage() {
  sed -n '3,12p' "$0" | sed 's/^# \{0,1\}//' >&2
  exit 2
}

_SO_AWK='
    function lex_line(line,    n, i, c, c2, tmp, o, cl) {
      clean = ""; n = length(line); i = 1
      while (i <= n) {
        c = substr(line, i, 1); c2 = substr(line, i, 2)
        if (instr)     { if (c == "\047") instr = 0; i++; continue }
        if (inblock)   { if (c2 == "*/") { inblock = 0; i += 2 } else i++; continue }
        if (indollar)  { if (c2 == "$$") { indollar = 0; i += 2 } else i++; continue }
        if (c2 == "/*") { inblock = 1; i += 2; continue }
        if (c2 == "$$") { indollar = 1; i += 2; continue }
        if (c2 == "--" || c2 == "//") break
        if (c == "\047") {                        # a literal may span lines: find(\$s, newline)
          i++; while (i <= n && substr(line, i, 1) != "\047") i++
          if (i > n) instr = 1
          i++; clean = clean "\047\047"; continue
        }
        if (c == "\"") { i++; continue }
        clean = clean c; i++
      }
      start_depth = depth
      tmp = clean; o = gsub(/[({]/, "", tmp); tmp = clean; cl = gsub(/[)}]/, "", tmp)
      depth += o - cl; if (depth < 0) depth = 0
    }
    {
      sub(/\r$/, "")
      lex_line($0)
      if (start_depth != 0) next
      s = clean; sub(/^[ \t]+/, "", s)
      low = tolower(s)
      if (low !~ /^create[ \t]/) next
      rest = substr(s, 7); sub(/^[ \t]+/, "", rest)
      verb = "create"
      if (tolower(rest) ~ /^or[ \t]+(modify|replace)[ \t]/) {
        sub(/^[Oo][Rr][ \t]+/, "", rest)
        verb = tolower(rest); sub(/[ \t].*$/, "", verb)
        sub(/^[A-Za-z]+[ \t]+/, "", rest)
      }
      kind = tolower(rest); sub(/[ \t(].*$/, "", kind)
      if (kind != "microflow" && kind != "nanoflow" && kind != "page" && kind != "snippet") next
      sub(/^[A-Za-z]+[ \t]+/, "", rest)
      if (!match(rest, /^[A-Za-z_][A-Za-z0-9_]*[ \t]*\.[ \t]*[A-Za-z_][A-Za-z0-9_]*/)) next
      name = substr(rest, 1, RLENGTH); gsub(/[ \t]/, "", name)
      printf "%s\t%s\t%d\t%s\n", toupper(kind), name, FNR, verb
    }'

so_docs() {  # $1 = script
  awk "$_SO_AWK" "$1"
}

# Header values: `-- supersedes: a.mdl, b.mdl` → one basename per line.
so_header() {  # $1 = script, $2 = supersedes|superseded-by
  sed -nE "s/^[[:space:]]*--[[:space:]]*$2:[[:space:]]*(.*)$/\1/p" "$1" 2>/dev/null \
    | tr ',' '\n' | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//; s/[[:space:]].*$//' \
    | sed -E 's#.*/##' | grep -v '^$' || true
}

so_root() {  # $1 = optional project root
  if [ -n "${1:-}" ]; then (cd "$1" 2>/dev/null && pwd) || echo "$1"
  elif [ -n "${PROJECT_ROOT:-}" ]; then echo "$PROJECT_ROOT"
  else pwd
  fi
}

so_scripts() {  # $1 = root → every build script under mdlsource/, run order, root-relative
  [ -d "$1/mdlsource" ] || return 0
  ( cd "$1" && find mdlsource -type f -name '*.mdl' ! -name '*.test.mdl' 2>/dev/null | LC_ALL=C sort )
}

so_index() {  # $1 = root → "doc <tab> script" for every owner, run order
  local f
  so_scripts "$1" | while IFS= read -r f; do
    so_docs "$1/$f" | awk -F'\t' -v s="$f" '{ print $1 " " $2 "\t" s }' | LC_ALL=C sort -u
  done
}

cmd="${1:-}"
case "$cmd" in
  docs)
    [ -f "${2:-}" ] || usage
    so_docs "$2"
    ;;
  report|count)
    ROOT="$(so_root "${2:-}")"
    IDX="$(so_index "$ROOT")"
    SUMMARY="$(printf '%s\n' "$IDX" | awk -F'\t' 'NF == 2 {
        if (!($1 in seen)) { seen[$1] = 1; order[++n] = $1 }
        c[$1]++; s[$1] = s[$1] (c[$1] > 1 ? ", " : "") $2
      }
      END {
        m = 0
        for (i = 1; i <= n; i++) if (c[order[i]] > 1) { m++; printf "  %s — %d scripts: %s\n", order[i], c[order[i]], s[order[i]] }
        printf "SUMMARY\t%d\t%d\n", m, n
      }')"
    M="$(printf '%s\n' "$SUMMARY" | awk -F'\t' '$1 == "SUMMARY" { print $2 }')"
    N="$(printf '%s\n' "$SUMMARY" | awk -F'\t' '$1 == "SUMMARY" { print $3 }')"
    if [ "$cmd" = count ]; then echo "${M:-0} ${N:-0}"; exit 0; fi
    if [ ! -d "$ROOT/mdlsource" ]; then echo "no mdlsource/ under $ROOT — nothing to report"; exit 0; fi
    printf '%s\n' "$SUMMARY" | grep -v '^SUMMARY' || true
    echo "multi-owner: ${M:-0} of ${N:-0} document(s) created by more than one mdlsource/ script"
    [ "${M:-0}" -gt 0 ] && echo "  → edit the owning script, use alter, or mark the winner: -- supersedes: <older script> (skills/learned-mdl-preflight.md STOP 21)"
    exit 0
    ;;
  check)
    [ -f "${2:-}" ] || usage
    S="$2"
    ROOT="$(so_root "${3:-}")"
    # The script's own path relative to ROOT, when it lives under it, so it is not its own co-owner.
    S_ABS="$(cd "$(dirname "$S")" && pwd)/$(basename "$S")"
    S_REL="${S_ABS#"$ROOT"/}"
    [ "$S_REL" = "$S_ABS" ] && S_REL=""
    S_BASE="$(basename "$S")"
    MY_SUP="$(so_header "$S" supersedes)"
    MY_SUPBY="$(so_header "$S" superseded-by)"
    DOCS="$(so_docs "$S" | awk -F'\t' '{ print $1 " " $2 }' | LC_ALL=C sort -u)"
    [ -n "$DOCS" ] || exit 0
    IDX="$(so_index "$ROOT")"
    OUT="$(while IFS= read -r d; do
      [ -n "$d" ] || continue
      printf '%s\n' "$IDX" | awk -F'\t' -v d="$d" '$1 == d { print $2 }' | while IFS= read -r o; do
        [ "$o" = "$S_REL" ] && continue
        ob="$(basename "$o")"
        if printf '%s\n' "$MY_SUP" | grep -qxF "$ob" || so_header "$ROOT/$o" superseded-by | grep -qxF "$S_BASE"; then
          continue
        fi
        if printf '%s\n' "$MY_SUPBY" | grep -qxF "$ob" || so_header "$ROOT/$o" supersedes | grep -qxF "$S_BASE"; then
          echo "CONFLICT	$d	$o	superseded: $o supersedes this script — replaying it reverts $o"
        elif [ -z "$S_REL" ]; then
          echo "CONFLICT	$d	$o	owned by $o; this script is outside mdlsource/"
        elif [ "$(printf '%s\n%s\n' "$o" "$S_REL" | LC_ALL=C sort | head -1)" = "$o" ]; then
          echo "CONFLICT	$d	$o	older owner $o — a new restatement needs '-- supersedes: $ob'"
        else
          echo "CONFLICT	$d	$o	newer owner $o — replaying this script reverts it"
        fi
      done
    done <<EOF
$DOCS
EOF
)"
    [ -n "$OUT" ] || exit 0
    printf '%s\n' "$OUT"
    exit 1
    ;;
  *) usage ;;
esac
