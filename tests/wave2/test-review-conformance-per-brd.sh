#!/usr/bin/env bash
# Usage: bash test-review-conformance-per-brd.sh [path-to-review-module.sh]
#
# Fixture for project-bin/review-module.sh's conformance rung on a per-BRD ledger.
#
# The defect (review of the #260 fix, 2026-10-13): conformance-check.sh writes one report per
# BRD (docs/conformance/report-<date>-<BRD>.tsv) for a per-BRD ledger, and no report-<date>.tsv.
# review-module.sh read exactly one file on both of its paths:
#   - --reuse-conformance docs/conformance/report-<date>.tsv (what verify-module.sh passes):
#     the file does not exist, so rung 13 of verify-module FAULTed "does not exist";
#   - its own run: `ls -t report-*.tsv | head -1`, i.e. one BRD's rows, the others dropped.
# Both now read every report of the run and slice this module's rows out of all of them.
#
# Cases, each on BOTH layouts (single-tree, and two-tree with the .mpr under app/):
#   1. --reuse-conformance <base>: both per-BRD siblings are read (2 Orders rows, not a FAULT)
#   1b. a module with ONLY the per-BRD directory (no coverage-ledger.md index) is a ledger, not
#      "no ledger"; and the reuse log field names the files read, not the absent base name
#   2. its own run (stub conformance-check.sh in <project>/bin, which _tool prefers): rows from
#      both per-BRD reports reach conformance.tsv
#
# The reports and the mxcli / conformance-check stubs are SYNTHETIC: the report columns are the
# six conformance-check.sh writes, and the assertions are about which files are read. Later
# rungs (graph sweep, coverage) fault harmlessly on the empty fixture project; only the
# conformance slice is asserted.

set -uo pipefail

SUT="${1:-}"
[ -z "$SUT" ] && SUT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/project-bin/review-module.sh"
if [ ! -f "$SUT" ]; then
  echo "SKIP: subject not found at $SUT"
  echo "SCORE: 0/0 — nothing to test"
  exit 0
fi
SUT="$(cd "$(dirname "$SUT")" && pwd)/$(basename "$SUT")"
[ -f "$(dirname "$SUT")/_common.sh" ] || { echo "FAIL — _common.sh not beside $SUT"; exit 1; }

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  ok   — $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL — $1"; [ -n "${2:-}" ] && echo "         got: $2"; }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/review-perbrd.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
D="$(date +%Y-%m-%d)"

report() {  # report <file> <brd>
  { printf 'module\tpointer\tstored\tobserved\tverdict\tcommand\n'
    printf 'Orders\t%s:`/microflows/0`\tbuilt\tPRESENT\tOK\tDESCRIBE MICROFLOW Orders.X\n' "$2"
    printf 'Billing\t%s:`/microflows/1`\tbuilt\tPRESENT\tOK\tDESCRIBE MICROFLOW Billing.Y\n' "$2"
  } > "$1"
}

setup() {  # setup <single|two> -> sets P
  P="$WORK/$1"; rm -rf "$P"
  mkdir -p "$P/architecture/modules/Orders/coverage-ledger" "$P/docs/conformance" "$P/bin"
  if [ "$1" = two ]; then mkdir -p "$P/app"; : > "$P/app/Shop.mpr"; else : > "$P/Shop.mpr"; fi
  printf '# Orders — index\n- [F001](coverage-ledger/F001.md)\n' > "$P/architecture/modules/Orders/coverage-ledger.md"
  : > "$P/architecture/modules/Orders/coverage-ledger/F001.md"
  cat > "$P/mxcli" <<'EOF'
#!/usr/bin/env bash
case "$*" in *"SHOW MODULES"*) echo "| Orders |"; exit 0 ;; esac
echo "Error: not available in this fixture"; exit 1
EOF
  chmod +x "$P/mxcli"
  # Module-exists probe: the catalog answers instantly; without it review-module falls back to
  # `mxcli SHOW MODULES` under a 60 s watchdog it waits out in full.
  if command -v sqlite3 >/dev/null 2>&1; then
    mkdir -p "$P/.mxcli"
    printf "CREATE TABLE objects (QualifiedName TEXT, ModuleName TEXT);\nINSERT INTO objects VALUES ('Orders.X','Orders');\n" \
      | sqlite3 "$P/.mxcli/catalog.db"
  fi
}
run() { ( cd "$P" && PROJECT_ROOT="$P" MXTK_ROOT="" bash "$SUT" Orders --json-only --out "$P/out/report.json" "$@" ) \
          > "$WORK/out" 2>&1; echo $?; }
slice() { awk -F'\t' 'NR>1 && $1=="Orders"' "$P/.claude/loop/review/Orders/conformance.tsv" 2>/dev/null | grep -c . ; }
out() { sed $'s/\033\[[0-9;]*m//g' "$WORK/out" | tr '\n' ' ' | cut -c1-400; }

for layout in single two; do
  echo "== $layout-tree layout"

  # --- 1. reuse: verify-module passes the base name; the per-BRD siblings are the run ---------
  setup "$layout"
  report "$P/docs/conformance/report-$D-F001.tsv" F001
  report "$P/docs/conformance/report-$D-F002.tsv" F002
  run --reuse-conformance "docs/conformance/report-$D.tsv" >/dev/null
  if grep -q "does not exist" "$WORK/out"; then
    bad "[$layout] reuse FAULTed on a per-BRD run (base report-<date>.tsv absent)" "$(out)"
  elif [ "$(slice)" = 2 ] && grep -q "2 rows from 2 report(s)" "$WORK/out"; then
    ok "[$layout] reuse reads both per-BRD reports (2 Orders rows, Billing's filtered out)"
  else
    bad "[$layout] reuse did not slice both per-BRD reports" "slice=$(slice) $(out)"
  fi

  # --- 1b. directory-only ledger; log field names the files actually read ----------------------
  setup "$layout"
  rm -f "$P/architecture/modules/Orders/coverage-ledger.md"
  report "$P/docs/conformance/report-$D-F001.tsv" F001
  report "$P/docs/conformance/report-$D-F002.tsv" F002
  run --reuse-conformance "docs/conformance/report-$D.tsv" >/dev/null
  S="$P/.claude/loop/review/Orders/summary.tsv"
  if grep -q "no architecture/modules/Orders/coverage-ledger.md" "$WORK/out"; then
    bad "[$layout] directory-only ledger reported as no ledger" "$(out)"
  elif [ "$(slice)" = 2 ] && grep -q "conformance (reused).PASS.*report-$D-F001.tsv, docs/conformance/report-$D-F002.tsv" "$S" \
       && ! grep -q "PASS.0.-.docs/conformance/report-$D.tsv\$" "$S"; then
    ok "[$layout] directory-only ledger measured; summary names report-$D-F001/F002.tsv"
  else
    bad "[$layout] directory-only ledger or log field wrong" "slice=$(slice) $(tr '\n' ' ' < "$S" 2>/dev/null)"
  fi

  # --- 2. own run: every report this run wrote, not just the newest ---------------------------
  setup "$layout"
  cat > "$P/bin/conformance-check.sh" <<EOF
#!/usr/bin/env bash
mkdir -p docs/conformance
$(declare -f report)
report "docs/conformance/report-$D-F001.tsv" F001
sleep 1
report "docs/conformance/report-$D-F002.tsv" F002
echo "conformance-check stub"; exit 0
EOF
  chmod +x "$P/bin/conformance-check.sh"
  run >/dev/null
  if [ "$(slice)" = 2 ]; then
    ok "[$layout] own run slices rows from both per-BRD reports (2 Orders rows)"
  else
    bad "[$layout] own run read only the newest per-BRD report" "slice=$(slice) $(out)"
  fi
done

echo ""
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
