#!/usr/bin/env bash
# install-project-hooks.sh — the commit-time backstop for the mxbuild gate.
#
#   ./bin/install-project-hooks.sh           # install/refresh the pre-commit + revision-note hooks
#   ./bin/install-project-hooks.sh --check   # exit 1 if any is missing or stale
#   ./bin/install-project-hooks.sh --push-refspecs   # notes push refspecs only, no fetch (the post-commit hook runs this)
#
# Two jobs. (1) pre-commit: the mxbuild-gate backstop below. (2) post-commit + post-rewrite: the
# Studio Pro revision note (2026-10-12, field project). Studio Pro's History pane lists a commit's
# changed documents from refs/notes/mx_metadata "ModelChanges", which only Studio Pro filled; CLI
# commits showed "Model changes 0". These hooks run bin/mx-metadata-note.py write HEAD after every
# commit, amend and rebase; they never block (a missing note costs a History entry, nothing
# more). The installer also adds the notes ref to each Team Server remote's push refspecs, so a
# plain `git push <remote>` carries the notes with the branch.
#
# Push refspecs (review fix, 2026-10-14). A push refspec whose source ref does not exist fails the
# WHOLE push ("src refspec refs/notes/mx_metadata does not match any") and nothing is pushed, not
# even the branch. So the notes refspec is only ever added while the local notes ref exists: the
# installer first fetches the remote's notes when there is no local ref (non-forced: it only
# creates the ref), and the post-commit hook adds the refspec once the first note is written. And
# once remote.<r>.push is set, git ignores push.default for that remote entirely, so the branch
# refspec `HEAD` (current branch -> same name) is added explicitly beside it.
#
# WHY (2026-09-17, field project). A model can change without the mxbuild gate ever running — a
# bare `./mxcli exec`, an exec.sh run on a machine with no mxbuild, a Studio Pro save —
# and until now every such change committed and pushed like any other. The hook refuses
# a commit that stages model files (the .mpr and mprcontents/) unless bin/model-stamp.sh
# holds a PASS stamp for exactly that staged content. Commits that touch no model file
# are untouched. It runs on every machine, cloud or laptop, with no toolkit clone needed.
#
# Guard rules (toolkit CLAUDE.md, "Shipping an instrument" rules 6/7):
#   * rule 7 — it never blocks the remedy: ./bin/verify-model.sh is not itself a commit, so
#     there is always a way to earn the stamp without going through this hook.
#   * rule 6 — a missing/stale bin/model-stamp.sh stamp is not the only evidence accepted.
#     A recent PASS row in docs/BUILD-LOG.md (written by exec.sh on every exec, independently
#     of the stamp file — the two share no code path) lets the commit through, with a warning
#     naming which row it trusted. A stale or non-pass row does not count. Absent BOTH the
#     stamp and a qualifying BUILD-LOG row, MODEL_UNVERIFIED_OK=1 lets one commit through,
#     out loud, when someone decides to.
#
# An existing pre-commit hook that is not ours is kept and chained (moved to
# pre-commit.pre-mxtk, called first). A repo with core.hooksPath set is reported, not
# edited — its hooks live somewhere this script must not write to.
set -e
. "$(dirname "$0")/_common.sh"

cd "$PROJECT_ROOT"
git rev-parse --show-toplevel >/dev/null 2>&1 || { echo "install-project-hooks.sh: $PROJECT_ROOT is not in a git repository"; exit 2; }
HOOKS="$(git rev-parse --git-path hooks)"
HOOK="$HOOKS/pre-commit"
MARK="# mxtk-model-stamp hook v1"
# bin/ relative to the git top level, so the hook works when the project root is a subdir.
BIN_REL="$(git rev-parse --show-prefix)bin"

NOTE_MARK="# mxtk-mx-metadata hook v1"
# Team Server remotes: the platform's git host, plus any remote named in MXTK_TS_REMOTES.
# The configured URL, not `git remote -v`: that one shows the URL after url.*.insteadOf rewriting.
ts_remotes() {
  { git config --get-regexp '^remote\..*\.url$' 2>/dev/null \
      | awk '$2 ~ /git\.api\.mendix\.com/ { n = $1; sub(/^remote\./, "", n); sub(/\.url$/, "", n); print n }'
    for r in ${MXTK_TS_REMOTES:-}; do git config --get "remote.$r.url" >/dev/null 2>&1 && echo "$r"; done
  } | sort -u
}
has_notes()    { git rev-parse -q --verify refs/notes/mx_metadata >/dev/null 2>&1; }
pushes_notes() { git config --get-all "remote.$1.push" 2>/dev/null | grep -q 'refs/notes/mx_metadata'; }

# wire_push <remote> fetch|nofetch — add the notes refspec only while it cannot fail the push.
wire_push() {
  _r="$1"
  if ! has_notes && [ "$2" = fetch ]; then
    # Non-forced, and only creates the ref: a remote with no notes just fails this quietly.
    if GIT_TERMINAL_PROMPT=0 git fetch -q "$_r" refs/notes/mx_metadata:refs/notes/mx_metadata >/dev/null 2>&1; then
      echo "  ✓ $_r: fetched its refs/notes/mx_metadata (Studio Pro's notes) before wiring the push"
    fi
  fi
  if ! has_notes; then
    if pushes_notes "$_r"; then
      git config --unset-all "remote.$_r.push" '^refs/notes/mx_metadata:' || true
      echo "  ✓ $_r: removed the notes push refspec — no local refs/notes/mx_metadata, so it would fail every push"
    fi
    [ "$2" = fetch ] && echo "  – $_r: notes push not wired yet (no notes on either side); the post-commit hook wires it with the first note"
    return 0
  fi
  if pushes_notes "$_r"; then
    [ "$2" = fetch ] && echo "  ✓ $_r already pushes refs/notes/mx_metadata"
    return 0
  fi
  # remote.<r>.push REPLACES push.default for this remote, so keep the branch push explicitly. An
  # existing push config is extended, never replaced.
  git config --get-all "remote.$_r.push" >/dev/null 2>&1 || git config --add "remote.$_r.push" HEAD
  git config --add "remote.$_r.push" "refs/notes/mx_metadata:refs/notes/mx_metadata"
  echo "  ✓ $_r: 'git push $_r' now carries refs/notes/mx_metadata with the branch" >&2
  echo "    (rejected as non-fast-forward = a colleague's Studio Pro noted commits too: run mx-metadata-note.py sync $_r)" >&2
}

if [ "${1:-}" = "--push-refspecs" ]; then
  for r in $(ts_remotes); do wire_push "$r" nofetch; done
  exit 0
fi

if [ -n "$(git config --get core.hooksPath 2>/dev/null)" ]; then
  echo "⚠ core.hooksPath is set ($(git config --get core.hooksPath)) — add this to that pre-commit yourself:"
  echo "    \"\$(git rev-parse --show-toplevel)/$BIN_REL/model-stamp.sh\" check --staged || exit 1"
  echo "  and this to its post-commit (revision notes for Studio Pro History; python via resolve_py, never the shebang):"  # portability-ok: advice text
  echo "    b=\"\$(git rev-parse --show-toplevel)/$BIN_REL\"; py=\"\$(PROJECT_ROOT=\"\$b/..\" bash -c '. \"\$1/_common.sh\" >/dev/null 2>&1 && resolve_py' _ \"\$b\")\""
  echo "    [ -n \"\$py\" ] && MXTK_HOOK=1 \"\$py\" \"\$b/mx-metadata-note.py\" write HEAD || true"
  echo "    [ -n \"\$py\" ] && bash \"\$b/install-project-hooks.sh\" --push-refspecs >/dev/null || true   # wires the notes push once a note exists"
  exit 1
fi

if [ "${1:-}" = "--check" ]; then
  rc=0
  if [ -f "$HOOK" ] && grep -q "^$MARK" "$HOOK"; then echo "  ✓ pre-commit hook installed ($HOOK)"
  else echo "  ✗ pre-commit model-verification hook missing — run ./bin/install-project-hooks.sh"; rc=1; fi
  for h in post-commit post-rewrite; do
    if [ -f "$HOOKS/$h" ] && grep -q "^$NOTE_MARK" "$HOOKS/$h"; then echo "  ✓ $h revision-note hook installed"
    else echo "  ✗ $h revision-note hook missing — run ./bin/install-project-hooks.sh"; rc=1; fi
  done
  for r in $(ts_remotes); do
    if has_notes && pushes_notes "$r"; then echo "  ✓ $r pushes refs/notes/mx_metadata"
    elif has_notes; then echo "  ✗ $r does not push refs/notes/mx_metadata — run ./bin/install-project-hooks.sh"; rc=1
    elif pushes_notes "$r"; then echo "  ✗ $r pushes refs/notes/mx_metadata but there is no local notes ref — every 'git push $r' fails; run ./bin/install-project-hooks.sh"; rc=1
    else echo "  – $r: no notes yet, so no notes refspec (the post-commit hook adds it with the first note)"; fi
  done
  exit $rc
fi

mkdir -p "$HOOKS"
if [ -f "$HOOK" ] && ! grep -q "^$MARK" "$HOOK"; then
  mv "$HOOK" "$HOOK.pre-mxtk"
  echo "  existing pre-commit hook kept as $(basename "$HOOK").pre-mxtk and chained first"
fi
cat > "$HOOK" <<HOOKEOF
#!/usr/bin/env bash
$MARK — written by bin/install-project-hooks.sh (mxcli-project-toolkit). Re-run it to refresh.
top="\$(git rev-parse --show-toplevel)"
[ -x "\$(dirname "\$0")/pre-commit.pre-mxtk" ] && { "\$(dirname "\$0")/pre-commit.pre-mxtk" || exit 1; }
stamp="\$top/$BIN_REL/model-stamp.sh"
if [ ! -x "\$stamp" ]; then
  echo "⚠ $BIN_REL/model-stamp.sh is missing — the model-verification hook cannot check this commit (re-run the toolkit's sync-project.sh)" >&2
  exit 0
fi
if ! "\$stamp" check --staged; then
  alt=""
  blog="\$top/docs/BUILD-LOG.md"
  max_age="\${MODEL_EVIDENCE_MAX_AGE:-14400}"
  if [ -f "\$blog" ]; then
    bmtime="\$(stat -c %Y "\$blog" 2>/dev/null || stat -f %m "\$blog" 2>/dev/null || echo 0)"
    case "\$bmtime" in ''|*[!0-9]*) bmtime=0 ;; esac
    now="\$(date +%s)"
    lastrow="\$(grep '^| 20' "\$blog" 2>/dev/null | tail -1)"
    if [ "\$bmtime" -gt 0 ] && [ \$(( now - bmtime )) -le "\$max_age" ] && printf '%s' "\$lastrow" | grep -q '| pass |'; then
      alt="a recent docs/BUILD-LOG.md row (gate: pass, \$(( (now - bmtime) / 60 )) min ago)"
    fi
  fi
  if [ -n "\$alt" ]; then
    echo "⚠ no local model-stamp, but accepting \$alt as evidence the model was mxbuild-gated." >&2
    echo "  (this is NOT a guarantee the staged content matches that row — verify-model.sh is the strong check)" >&2
  elif [ "\${MODEL_UNVERIFIED_OK:-0}" = "1" ]; then
    echo "⚠ MODEL_UNVERIFIED_OK=1 — committing a model the mxbuild gate has not verified." >&2
  else
    echo "" >&2
    echo "✗ commit refused: the staged model has not passed the mxbuild gate on this machine." >&2
    echo "  Run   ./bin/verify-model.sh   (one mxbuild, stamps the model when clean), then commit again." >&2
    echo "  Deliberate override, once:   MODEL_UNVERIFIED_OK=1 git commit ..." >&2
    exit 1
  fi
fi
exit 0
HOOKEOF
chmod +x "$HOOK"
echo "  ✓ pre-commit hook installed -> $HOOK"
echo "    (refuses to commit .mpr/mprcontents changes that have no mxbuild-gate PASS stamp; ./bin/verify-model.sh writes one)"

# --- revision notes for Studio Pro History (post-commit + post-rewrite) -------------------------
# Both hooks find Python through bin/_common.sh's resolve_py (executes each candidate, skips the
# Windows Store alias stub). No Python, or no _common.sh: one warning, the commit stands.
for h in post-commit post-rewrite; do
  HF="$HOOKS/$h"
  if [ -f "$HF" ] && ! grep -q "^$NOTE_MARK" "$HF"; then
    mv "$HF" "$HF.pre-mxtk"
    echo "  existing $h hook kept as $h.pre-mxtk and chained first"
  fi
  if [ "$h" = post-commit ]; then
    RUN='note_one HEAD'
    CHAIN='[ -x "$(dirname "$0")/post-commit.pre-mxtk" ] && "$(dirname "$0")/post-commit.pre-mxtk"'
  else
    # stdin: "<old> <new> [extra]" per rewritten commit (amend, rebase). Read it once, feed both.
    RUN='printf "%s\n" "$input" | while read -r _old new _rest; do [ -n "$new" ] && note_one "$new"; done'
    CHAIN='[ -x "$(dirname "$0")/post-rewrite.pre-mxtk" ] && printf "%s\n" "$input" | "$(dirname "$0")/post-rewrite.pre-mxtk" "$@"'
  fi
  cat > "$HF" <<HOOKEOF
#!/usr/bin/env bash
$NOTE_MARK — written by bin/install-project-hooks.sh (mxcli-project-toolkit). Re-run it to refresh.
# Writes the Studio Pro revision note (refs/notes/mx_metadata, with ModelChanges) for model commits.
# Never fails the git operation: every problem is one warning on stderr.
$( [ "$h" = post-rewrite ] && echo 'input="$(cat)"' )
$CHAIN
note="\$(git rev-parse --show-toplevel)/$BIN_REL/mx-metadata-note.py"
proj="\$(dirname "\$(dirname "\$note")")"
# mxcli v0.26+ writes this note itself (mxcli git note, mendixlabs/mxcli#1337): prefer it when the
# project's pinned binary has the command; older pins fall back to bin/mx-metadata-note.py.
mx="\$proj/mxcli"; mpr="\$(ls "\$proj"/*.mpr 2>/dev/null | head -1)"
# Probe for --write in the help text: an mxcli with \`git\` but no \`note\` can still exit 0 on --help.
if [ -x "\$mx" ] && [ -n "\$mpr" ] && "\$mx" git note --help 2>&1 | grep -q -- '--write'; then
  note_one() { "\$mx" git note -p "\$mpr" --write "\$1" >/dev/null 2>&1 || echo "⚠ mxcli git note failed for \$1 — Studio Pro History will show 'Model changes 0' (re-run: ./mxcli git note -p \$(basename "\$mpr") --write \$1)" >&2; }
else
  [ -f "\$note" ] || exit 0
  py=""
  [ -f "\$(dirname "\$note")/_common.sh" ] && py="\$(PROJECT_ROOT="\$proj" bash -c '. "\$1/_common.sh" >/dev/null 2>&1 && resolve_py' _ "\$(dirname "\$note")" 2>/dev/null)"
  [ -z "\$py" ] && { echo "⚠ no python found — Studio Pro History will show 'Model changes 0' for this commit (bin/mx-metadata-note.py backfill fixes it later)" >&2; exit 0; }  # portability-ok: resolve_py above is the probe
  note_one() { MXTK_HOOK=1 "\$py" "\$note" write "\$1" || true; }
fi
$RUN
# The first note just appeared? Then the Team Server push refspec can be wired without failing a push.
inst="\$(dirname "\$note")/install-project-hooks.sh"
git rev-parse -q --verify refs/notes/mx_metadata >/dev/null 2>&1 && [ -f "\$inst" ] && PROJECT_ROOT="\$proj" bash "\$inst" --push-refspecs >/dev/null || true
exit 0
HOOKEOF
  chmod +x "$HF"
done
echo "  ✓ post-commit + post-rewrite revision-note hooks installed (Studio Pro History lists each commit's changed documents)"

for r in $(ts_remotes); do wire_push "$r" fetch 2>&1; done
