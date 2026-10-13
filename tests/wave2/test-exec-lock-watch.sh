#!/usr/bin/env bash
# test-exec-lock-watch.sh — exec.sh's per-project lock, --commit-first, and the watch-compat advisory.
#
# Usage: bash tests/wave2/test-exec-lock-watch.sh [path-to-exec.sh]
#
# WHY (field run 2026-10-12, 20 UX tasks over three apps; #287, #284, #275, #289): 57 of 148
# exec.sh runs applied nothing — 26 refused on "uncommitted model changes" — and a machine-wide
# `pgrep "mxcli exec"` guard blocked an exec because a DIFFERENT project's test run was writing.
# Watch mode then silently missed a class of changes (~26 restarts), and nobody could tell a
# stale runtime from a defect.
#
# Covers
#   lock:   a live exec.sh on this project refuses the second (nothing written); a lock from a
#           dead pid is taken over with a note (new format AND the old bare-pid format); a lock
#           whose pid was reused by an unrelated process is stale; a live exec.sh on ANOTHER
#           project does not block; a running `mxcli exec` elsewhere does not block (note only);
#           the lock is gone after the run.
#   commit: the refusal names --commit-first; --commit-first commits exactly the model paths and
#           leaves an unrelated staged file staged and an unrelated edit uncommitted; it refuses
#           while Studio Pro holds the model even under FORCE_EXEC.
#   watch:  --watch-compat over REAL MDL (the toolkit's shipped scripts and fixtures; the two
#           statements not found in any shipped script are grepped out of the bug log / pending
#           issue that recorded them verbatim); the post-exec line in a real run; theme SCSS
#           newer than the run --local record (the captured handshake fixture) means restart.
#
# NOTHING here touches a real .mpr, mxcli, mxbuild or app. Throwaway git repos with stubs, as
# in test-bug07-08.sh.
set -uo pipefail

TOOLKIT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SUBJECT="${1:-$TOOLKIT/project-bin/exec.sh}"
case "$SUBJECT" in /*) ;; *) SUBJECT="$PWD/$SUBJECT" ;; esac
WORK="$(mktemp -d "${TMPDIR:-/tmp}/execlock.XXXXXX")" || exit 2
BG_PIDS=""
cleanup() { for p in $BG_PIDS; do kill -KILL "$p" 2>/dev/null; done; rm -rf "$WORK"; }
trap cleanup EXIT
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  ok   — $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL — $1"; }
has() { case "$2" in *"$3"*) ok "$1" ;; *) bad "$1 — missing '$3' in: $(printf '%s' "$2" | tail -5)" ;; esac; }
hasnt() { case "$2" in *"$3"*) bad "$1 — unexpected '$3'" ;; *) ok "$1" ;; esac; }
echo "== subject: $SUBJECT"

# ── Fixture projects ─────────────────────────────────────────────────────────
mkproj() {  # $1 = dir
  local P="$1"
  mkdir -p "$P/bin" "$P/mprcontents" "$P/mdlsource"
  printf 'not a real model\n' > "$P/Fixture.mpr"
  printf 'bson\n' > "$P/mprcontents/a.mxunit"
  printf 'CREATE MODULE "Nope";\n' > "$P/mdlsource/test.mdl"
  cp "$TOOLKIT/project-bin/_common.sh" "$TOOLKIT/project-bin/restore-mpr.sh" "$P/bin/"
  cp "$SUBJECT" "$P/bin/exec.sh"
  cat > "$P/bin/snapshot-mpr.sh" <<'SNAP'
#!/usr/bin/env bash
set -e
cd "$(dirname "$0")/.."
sleep "${SNAP_SLEEP:-0}"
D=".mpr-snapshots/$(date +%Y%m%d-%H%M%S)-$$"
mkdir -p "$D"; cp Fixture.mpr "$D/"; cp -r mprcontents "$D/"
echo "Snapshot saved: $D"
SNAP
  cat > "$P/mxcli" <<'MXCLI'
#!/usr/bin/env bash
case "${1:-}" in check) exit 0 ;; exec) echo "fake mxcli exec"; exit 0 ;; esac
exit 0
MXCLI
  chmod +x "$P/bin/"*.sh "$P/mxcli"
  ( cd "$P" && git init -q . && printf '.mpr-snapshots/\ndocs/\n.claude/\n' > .gitignore && git add -A \
    && git -c user.email=t@t -c user.name=t commit -qm fixture ) >/dev/null 2>&1
}
cat > "$WORK/mxbuild" <<'MXB'
#!/usr/bin/env bash
for a in "$@"; do case "$a" in --write-errors=*) printf '{"problems":[]}' > "${a#--write-errors=}" ;; esac; done
exit 0
MXB
chmod +x "$WORK/mxbuild"
P="$WORK/proj"; Q="$WORK/other"; mkproj "$P"; mkproj "$Q"
LOCK="$P/.mpr-snapshots/.exec.lock"

run() {  # $1 = project, rest = exec.sh args; prints output, returns rc
  ( cd "$1" && shift && GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t \
      SKIP_BASELINE=1 SP_RESTART=0 MXTK_NO_INSTALL=1 MXTK_NO_SCORE=1 MXBUILD_PATH="$WORK/mxbuild" ./bin/exec.sh "$@" ) 2>&1
}
bg_hold() {  # $1 = project — start an exec.sh that holds its lock ~8 s; echoes its pid
  ( cd "$1" && exec env SKIP_BASELINE=1 SP_RESTART=0 MXTK_NO_INSTALL=1 MXTK_NO_SCORE=1 SNAP_SLEEP=8 \
      MXBUILD_PATH="$WORK/mxbuild" ./bin/exec.sh mdlsource/test.mdl ) >"$WORK/bg.out" 2>&1 &
  echo $!
}
wait_lock() { local i; for i in $(seq 1 50); do [ -s "$1" ] && return 0; sleep 0.1; done; return 1; }
dead_pid() { sh -c 'exit 0' & local p=$!; wait "$p" 2>/dev/null; echo "$p"; }

echo "-- lock: live holder on THIS project refuses"
H="$(bg_hold "$P")"; BG_PIDS="$BG_PIDS $H"
if wait_lock "$LOCK"; then
  OUT="$(run "$P" mdlsource/test.mdl)"; RC=$?
  [ "$RC" -ne 0 ] && ok "second exec refused while the first holds the lock (rc $RC)" || bad "second exec ran concurrently (rc 0)"
  has  "refusal names the holder pid" "$OUT" "PID $H"
  has  "refusal says no manual rm is needed" "$OUT" "no manual rm"
  hasnt "the refused run wrote nothing" "$OUT" "fake mxcli exec"
else
  bad "[setup] background exec never took the lock"
fi

echo "-- other project not blocked by a live exec.sh here"
OUT="$(run "$Q" mdlsource/test.mdl)"; RC=$?
[ "$RC" -eq 0 ] && ok "exec on another project ran while this one is locked" || bad "another project was blocked (rc $RC): $(printf '%s' "$OUT" | tail -3)"
kill -KILL "$H" 2>/dev/null; wait "$H" 2>/dev/null

echo "-- lock: dead holder is taken over (the SIGKILL above left it behind)"
[ -f "$LOCK" ] && ok "[setup] SIGKILLed run left its lock" || bad "[setup] no lock left behind — case proves nothing"
OUT="$(run "$P" mdlsource/test.mdl)"; RC=$?
[ "$RC" -eq 0 ] && ok "exec ran over a stale lock (rc 0)" || bad "stale lock blocked (rc $RC): $(printf '%s' "$OUT" | tail -3)"
has "takeover is said out loud" "$OUT" "taking it over"
has "the run actually wrote" "$OUT" "fake mxcli exec"
[ -f "$LOCK" ] && bad "lock left behind after a clean run" || ok "lock removed after the run"

echo "-- lock: old bare-pid format, dead pid"
dead_pid > "$LOCK"
OUT="$(run "$P" mdlsource/test.mdl)"; RC=$?
[ "$RC" -eq 0 ] && has "pre-change lock format taken over" "$OUT" "taking it over" || bad "old-format stale lock blocked (rc $RC)"

echo "-- lock: pid reused by an unrelated live process"
sleep 30 & S=$!; BG_PIDS="$BG_PIDS $S"
if [ -n "$(ps -o args= -p "$S" 2>/dev/null)" ]; then
  printf '%s 1700000000 old.mdl\n' "$S" > "$LOCK"
  OUT="$(run "$P" mdlsource/test.mdl)"; RC=$?
  [ "$RC" -eq 0 ] && has "a live non-exec.sh pid is a stale lock" "$OUT" "taking it over" || bad "reused pid blocked (rc $RC)"
else
  ok "[skip] ps -o args= unavailable here — kill -0 alone decides (Git Bash path)"
fi
kill -KILL "$S" 2>/dev/null; wait "$S" 2>/dev/null

echo "-- a raw 'mxcli exec' elsewhere on the machine is a note, not a refusal"
bash -c 'exec -a "mxcli exec /elsewhere/other.mdl" sleep 20' & R=$!; BG_PIDS="$BG_PIDS $R"
sleep 0.3
OUT="$(run "$P" mdlsource/test.mdl)"; RC=$?
[ "$RC" -eq 0 ] && ok "not blocked by another project's raw mxcli exec" || bad "machine-wide block still active (rc $RC)"
if pgrep -f "mxcli exec" >/dev/null 2>&1; then has "  and it is mentioned as a note" "$OUT" "not blocking"; fi   # portability-ok: guarded by its own exit status; no pgrep, no assertion
kill -KILL "$R" 2>/dev/null; wait "$R" 2>/dev/null

echo "-- commit-first"
printf 'edited by studio pro\n' >> "$P/mprcontents/a.mxunit"
printf 'new unit\n' > "$P/mprcontents/b.mxunit"
printf 'unrelated edit\n' > "$P/notes.txt"; ( cd "$P" && git add notes.txt && git -c user.email=t@t -c user.name=t commit -qm notes && printf 'more\n' >> notes.txt )
printf 'unrelated staged\n' > "$P/staged.txt"; ( cd "$P" && git add staged.txt )
OUT="$(run "$P" mdlsource/test.mdl)"; RC=$?
[ "$RC" -ne 0 ] && ok "default unchanged: dirty model refused" || bad "dirty model no longer refused by default"
has "the refusal points at --commit-first" "$OUT" "--commit-first"
HEAD0="$(git -C "$P" rev-parse HEAD)"
OUT="$(run "$P" --commit-first mdlsource/test.mdl)"; RC=$?
[ "$RC" -eq 0 ] && ok "--commit-first committed and executed (rc 0)" || bad "--commit-first failed (rc $RC): $(printf '%s' "$OUT" | tail -4)"
has "prints what it will commit" "$OUT" "mprcontents/b.mxunit"
has "says the other staged path stays out" "$OUT" "1 other staged path"
FILES="$(git -C "$P" diff --name-only "$HEAD0" HEAD | sort | tr '\n' ' ')"
[ "$FILES" = "mprcontents/a.mxunit mprcontents/b.mxunit " ] && ok "commit holds exactly the model paths" || bad "commit holds: $FILES"
git -C "$P" diff --cached --name-only | grep -qx staged.txt && ok "unrelated staged file still staged, not committed" || bad "staged.txt lost its staged state"
git -C "$P" status --porcelain notes.txt | grep -q . && ok "unrelated edit left uncommitted" || bad "notes.txt was committed"
git -C "$P" log -1 --format=%s | grep -q 'before exec.sh test.mdl' && ok "commit message names the script" || bad "commit message: $(git -C "$P" log -1 --format=%s)"

echo "-- commit-first refuses while Studio Pro holds the model"
printf 'sp edit\n' >> "$P/mprcontents/a.mxunit"
sleep 30 & SP=$!; BG_PIDS="$BG_PIDS $SP"
printf '{"ProcessId":%s}\n' "$SP" > "$P/Fixture.mpr.lock"
HEAD1="$(git -C "$P" rev-parse HEAD)"
OUT="$(FORCE_EXEC=1 run "$P" --commit-first mdlsource/test.mdl)"; RC=$?
[ "$RC" -ne 0 ] && ok "refused under FORCE_EXEC (rc $RC)" || bad "committed/executed while SP holds the model"
has "says why" "$OUT" "Studio Pro holds"
[ "$(git -C "$P" rev-parse HEAD)" = "$HEAD1" ] && ok "nothing committed" || bad "a commit was made while SP held the model"
hasnt "nothing executed" "$OUT" "fake mxcli exec"
kill -KILL "$SP" 2>/dev/null; wait "$SP" 2>/dev/null; rm -f "$P/Fixture.mpr.lock"
( cd "$P" && git checkout -q -- mprcontents )

echo "-- watch-compat over real MDL"
AG="$TOOLKIT/skills/agents-examples"; GAL="$TOOLKIT/examples/stylegallery/mdlsource/gallery"
PFM="$TOOLKIT/tests/wave2/fixtures/page-fidelity-mocks"
wc_() { (cd "$WORK" && bash "$SUBJECT" --watch-compat "$1" 2>&1); }
expect() {  # $1 file  $2 expected prefix  $3 reason substring (or "")  $4 label
  [ -f "$1" ] || { bad "$4 — golden input missing: ${1#$TOOLKIT/}"; return; }
  local o; o="$(wc_ "$1")"
  case "$o" in "$2"*) ;; *) bad "$4 → expected '$2', got: $o"; return ;; esac
  [ -z "$3" ] || case "$o" in *"$3"*) ;; *) bad "$4 → reason '$3' missing: $o"; return ;; esac
  ok "$4 → ${o%% (*}"
}
expect "$AG/tool-write.example.mdl"   "restart needed" "microflow created or recreated" "create or modify microflow (tool-write)"
expect "$GAL/05-demo-data.mdl"        "restart needed" "entity created or changed"      "non-persistent entities + microflows + grants (05-demo-data)"
expect "$GAL/05-demo-data.mdl"        "restart needed" "access rule changed (GRANT)"    "  and names the grants"
expect "$GAL/00-module.mdl"           "restart needed" "module/user role"               "create module role (00-module)"
expect "$GAL/90-gallery-home.mdl"     "restart needed" "new page"                       "plain create page (90-gallery-home)"
expect "$PFM/bind-contract-alter.mdl" "watch can apply this" "" "alter page set ImageUrl — not a page Url (bind-contract-alter)"
expect "$GAL/13-badges-chips.mdl"     "watch can apply this" "" "create snippet (13-badges-chips)"
expect "$AG/agent-snippet.example.mdl" "watch can apply this" "" "create or modify snippet with comments (agent-snippet)"
# Statements no shipped script contains, taken verbatim from where a real run recorded them.
grep -m1 -oE 'alter entity M\.Item add attribute Flag: Boolean;' \
  "$TOOLKIT/bug-logs/pending-github-issues/exec-non-transactional-silent-skip.md" > "$WORK/attr.mdl"
[ -s "$WORK/attr.mdl" ] && expect "$WORK/attr.mdl" "restart needed" "attribute added" "alter entity ... add attribute (pending issue, verbatim)" \
                        || bad "golden 'alter entity ... add attribute' line not found in the pending issue"
grep -q 'alter page … { set Url = '"'"'…'"'"'; }' "$TOOLKIT/bug-logs/mxcli-bugs.md" \
  && ok "[golden] bug log records 'alter page … { set Url = '…'; }' as a working statement" \
  || bad "[golden] the set Url row is gone from bug-logs/mxcli-bugs.md"
printf "alter page Shop.Order_Overview { set Url = 'orders'; }\n" > "$WORK/url.mdl"
expect "$WORK/url.mdl" "restart needed" "page URL" "alter page { set Url = ... } (bug-log shape)"
printf -- "-- create microflow Shop.ACT_X in a comment\nalter page Shop.P { set Caption = 'create microflow X; grant' on t1 }\n" > "$WORK/noise.mdl"
expect "$WORK/noise.mdl" "watch can apply this" "" "comments and string literals never count"

echo "-- watch-compat in a real run"
cp "$GAL/05-demo-data.mdl" "$P/mdlsource/demo.mdl"
OUT="$(run "$P" mdlsource/demo.mdl)"; RC=$?
has "post-exec line says restart needed" "$OUT" "→ Watch: restart needed"
has "post-exec line points at the scoped restart helper" "$OUT" "./bin/app-restart.sh"
has "and at ui-loop.md for the table and the symptoms" "$OUT" "skills/ui-loop.md"
OUT="$(run "$P" mdlsource/test.mdl)"
hasnt "a module-only script is not called restart" "$OUT" "restart needed"
# Theme SCSS newer than the running app's boot (handshake = the captured run-local.json).
mkdir -p "$P/.mxcli" "$P/themesource/shop/web"
sed -e "s|^  \"pid\": [0-9]*|  \"pid\": $$|" -e 's/^  "adminPass": "[^"]*"/  "adminPass": "x"/' \
  "$TOOLKIT/tests/wave2/fixtures/run-local/run-local.json" > "$P/.mxcli/run-local.json"
touch -t 202601010000 "$P/.mxcli/run-local.json"
printf '.x{color:red}\n' > "$P/themesource/shop/web/main.scss"
cp "$PFM/bind-contract-alter.mdl" "$P/mdlsource/page.mdl"
( cd "$P" && git add mdlsource themesource && git -c user.email=t@t -c user.name=t commit -qm s ) >/dev/null 2>&1
OUT="$(run "$P" mdlsource/page.mdl)"
has "a page-only script after an SCSS edit → restart, naming the file" "$OUT" "themesource/shop/web/main.scss"
touch "$P/.mxcli/run-local.json"
OUT="$(run "$P" mdlsource/page.mdl)"
has "same script, SCSS older than the boot → watch applies it" "$OUT" "→ Watch: watch can apply this"

echo ""
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
