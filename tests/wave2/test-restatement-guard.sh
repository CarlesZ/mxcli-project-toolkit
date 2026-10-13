#!/usr/bin/env bash
# test-restatement-guard.sh — exec.sh's restatement guards (#261 stale DESCRIBE, #269 co-owned
# documents) and its rollback when mxbuild crashes on the written model (#309 inbox).
#
# Usage: bash tests/wave2/test-restatement-guard.sh [path-to-exec.sh]
#        script-owners.sh and describe-baseline.sh are taken from the same directory as exec.sh.
#
# Covers
#   owners:   `docs` over REAL MDL — the mxcli v0.23.0 DESCRIBE captures, the shipped StyleGallery
#             mdlsource tree, skills/agents-examples — matches a plain grep of statement heads
#             (34); the StyleGallery tree reports 0 of 20 co-owned. `check`: an unrecorded older
#             owner, an unrecorded newer owner (a replay), `-- supersedes:` settles it, and a
#             superseded script replayed is a conflict; `superseded-by:` in the old script works.
#   baseline: `stamp` writes one header per restated document from a DESCRIBE (the captures,
#             replayed by a fake mxcli); `verify` is SAME on the same model, DRIFT when the live
#             microflow's message changed (the #261 shape), DRIFT when an absent doc appeared,
#             and NOBASELINE (exit 2) without a header.
#   exec.sh:  warns by default and still writes, with the warning in the BUILD-LOG row;
#             MXTK_RESTATE_GUARD=refuse and exec approval `ask` refuse with nothing written;
#             MXTK_RESTATE_GUARD=warn overrides ask; =off is silent.
#   crash:    mxbuild clean on the baseline, exit 1 with no errors file after the write → the
#             model on disk equals the snapshot again and the BUILD-LOG row says rolled back.
#             Without a measured baseline (SKIP_BASELINE) the write is still kept, as before.
#
# Against master's exec.sh every exec.sh/crash case fails, and the owners/baseline cases fail
# because the two scripts do not exist there. NOTHING here touches a real .mpr, mxcli or mxbuild.
set -uo pipefail

TOOLKIT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SUBJECT="${1:-$TOOLKIT/project-bin/exec.sh}"
case "$SUBJECT" in /*) ;; *) SUBJECT="$PWD/$SUBJECT" ;; esac
BIN="$(dirname "$SUBJECT")"
OWNERS="$BIN/script-owners.sh"
BASEL="$BIN/describe-baseline.sh"
CAP="$TOOLKIT/tests/wave2/fixtures/context-pack/capture/describe"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/restate.XXXXXX")" || exit 2
trap 'rm -rf "$WORK"' EXIT
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  ok   — $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL — $1"; }
has() { case "$2" in *"$3"*) ok "$1" ;; *) bad "$1 — missing '$3' in: $(printf '%s' "$2" | tail -4)" ;; esac; }
hasnt() { case "$2" in *"$3"*) bad "$1 — unexpected '$3'" ;; *) ok "$1" ;; esac; }
echo "== subject: $SUBJECT"
for f in "$OWNERS" "$BASEL"; do [ -f "$f" ] || bad "[setup] $(basename "$f") not found beside exec.sh"; done

# ── owners: parser over real MDL ─────────────────────────────────────────────
echo "-- owners: docs over real MDL"
REAL="$(ls "$CAP"/*.out "$TOOLKIT"/examples/stylegallery/mdlsource/gallery/*.mdl "$TOOLKIT"/skills/agents-examples/*.mdl)"
GREP_N=0; DOCS_N=0
for f in $REAL; do
  g="$(grep -ciE '^[[:space:]]*create[[:space:]]+(or[[:space:]]+(modify|replace)[[:space:]]+)?(microflow|nanoflow|page|snippet)[[:space:]]' "$f" || true)"
  d="$(bash "$OWNERS" docs "$f" 2>/dev/null | grep -c . || true)"
  GREP_N=$((GREP_N + g)); DOCS_N=$((DOCS_N + d))
done
[ "$GREP_N" -eq 34 ] && ok "[setup] 34 statement heads in the golden files" || bad "[setup] golden grep found $GREP_N, expected 34"
[ "$DOCS_N" -eq "$GREP_N" ] && ok "docs lists every head ($DOCS_N)" || bad "docs listed $DOCS_N, grep $GREP_N"
OUT="$(bash "$OWNERS" docs "$CAP/MICROFLOW__Sales.ACT_ApprovalStep_Reject.out" 2>&1)"
has "a DESCRIBE capture parses as a modify of its microflow" "$OUT" "MICROFLOW	Sales.ACT_ApprovalStep_Reject	"
OUT="$(bash "$OWNERS" count "$TOOLKIT/examples/stylegallery" 2>&1)"
[ "$OUT" = "0 20" ] && ok "StyleGallery tree: 0 of 20 co-owned" || bad "StyleGallery count '$OUT', expected '0 20'"

# ── owners: check ────────────────────────────────────────────────────────────
echo "-- owners: check"
O="$WORK/own"; mkdir -p "$O/mdlsource"
cp "$CAP/MICROFLOW__Sales.ACT_ApprovalStep_Reject.out" "$O/mdlsource/05-reject.mdl"
cp "$CAP/MICROFLOW__Sales.ACT_ApprovalStep_Approve.out" "$O/mdlsource/06-approve.mdl"
cp "$CAP/MICROFLOW__Sales.ACT_ApprovalStep_Reject.out" "$O/mdlsource/09-reject-fix.mdl"
OUT="$(bash "$OWNERS" report "$O" 2>&1)"
has "report names the co-owned microflow and both scripts" "$OUT" "MICROFLOW Sales.ACT_ApprovalStep_Reject — 2 scripts: mdlsource/05-reject.mdl, mdlsource/09-reject-fix.mdl"
has "report summary" "$OUT" "multi-owner: 1 of 2"
OUT="$(bash "$OWNERS" check "$O/mdlsource/09-reject-fix.mdl" "$O" 2>&1)"; RC=$?
[ "$RC" -eq 1 ] && has "new restatement without a header: older owner named" "$OUT" "older owner mdlsource/05-reject.mdl" || bad "check rc $RC on an unrecorded older owner"
OUT="$(bash "$OWNERS" check "$O/mdlsource/05-reject.mdl" "$O" 2>&1)"; RC=$?
[ "$RC" -eq 1 ] && has "replaying the older script: newer owner named" "$OUT" "newer owner mdlsource/09-reject-fix.mdl" || bad "check rc $RC on a replay"
OUT="$(bash "$OWNERS" check "$O/mdlsource/06-approve.mdl" "$O" 2>&1)"; RC=$?
[ "$RC" -eq 0 ] && ok "a sole owner passes" || bad "sole owner rc $RC: $OUT"
{ echo "-- supersedes: 05-reject.mdl"; cat "$CAP/MICROFLOW__Sales.ACT_ApprovalStep_Reject.out"; } > "$O/mdlsource/09-reject-fix.mdl"
OUT="$(bash "$OWNERS" check "$O/mdlsource/09-reject-fix.mdl" "$O" 2>&1)"; RC=$?
[ "$RC" -eq 0 ] && ok "-- supersedes: settles it for the new owner" || bad "supersedes ignored (rc $RC): $OUT"
OUT="$(bash "$OWNERS" check "$O/mdlsource/05-reject.mdl" "$O" 2>&1)"; RC=$?
[ "$RC" -eq 1 ] && has "replaying a superseded script is a conflict" "$OUT" "superseded: mdlsource/09-reject-fix.mdl supersedes this script" || bad "superseded replay rc $RC"
cp "$CAP/MICROFLOW__Sales.ACT_ApprovalStep_Reject.out" "$O/mdlsource/09-reject-fix.mdl"
{ echo "-- superseded-by: 09-reject-fix.mdl"; cat "$CAP/MICROFLOW__Sales.ACT_ApprovalStep_Reject.out"; } > "$O/mdlsource/05-reject.mdl"
OUT="$(bash "$OWNERS" check "$O/mdlsource/09-reject-fix.mdl" "$O" 2>&1)"; RC=$?
[ "$RC" -eq 0 ] && ok "-- superseded-by: in the old script settles it too" || bad "superseded-by ignored (rc $RC): $OUT"

# ── fixture project for baseline + exec.sh ───────────────────────────────────
P="$WORK/proj"
mkdir -p "$P/bin" "$P/mprcontents" "$P/mdlsource" "$P/live"
printf 'not a real model\n' > "$P/Fixture.mpr"
printf 'bson\n' > "$P/mprcontents/a.mxunit"
cp "$TOOLKIT/project-bin/_common.sh" "$TOOLKIT/project-bin/restore-mpr.sh" "$P/bin/"
cp "$SUBJECT" "$P/bin/exec.sh"
for f in "$OWNERS" "$BASEL"; do [ -f "$f" ] && cp "$f" "$P/bin/"; done
cat > "$P/bin/snapshot-mpr.sh" <<'SNAP'
#!/usr/bin/env bash
set -e
cd "$(dirname "$0")/.."
D=".mpr-snapshots/$(date +%Y%m%d-%H%M%S)-$$"
mkdir -p "$D"; cp Fixture.mpr "$D/"; cp -r mprcontents "$D/"
echo "Snapshot saved: $D"
SNAP
# Fake mxcli: check passes, exec appends to the model, DESCRIBE replays live/<KIND>__<Name>.out
# (copies of the v0.23.0 captures) and answers "not found" for anything else, as the real one did.
cat > "$P/mxcli" <<'MXCLI'
#!/usr/bin/env bash
D="$(cd "$(dirname "$0")" && pwd)"
case "${1:-}" in
  check) exit 0 ;;
  exec)  echo "fake mxcli exec"; echo "written by the script" >> "$D/Fixture.mpr"; exit 0 ;;
esac
q="${4:-}"; q="${q#DESCRIBE }"; name="${q##* }"; kind="${q% *}"
f="$D/live/${kind}__${name}.out"
[ -f "$f" ] && { cat "$f"; exit 0; }
echo "Error: $(printf '%s' "$kind" | tr 'A-Z' 'a-z') not found: $name" >&2; exit 1
MXCLI
cat > "$WORK/mxbuild" <<'MXB'
#!/usr/bin/env bash
OUT=""; for a in "$@"; do case "$a" in --write-errors=*) OUT="${a#--write-errors=}" ;; esac; done
n=$(( $(cat "$MXB_COUNT" 2>/dev/null || echo 0) + 1 )); echo "$n" > "$MXB_COUNT"
if [ "${MODE_BUILD:-clean}" = crash-after-write ] && grep -q 'written by the script' "$MXB_MPR"; then
  rm -f "$OUT"; echo "An error occurred when trying to set the 'DestinationEntity' property of a Entity ref step in a Page."; exit 1
fi
[ -n "$OUT" ] && printf '{"problems":[]}' > "$OUT"; exit 0
MXB
chmod +x "$P/bin/"*.sh "$P/mxcli" "$WORK/mxbuild"
cp "$CAP/MICROFLOW__Sales.ACT_ApprovalStep_Reject.out" "$CAP/MICROFLOW__Sales.ACT_ApprovalStep_Approve.out" "$P/live/"
( cd "$P" && git init -q . && printf '.mpr-snapshots/\ndocs/\n.claude/\n' > .gitignore && git add -A \
  && git -c user.email=t@t -c user.name=t commit -qm fixture ) >/dev/null 2>&1
LOG="$P/docs/BUILD-LOG.md"
export MXB_COUNT="$WORK/mxb.count" MXB_MPR="$P/Fixture.mpr"
commit_model() { ( cd "$P" && git add -A && git -c user.email=t@t -c user.name=t commit -qm m ) >/dev/null 2>&1; }

# ── baseline: stamp / verify ─────────────────────────────────────────────────
echo "-- baseline: stamp and verify"
S="$P/mdlsource/10-reject-msg.mdl"
cp "$CAP/MICROFLOW__Sales.ACT_ApprovalStep_Reject.out" "$S"
cat "$CAP/MICROFLOW__Sales.ACT_ApprovalStep_Approve.out" >> "$S"
sed 's/ACT_ApprovalStep_Approve/ACT_ApprovalStep_Hold/g' "$CAP/MICROFLOW__Sales.ACT_ApprovalStep_Approve.out" >> "$S"
OUT="$(cd "$P" && bash bin/describe-baseline.sh verify "$S" 2>&1)"; RC=$?
[ "$RC" -eq 2 ] && has "no header: NOBASELINE with the restated count" "$OUT" "NOBASELINE	3" || bad "verify without header rc $RC: $OUT"
OUT="$(cd "$P" && bash bin/describe-baseline.sh stamp "$S" 2>&1)"; RC=$?
[ "$RC" -eq 0 ] && ok "stamp rc 0" || bad "stamp rc $RC: $OUT"
[ "$(grep -c '^-- baseline: ' "$S" 2>/dev/null)" = 3 ] && ok "three header lines" || bad "header lines: $(grep -c '^-- baseline: ' "$S" 2>/dev/null)"
grep -q '^-- baseline: Sales.ACT_ApprovalStep_Hold absent' "$S" && ok "a document not in the model is stamped absent" || bad "no absent line"
grep -qE '^-- baseline: Sales.ACT_ApprovalStep_Reject sha256=[0-9a-f]{64}' "$S" && ok "existing document stamped with a sha256" || bad "no sha256 line"
( cd "$P" && bash bin/describe-baseline.sh stamp "$S" ) >/dev/null 2>&1
[ "$(grep -c '^-- baseline: ' "$S" 2>/dev/null)" = 3 ] && ok "re-stamp replaces, never duplicates" || bad "re-stamp duplicated headers"
OUT="$(cd "$P" && bash bin/describe-baseline.sh verify "$S" 2>&1)"; RC=$?
[ "$RC" -eq 0 ] && ok "unchanged model: verify rc 0" || bad "verify on unchanged model rc $RC: $OUT"
# The #261 shape: an earlier script changed the live message after this one was drafted.
sed "s/A comment is required to reject./Please add a comment before rejecting./" "$CAP/MICROFLOW__Sales.ACT_ApprovalStep_Reject.out" > "$P/live/MICROFLOW__Sales.ACT_ApprovalStep_Reject.out"
cp "$CAP/MICROFLOW__Sales.ACT_ApprovalStep_Approve.out" "$P/live/MICROFLOW__Sales.ACT_ApprovalStep_Hold.out"
OUT="$(cd "$P" && bash bin/describe-baseline.sh verify "$S" 2>&1)"; RC=$?
[ "$RC" -eq 1 ] && ok "changed live body: verify rc 1" || bad "verify rc $RC after drift"
has "DRIFT row names the changed microflow" "$OUT" "DRIFT	Sales.ACT_ApprovalStep_Reject	changed since the script was drafted"
has "the diff shows the live message the script would revert" "$OUT" "+    validation feedback \$ApprovalStep/Comments message 'Please add a comment before rejecting.'"
has "absent at draft, present now" "$OUT" "DRIFT	Sales.ACT_ApprovalStep_Hold	created since the script was drafted"
hasnt "the unchanged microflow is not reported" "$OUT" "DRIFT	Sales.ACT_ApprovalStep_Approve"
rm -f "$P/live/MICROFLOW__Sales.ACT_ApprovalStep_Hold.out"

# ── exec.sh: warn / refuse / ask / off ───────────────────────────────────────
run() {  # env... ; runs exec.sh on $S; prints output; rc in $WORK/rc
  ( cd "$P" && SKIP_BASELINE=1 SKIP_DOCTOR=1 SP_RESTART=0 MXTK_NO_INSTALL=1 MXTK_NO_SCORE=1 \
      MXBUILD_PATH="$WORK/mxbuild" ./bin/exec.sh "${RUN_SCRIPT:-mdlsource/10-reject-msg.mdl}" ) > "$WORK/out" 2>&1
  echo $? > "$WORK/rc"; cat "$WORK/out"
}
reset_model() { ( cd "$P" && git checkout -q -- Fixture.mpr mprcontents ) 2>/dev/null; }
cp "$CAP/MICROFLOW__Sales.ACT_ApprovalStep_Reject.out" "$P/mdlsource/05-reject.mdl"
commit_model

echo "-- exec.sh: default warns and writes"
OUT="$(run)"; RC=$(cat "$WORK/rc")
[ "$RC" -eq 0 ] && ok "warn mode: exit 0" || bad "warn mode rc $RC: $(tail -3 "$WORK/out")"
has "co-owner warning" "$OUT" "also owned by another mdlsource/ script"
has "  names the older owner" "$OUT" "older owner mdlsource/05-reject.mdl"
has "stale-draft warning" "$OUT" "Stale draft"
has "  names the drifted microflow" "$OUT" "Sales.ACT_ApprovalStep_Reject — changed since the script was drafted"
has "the write happened" "$OUT" "fake mxcli exec"
ROW="$(grep '10-reject-msg.mdl' "$LOG" 2>/dev/null | tail -1)"
has "BUILD-LOG row carries the stale-baseline warning" "$ROW" "stale baseline: Sales.ACT_ApprovalStep_Reject"
has "BUILD-LOG row carries the co-owner warning" "$ROW" "co-owned: Sales.ACT_ApprovalStep_Reject"
reset_model

echo "-- exec.sh: MXTK_RESTATE_GUARD=refuse"
OUT="$(MXTK_RESTATE_GUARD=refuse run)"; RC=$(cat "$WORK/rc")
[ "$RC" -eq 1 ] && ok "refuse: exit 1" || bad "refuse rc $RC"
hasnt "refuse: nothing written" "$OUT" "fake mxcli exec"
hasnt "refuse: no snapshot taken" "$OUT" "Snapshot saved"
grep -q 'restatement guard refused' "$LOG" 2>/dev/null && ok "refusal logged" || bad "no refusal row"

echo "-- exec.sh: exec approval ask refuses; MXTK_RESTATE_GUARD=warn overrides"
OUT="$(MXTK_ROOT="$TOOLKIT" CLAUDE_EXEC_APPROVAL=ask run)"; RC=$(cat "$WORK/rc")
[ "$RC" -eq 1 ] && hasnt "ask: nothing written" "$OUT" "fake mxcli exec" || bad "ask mode rc $RC (expected refusal)"
OUT="$(MXTK_ROOT="$TOOLKIT" CLAUDE_EXEC_APPROVAL=ask MXTK_RESTATE_GUARD=warn run)"; RC=$(cat "$WORK/rc")
[ "$RC" -eq 0 ] && has "ask + warn override: written" "$OUT" "fake mxcli exec" || bad "override rc $RC"
reset_model

echo "-- exec.sh: off is silent"
OUT="$(MXTK_RESTATE_GUARD=off run)"; RC=$(cat "$WORK/rc")
[ "$RC" -eq 0 ] && hasnt "off: no warning" "$OUT" "Stale draft" || bad "off rc $RC"
reset_model

echo "-- exec.sh: a fresh stamp after the drift is clean"
( cd "$P" && bash bin/describe-baseline.sh stamp "$S" ) >/dev/null 2>&1
{ echo "-- supersedes: 05-reject.mdl"; cat "$S"; } > "$S.tmp" && mv "$S.tmp" "$S"
commit_model
OUT="$(run)"; RC=$(cat "$WORK/rc")
[ "$RC" -eq 0 ] && hasnt "re-stamped + supersedes: no warning" "$OUT" "⚠ Restatement" || bad "rc $RC"
hasnt "  and no stale-draft warning" "$OUT" "Stale draft"
reset_model

# ── crash: mxbuild ran on the baseline, crashed after the write ──────────────
echo "-- crash: mxbuild crashes on the written model"
printf 'CREATE MODULE "Nope";\n' > "$P/mdlsource/20-crash.mdl"; commit_model
BEFORE="$(cat "$P/Fixture.mpr")"; rm -f "$MXB_COUNT"
( cd "$P" && SKIP_DOCTOR=1 SP_RESTART=0 MXTK_NO_INSTALL=1 MXTK_NO_SCORE=1 MODE_BUILD=crash-after-write \
    MXBUILD_PATH="$WORK/mxbuild" ./bin/exec.sh mdlsource/20-crash.mdl ) > "$WORK/out" 2>&1; RC=$?
OUT="$(cat "$WORK/out")"
[ "$(cat "$MXB_COUNT" 2>/dev/null)" -ge 2 ] && ok "[setup] baseline measured, then the gate ran" || bad "[setup] mxbuild ran $(cat "$MXB_COUNT" 2>/dev/null) time(s)"
[ "$RC" -eq 1 ] && ok "crash: exit 1" || bad "crash rc $RC"
[ "$(cat "$P/Fixture.mpr")" = "$BEFORE" ] && ok "crash: model on disk equals the snapshot" || bad "crash: the write was KEPT on a model mxbuild cannot load"
ROW="$(grep '20-crash.mdl' "$LOG" 2>/dev/null | tail -1)"
has "crash: BUILD-LOG row says rolled back" "$ROW" "script rolled back"
reset_model

echo "-- crash without a measured baseline keeps the write (machine may be the cause)"
( cd "$P" && SKIP_BASELINE=1 SKIP_DOCTOR=1 SP_RESTART=0 MXTK_NO_INSTALL=1 MXTK_NO_SCORE=1 MODE_BUILD=crash-after-write \
    MXBUILD_PATH="$WORK/mxbuild" ./bin/exec.sh mdlsource/20-crash.mdl ) > "$WORK/out" 2>&1; RC=$?
[ "$RC" -eq 1 ] && ok "[guard] exit 1" || bad "[guard] rc $RC"
grep -q 'written by the script' "$P/Fixture.mpr" && ok "[guard] unmeasured baseline: write kept, as before" || bad "unmeasured baseline rolled back"
has "  and the message says STOP, not 'Open in SP'" "$(cat "$WORK/out")" "STOP: the model may not load"
reset_model

echo ""
echo "== $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
