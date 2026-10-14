#!/usr/bin/env bash
# Fixture for the Studio Pro revision note (project-bin/mx-metadata-note.py) and the post-commit /
# post-rewrite hooks + notes push refspec project-bin/install-project-hooks.sh installs.
# 2026-10-12: every CLI commit on a field project showed "Model changes 0" in Studio Pro History,
# because the hand-written note carried "ModelChanges":[].
#
# Golden input is captured, not written: fixtures/mx-metadata-note/ holds four real .mxunit files
# (MyFirstModule's module, MyFirstLogic microflow, domain model, module security -- Mendix template
# content, no app data), their verbatim Unit-table rows and the real .mpr schema, all from a
# Mendix 11.15.0 model. The test assembles them into throwaway git repos (single-tree AND two-tree)
# and asserts the note Studio Pro would read. The field run against real Studio Pro is cited in the
# script header, not repeated here.
#
# usage: bash tests/wave2/test-mx-metadata-note.sh      (no argument; subjects are the project-bin files)
# Every repo here sets HEAD to main explicitly, so the result does not depend on init.defaultBranch;
# run it under both:  GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=init.defaultBranch GIT_CONFIG_VALUE_0=master
set -uo pipefail
TK="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
FX="$TK/tests/wave2/fixtures/mx-metadata-note"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/mx-metadata-note.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; [ -n "${2:-}" ] && printf '%s\n' "$2" | sed 's/^/       /'; }
. "$TK/bin/lib/portable.sh"; require_py

MOD=16747dc6-b6b7-42ae-aabf-255dca2aeeaf; MF=4a8475b3-14cb-4100-8963-58f2fd3a0be8
DM=84776610-13b2-48cb-a265-d5e984d63129; MS=3f64baa2-b85c-4999-9a3c-3cc38382eb54
PL=0f0f0f0f-1111-4222-8333-444444444444   # a project-level unit: real ModuleSecurity bytes, placed under the root
export MODEL_UNVERIFIED_OK=1               # the pre-commit gate is test-model-stamp.sh's subject, not this one's
export GIT_TERMINAL_PROMPT=0
unset MXTK_TS_REMOTES
TSURL=https://git.api.mendix.com/00000000-0000-0000-0000-000000000000.git
# A Team Server remote that is really a local bare repo: url.<bare>.insteadOf keeps the configured
# URL on git.api.mendix.com (what the installer detects) while every fetch/push goes local.
bare()   { git init -q --bare "$1" && git -C "$1" symbolic-ref HEAD refs/heads/main; }
tsremote() { git config "url.$1.insteadOf" "$TSURL"; git remote add teamserver "$TSURL"; }
nmd()    { "$PY" ./bin/mx-metadata-note.py "$@"; }   # resolve_py's interpreter, never the shebang

# mkmodel <model-dir> <unit>... : write <model-dir>/App.mpr (real schema + captured rows) and the units
mkmodel() {
  local d="$1"; shift
  "$PY" - "$FX" "$d" "$@" <<'PY'
import os, sqlite3, sys, shutil
fx, d, units = sys.argv[1], sys.argv[2], sys.argv[3:]
rows = {}
for line in open(f"{fx}/unit-rows.tsv"):
    if line.startswith("#"): continue
    u, c, n = line.rstrip("\n").split("\t"); rows[u] = (c, n)
def blob(g):
    b = bytes.fromhex(g.replace("-", "")); return b[3::-1] + b[5:3:-1] + b[7:5:-1] + b[8:]
root = "4d827743a25b514b800e658754fc369b"
pl = "0f0f0f0f-1111-4222-8333-444444444444"
mpr = f"{d}/App.mpr"
if os.path.exists(mpr): os.unlink(mpr)
db = sqlite3.connect(mpr); db.executescript(open(f"{fx}/schema.sql").read())
db.execute("insert into _MetaData values (2,'11.15.0','11.15.0','')")
cdir = f"{d}/mprcontents"; shutil.rmtree(cdir, ignore_errors=True)
for u in units:
    src = "3f64baa2-b85c-4999-9a3c-3cc38382eb54" if u == pl else u
    key = blob(u).hex()
    c, n = (root, "ProjectSecurity") if u == pl else rows[key]
    db.execute("insert into Unit (UnitID, ContainerID, ContainmentName) values (?,?,?)", (blob(u), bytes.fromhex(c), n))
    os.makedirs(f"{cdir}/{u[:2]}/{u[2:4]}", exist_ok=True)
    shutil.copy(f"{fx}/{src}.mxunit", f"{cdir}/{u[:2]}/{u[2:4]}/{u}.mxunit")
db.commit(); db.close()
PY
}
note()   { git notes --ref=mx_metadata show "${1:-HEAD}" 2>/dev/null; }
field()  { "$PY" -c "import json,sys;n=json.load(sys.stdin);print(json.dumps(sorted((c['Status'],c['UnitType'],c['UnitName'],c['Module']) for c in n['ModelChanges'])))"; }
newrepo() {
  local r="$1"; mkdir -p "$r/bin"; cd "$r" && git init -q . && git symbolic-ref HEAD refs/heads/main && git config user.email t@t && git config user.name t
  cp "$TK/project-bin/_common.sh" "$TK/project-bin/model-stamp.sh" "$TK/project-bin/install-project-hooks.sh" "$TK/project-bin/mx-metadata-note.py" bin/
  echo readme > README.md; git add -A >/dev/null; git commit -qm init
}

echo "T0 push refspec never fails a push (review fix: a notes refspec with no local notes ref broke every push)"
TS="$WORK/ts.git"; bare "$TS"
P="$WORK/single"; newrepo "$P"; tsremote "$TS"
git config --add remote.teamserver.push HEAD; git config --add remote.teamserver.push refs/notes/mx_metadata:refs/notes/mx_metadata
if git push -q teamserver >/dev/null 2>&1; then bad "control: the old unconditional refspec should fail a push with no local notes"
else ok "control: old refspec + no local notes = whole push fails"; fi
git config --unset-all remote.teamserver.push
PROJECT_ROOT="$P" ./bin/install-project-hooks.sh --check >/dev/null 2>&1 && bad "--check passed with no hooks" || ok "--check fails before install"
git config --add remote.teamserver.push HEAD; git config --add remote.teamserver.push refs/notes/mx_metadata:refs/notes/mx_metadata
PROJECT_ROOT="$P" ./bin/install-project-hooks.sh >/dev/null 2>&1
if git config --get-all remote.teamserver.push | grep -q notes; then bad "notes refspec kept with no notes on either side" "$(git config --get-all remote.teamserver.push)"
else ok "install removes a stale notes refspec and adds none while no notes exist"; fi
if git push -q teamserver >/dev/null 2>&1 && git -C "$TS" rev-parse -q --verify refs/heads/main >/dev/null; then ok "git push teamserver pushes the branch"
else bad "push failed after install" "$(git push teamserver 2>&1)"; fi
[ -x .git/hooks/post-commit ] && [ -x .git/hooks/post-rewrite ] && ok "post-commit + post-rewrite installed" || bad "hooks missing"
PROJECT_ROOT="$P" ./bin/install-project-hooks.sh --check >/dev/null 2>&1 && ok "--check passes with no notes and no notes refspec" || bad "--check" "$(PROJECT_ROOT="$P" ./bin/install-project-hooks.sh --check 2>&1)"

echo "T1 a model commit gets a note with real names, types and module"
mkmodel "$P" $MOD $MF $DM $MS
git add -A >/dev/null; git commit -qm "add MyFirstModule" 2>/dev/null
got="$(note | field)"
exp='[["Added", "DomainModels$DomainModel", "", "MyFirstModule"], ["Added", "Microflows$Microflow", "MyFirstLogic", "MyFirstModule"], ["Added", "Projects$ModuleImpl", "MyFirstModule", "MyFirstModule"], ["Added", "Security$ModuleSecurity", "", "MyFirstModule"]]'
[ "$got" = "$exp" ] && ok "4 Added entries, Studio Pro's shape" || bad "ModelChanges" "got $got"
note | grep -q '"ModelerVersion":"11.15.0"' && ok "ModelerVersion read from the commit's .mpr" || bad "version" "$(note)"

echo "T2 modified and deleted units; deleted ones are named from the parent commit"
"$PY" - "$P/mprcontents/${MF:0:2}/${MF:2:2}/$MF.mxunit" <<'PY'
import sys; p=sys.argv[1]; b=open(p,'rb').read(); assert b'client' in b; open(p,'wb').write(b.replace(b'client', b'CLIENT', 1))
PY
git add -A >/dev/null; git commit -qm "edit microflow" 2>/dev/null
[ "$(note | field)" = '[["Modified", "Microflows$Microflow", "MyFirstLogic", "MyFirstModule"]]' ] && ok "Modified microflow" || bad "modified" "$(note)"
mkmodel "$P" $MOD $DM $MS; git add -A >/dev/null; git commit -qm "drop microflow" 2>/dev/null
[ "$(note | field)" = '[["Deleted", "Microflows$Microflow", "MyFirstLogic", "MyFirstModule"]]' ] && ok "Deleted microflow, still named" || bad "deleted" "$(note)"

echo "T3 project-level unit: empty UnitName and Module, as Studio Pro writes them"
mkmodel "$P" $MOD $DM $MS $PL; git add -A >/dev/null; git commit -qm "project unit" 2>/dev/null
[ "$(note | field)" = '[["Added", "Security$ModuleSecurity", "", ""]]' ] && ok "project-level entry" || bad "project-level" "$(note)"

echo "T4 a commit that touches no model file gets no note"
echo more >> README.md; git commit -qam docs 2>/dev/null
note >/dev/null && bad "docs commit got a note" "$(note)" || ok "no note on a docs commit"

echo "T5 amend: post-rewrite notes the new commit; an existing note keeps its other keys"
git notes --ref=mx_metadata add -f -m '{"BranchName":"x","ModelerVersion":"9.9.9","ModelChanges":[],"RelatedStories":[],"Extra":1}' HEAD~1 2>/dev/null
nmd write HEAD~1 >/dev/null
note HEAD~1 | grep -q '"ModelerVersion":"9.9.9".*"Extra":1' && note HEAD~1 | grep -q 0f0f0f0f && ok "existing keys kept, ModelChanges filled" || bad "keys" "$(note HEAD~1)"
mkmodel "$P" $MOD $DM $MS; git add -A >/dev/null; git commit -q --amend -m "docs + drop project unit" 2>/dev/null
[ "$(note | field)" = '[["Deleted", "Security$ModuleSecurity", "", ""]]' ] && ok "amended commit noted" || bad "amend" "$(note)"

echo "T6 the first note wires the push refspec; a plain push then carries branch + notes"
git config --get-all remote.teamserver.push | tr '\n' ' ' | grep -q 'HEAD refs/notes/mx_metadata:refs/notes/mx_metadata' && ok "post-commit wired teamserver: HEAD + notes" || bad "refspec" "$(git config --get-all remote.teamserver.push)"
PROJECT_ROOT="$P" ./bin/install-project-hooks.sh >/dev/null 2>&1
[ "$(git config --get-all remote.teamserver.push | wc -l | tr -d ' ')" = 2 ] && ok "re-install is idempotent" || bad "refspec duplicated" "$(git config --get-all remote.teamserver.push)"
PROJECT_ROOT="$P" ./bin/install-project-hooks.sh --check >/dev/null 2>&1 && ok "--check passes" || bad "--check failed" "$(PROJECT_ROOT="$P" ./bin/install-project-hooks.sh --check 2>&1)"
if git push -q teamserver >/dev/null 2>&1 && [ "$(git -C "$TS" rev-parse refs/heads/main)" = "$(git rev-parse HEAD)" ] \
   && [ "$(git -C "$TS" rev-parse refs/notes/mx_metadata)" = "$(git rev-parse refs/notes/mx_metadata)" ]; then ok "git push teamserver: branch and notes both landed"
else bad "push branch+notes" "$(git push teamserver 2>&1)"; fi
git checkout -q -b feature && git commit -q --allow-empty -m feature 2>/dev/null
if git push -q teamserver >/dev/null 2>&1 && git -C "$TS" rev-parse -q --verify refs/heads/feature >/dev/null; then ok "another branch pushes to its own name (HEAD refspec = push.default current)"
else bad "feature branch push" "$(git push teamserver 2>&1)"; fi
git checkout -q main

echo "T6b a fresh clone with no local notes: install fetches the remote's notes, then wires the push"
F="$WORK/fresh"; git clone -q "$TS" "$F" && cd "$F" && git config user.email t@t && git config user.name t
git remote remove origin; tsremote "$TS"; git fetch -q teamserver; git branch -q -u teamserver/main
mkdir -p bin; cp "$TK/project-bin/_common.sh" "$TK/project-bin/model-stamp.sh" "$TK/project-bin/install-project-hooks.sh" "$TK/project-bin/mx-metadata-note.py" bin/
git rev-parse -q --verify refs/notes/mx_metadata >/dev/null && bad "precondition: clone already has notes" || true
PROJECT_ROOT="$F" ./bin/install-project-hooks.sh >/dev/null 2>&1
[ "$(git rev-parse -q --verify refs/notes/mx_metadata)" = "$(git -C "$TS" rev-parse refs/notes/mx_metadata)" ] && ok "install fetched the remote's notes" || bad "notes not fetched"
git config --get-all remote.teamserver.push | grep -q notes && ok "and wired the notes refspec" || bad "not wired" "$(git config --get-all remote.teamserver.push)"
git push -q teamserver >/dev/null 2>&1 && ok "git push teamserver succeeds" || bad "push" "$(git push teamserver 2>&1)"
cd "$P"

echo "T7 backfill: notes a history that had none; a second run changes nothing"
git update-ref -d refs/notes/mx_metadata
out="$(nmd backfill)"
echo "$out" | tail -1 | grep -q "updated 5 notes" && ok "backfill wrote 5 notes (5 model commits)" || bad "backfill" "$out"
nmd backfill | tail -1 | grep -q "updated 0 notes" && ok "second backfill is a no-op" || bad "not idempotent"

echo "T7b backfill never overwrites a note that already lists changes (Studio Pro's); --force does"
git notes --ref=mx_metadata add -f -m '{"ModelerVersion":"11.15.0","ModelChanges":[{"Status":"Modified","UnitName":"FromStudioPro"}],"From":"sp"}' HEAD~2 2>/dev/null
nmd backfill | tail -1 | grep -q "updated 0 notes" && note HEAD~2 | grep -q FromStudioPro && ok "Studio Pro's non-empty note left alone" || bad "SP note overwritten" "$(note HEAD~2)"
nmd write HEAD~2 >/dev/null; note HEAD~2 | grep -q FromStudioPro && ok "write leaves it alone too" || bad "write overwrote" "$(note HEAD~2)"
nmd backfill --force | tail -1 | grep -q "updated 1 notes" && ! note HEAD~2 | grep -q FromStudioPro && note HEAD~2 | grep -q '"From":"sp"' \
  && ok "--force recomputes it, other keys kept" || bad "--force" "$(note HEAD~2)"

echo "T8 two-tree layout (app/App.mpr + root symlink)"
T="$WORK/twotree"; newrepo "$T"; PROJECT_ROOT="$T" ./bin/install-project-hooks.sh >/dev/null 2>&1
mkdir -p app; mkmodel "$T/app" $MOD $MF; ln -s app/App.mpr App.mpr
git add -A >/dev/null; git commit -qm "two-tree model" 2>/dev/null
[ "$(note | field)" = '[["Added", "Microflows$Microflow", "MyFirstLogic", "MyFirstModule"], ["Added", "Projects$ModuleImpl", "MyFirstModule", "MyFirstModule"]]' ] && ok "two-tree note" || bad "two-tree" "$(note)"

echo "T9 sync: another clone noted other commits; merge, then a fast-forward push"
B="$WORK/remote.git"; bare "$B"
cd "$P" && git remote add origin "$B" && git push -q origin HEAD:refs/heads/main refs/notes/mx_metadata:refs/notes/mx_metadata
C="$WORK/clone"; git clone -q "$B" "$C" && cd "$C" && git config user.email t@t && git config user.name t
git fetch -q origin refs/notes/mx_metadata:refs/notes/mx_metadata
git notes --ref=mx_metadata add -f -m '{"ModelerVersion":"11.15.0","ModelChanges":[{"Status":"Modified"}],"From":"them"}' HEAD~3 2>/dev/null   # changed only there
git notes --ref=mx_metadata add -f -m '{"ModelerVersion":"11.15.0","ModelChanges":[],"From":"them"}' HEAD~2 2>/dev/null                        # changed on BOTH sides
git notes --ref=mx_metadata add -f -m '{"ModelerVersion":"11.15.0","ModelChanges":[{"Status":"Added"}],"From":"them-sp"}' HEAD~1 2>/dev/null   # BOTH sides, theirs lists changes
git push -q origin refs/notes/mx_metadata:refs/notes/mx_metadata 2>/dev/null
cd "$P" && git notes --ref=mx_metadata add -f -m '{"ModelerVersion":"11.15.0","ModelChanges":[],"From":"us"}' HEAD~2 2>/dev/null
git notes --ref=mx_metadata add -f -m '{"ModelerVersion":"11.15.0","ModelChanges":[{"Status":"Modified"}],"From":"us"}' HEAD~1 2>/dev/null
mkmodel "$P" $MOD $MF $DM $MS && git add -A >/dev/null && git commit -qm "re-add" 2>/dev/null
if git push -q origin refs/notes/mx_metadata:refs/notes/mx_metadata 2>/dev/null; then bad "diverged notes pushed without a merge"
else ok "plain notes push rejected when the remote moved"; fi
nmd sync origin >/dev/null 2>&1 && ok "sync merged and pushed" || bad "sync failed" "$(nmd sync origin 2>&1)"
[ "$(git ls-remote origin refs/notes/mx_metadata | cut -f1)" = "$(git rev-parse refs/notes/mx_metadata)" ] && ok "remote notes == local" || bad "remote differs"
git notes --ref=mx_metadata show HEAD~4 2>/dev/null | grep -q '"From":"them"' && ok "a note changed only on the remote keeps the remote's change" || bad "remote-only change lost" "$(git notes --ref=mx_metadata show HEAD~4)"
git notes --ref=mx_metadata show HEAD~3 2>/dev/null | grep -q '"From":"us"' && ok "a note changed on both sides, theirs empty: ours wins" || bad "ours lost the conflict" "$(git notes --ref=mx_metadata show HEAD~3)"
git notes --ref=mx_metadata show HEAD~2 2>/dev/null | grep -q '"From":"them-sp"' && ok "a note changed on both sides, theirs lists changes: theirs kept, never pushed over" || bad "colleague's non-empty note overwritten" "$(git notes --ref=mx_metadata show HEAD~2)"

echo; echo "mx-metadata-note: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
