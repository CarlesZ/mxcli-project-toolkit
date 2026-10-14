#!/usr/bin/env bash
# test-baseline-lock.sh — a ratchet baseline moves only on a person's approval (#348).
#
# Usage: bash tests/wave2/test-baseline-lock.sh [toolkit-root]
#   The subject is a toolkit tree: its project-bin/lint-gate.sh, conformance-check.sh,
#   baseline-lock.sh, baseline-approve.sh and bin/gate-check.sh. Run against origin/master's
#   tree, the L/C/G cases fail — that is the hole: the agent typed --approved-in-chat itself.
#
#   L1  lint: a rise with --reason AND --approved-in-chat, no person → refused, baseline unchanged
#   L2  baseline-approve.sh with no terminal (an agent's tool call) → refused, no approval row
#   L3  after the person approves → the update lands, exactly the approved content
#   L4  the approval binds to content: counts change after approval → refused again
#   L5  deleting the baseline and re-creating it lower is refused (no laundering by delete)
#   C1  conformance: --update-baseline accepting a regression, no person → refused, unchanged
#   C2  after the person approves → it lands
#   G1  gate-check: a hand-moved baseline reports FAIL, and Stage 5 is BLOCKED (exit 1)
#   G2  after the person approves the file as it is (--current) → PASS
#   G3  a baseline with no record at all (predates the lock) → MANUAL, not PASS
#
# Synthetic lint JSON and a stub mxcli, as in test-lint-gate-accept.sh and
# test-conformance-baseline-scope.sh: nothing here parses tool output; the assertions are
# about which baseline writes land. The person's step runs baseline-approve.sh under a
# pseudo-terminal (fixtures/baseline-lock/human.sh); the fixture never writes an approval row.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TK="$(cd "${1:-$HERE/../..}" && pwd)"
. "$HERE/fixtures/baseline-lock/human.sh"
command -v python3 >/dev/null 2>&1 && PY=python3 || PY=python  # portability-ok: fixture probe
WORK="$(mktemp -d "${TMPDIR:-/tmp}/baseline-lock.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; [ -n "${2:-}" ] && printf '%s\n' "$2" | head -8 | sed 's/^/       /'; }
pty_available || { echo "SKIP: no usable \`script\` for a pseudo-terminal"; exit 0; }

newproj() {  # newproj <dir> — a project with the toolkit's scripts installed in bin/
  mkdir -p "$1/bin" "$1/.claude"
  for f in _common.sh lint-gate.sh conformance-check.sh baseline-lock.sh baseline-approve.sh; do
    [ -f "$TK/project-bin/$f" ] && cp "$TK/project-bin/$f" "$1/bin/"
  done
  printf 'mpr' > "$1/App.mpr"
}
lintjson() {  # lintjson RULE=n ... > $WORK/lint.json
  "$PY" - "$@" > "$WORK/lint.json" <<'PY'
import json, sys
v = []
for a in sys.argv[1:]:
    r, n = a.split("=")
    v += [{"ruleId": r, "severity": "warning", "message": "f%d" % i, "module": "Orders",
           "document": "D%d" % i, "documentType": "microflow", "documentId": "%s-%d" % (r, i),
           "suggestion": "s"} for i in range(int(n))]
print(json.dumps({"violations": v, "summary": {}}))
PY
}
P="$WORK/p"; newproj "$P"; printf '#!/bin/sh\nexit 0\n' > "$P/mxcli"; chmod +x "$P/mxcli"
gate() { (cd "$P" && LINT_JSON="$WORK/lint.json" bash bin/lint-gate.sh "$@") 2>&1; }
LB="$P/.claude/lint-baseline.json"
counts() { "$PY" -c 'import json,sys;print(json.load(open(sys.argv[1]))["counts"])' "$1" 2>/dev/null; }

echo "L1 the agent's own flags do not move the lint baseline"
lintjson CONV009=2 SEC003=1; gate --update-baseline >/dev/null
before="$(cat "$LB" 2>/dev/null)"
lintjson CONV009=5 SEC003=2
out="$(gate --update-baseline --reason "cleanup later" --approved-in-chat)"; rc=$?
[ "$rc" -ne 0 ] && [ "$(cat "$LB")" = "$before" ] && ok "refused (rc $rc), baseline unchanged" \
  || bad "the agent moved the baseline on its own flag (rc $rc): $(counts "$LB")" "$out"

echo "L2 the approve command refuses without a terminal"
out="$(bash "$P/bin/baseline-approve.sh" lint </dev/null 2>&1)"; rc=$?
[ "$rc" -ne 0 ] && [ ! -s "$P/.claude/baseline-approvals.tsv" ] && ok "no terminal → refused, no approval row" \
  || bad "approved without a terminal (rc $rc)" "$out"

echo "L3 with the person's approval the update lands"
human_approve "$P" lint
out="$(gate --update-baseline --reason "cleanup later")"; rc=$?
[ "$rc" -eq 0 ] && [ "$(counts "$LB")" = "{'CONV009': 5, 'SEC003': 2}" ] && ok "accepted: $(counts "$LB")" \
  || bad "approved update did not land (rc $rc)" "$out"

echo "L4 an approval covers exactly what the person saw"
lintjson CONV009=7 SEC003=2; gate --update-baseline --reason r >/dev/null
human_approve "$P" lint
lintjson CONV009=9 SEC003=2
out="$(gate --update-baseline --reason r)"; rc=$?
[ "$rc" -ne 0 ] && [ "$(counts "$LB")" = "{'CONV009': 5, 'SEC003': 2}" ] && ok "counts moved after approval → refused" \
  || bad "a stale approval moved the baseline (rc $rc): $(counts "$LB")" "$out"

echo "L5 deleting the baseline does not launder a rise"
rm -f "$LB"; lintjson CONV009=9 SEC003=2
out="$(gate --update-baseline)"; rc=$?
[ "$rc" -ne 0 ] && [ ! -f "$LB" ] && ok "re-creation needs a person (rc $rc)" \
  || bad "a deleted baseline was re-created at 9 with no approval (rc $rc)" "$out"

echo "C1/C2 conformance: accepting a regression needs the person"
C="$WORK/c"; newproj "$C"; mkdir -p "$C/architecture/modules/Orders"
printf 'Orders.Order\nOrders.ACT_Save\n' > "$C/PRESENT"
cat > "$C/mxcli" <<'EOF'
#!/usr/bin/env bash
cmd=""; while [ $# -gt 0 ]; do [ "$1" = -c ] && cmd="$2"; shift; done
name="${cmd##* }"
if grep -qx "$name" "$(dirname "$0")/PRESENT"; then echo "-- $name"; exit 0; fi
echo "Error: $name not found"; exit 1
EOF
chmod +x "$C/mxcli"
cat > "$C/architecture/modules/Orders/coverage-ledger.md" <<'EOF'
| Pointer | Kind | Name | Row | Proof | Acceptance | Status |
|---|---|---|---|---|---|---|
| `/domainEntities/0` | entity | Order | 1.1 | exec.sh | `DESCRIBE ENTITY Orders.Order` | built |
| `/microflows/0` | microflow | ACT_Save | 1.2 | exec.sh | `DESCRIBE MICROFLOW Orders.ACT_Save` | built |
EOF
conf() { ( cd "$C" && PROJECT_ROOT="$C" bash bin/conformance-check.sh --quiet "$@" ) 2>&1; }
CB="$C/docs/conformance/baseline.tsv"
conf >/dev/null
printf 'Orders.Order\n' > "$C/PRESENT"
before="$(cat "$CB")"
out="$(conf --update-baseline)"; rc=$?
[ "$rc" -ne 0 ] && [ "$(cat "$CB")" = "$before" ] && ok "C1 regression not baselined without the person (rc $rc)" \
  || bad "C1 the agent baselined a regression (rc $rc)" "$out"
human_approve "$C" conformance
out="$(conf --update-baseline)"; rc=$?
[ "$rc" -eq 0 ] && grep -q "ACT_Save\|/microflows/0.*STALE" "$CB" && grep -q STALE "$CB" && ok "C2 accepted after approval" \
  || bad "C2 approved rewrite did not land (rc $rc)" "$out"

echo "G1-G3 gate-check reports a baseline that moved without approval"
GC="$TK/bin/gate-check.sh"
gline() { bash "$GC" "$1" --no-html 2>/dev/null | grep '^Baselines'; }
printf '{\n  "counts": {"CONV009": 40, "SEC003": 2}\n}\n' > "$LB"   # a hand edit
l="$(gline "$P")"
case "$l" in *FAIL*lint*) ok "G1 hand-moved lint baseline: FAIL" ;; *) bad "G1 hand edit not flagged" "${l:-<no Baselines line>}" ;; esac
bash "$GC" "$P" 5 --no-html >/dev/null 2>"$WORK/g.err"; rc=$?
[ "$rc" -eq 1 ] && grep -q "BLOCKED by a baseline" "$WORK/g.err" && ok "G1 Stage 5 BLOCKED (exit 1)" \
  || bad "G1 Stage 5 not blocked by the hand edit (rc $rc)" "$(tail -3 "$WORK/g.err")"
human_approve "$P" lint --current
l="$(gline "$P")"
case "$l" in *PASS*) ok "G2 after the person approves the file as it is: PASS" ;; *) bad "G2 not PASS after --current approval" "$l" ;; esac
L="$WORK/legacy"; mkdir -p "$L/.claude"; cp "$LB" "$L/.claude/lint-baseline.json"
l="$(gline "$L")"
case "$l" in *MANUAL*) ok "G3 a baseline with no record: MANUAL" ;; *) bad "G3 unrecorded baseline not MANUAL" "${l:-<no Baselines line>}" ;; esac

echo ""
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
