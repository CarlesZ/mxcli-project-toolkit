#!/usr/bin/env bash
# The "Session-start ritual" section of a project's CLAUDE.local.md. ONE copy, for the same
# reason bin/lib/intake-template.sh and bin/lib/resume-template.sh exist: init-project.sh writes
# it and sync-project.sh heals it, and two hand-kept copies of a template have drifted before.
#
# WHY IT IS SHORT (#288, 2026-10-13). CLAUDE.local.md is loaded on every turn of the main session
# AND of every subagent. In a 20-task, 89-subagent run (2026-10-12) each subagent started at
# 47-48k tokens before reading its brief, and the instruction chain was ~76k characters of that.
# The old section spent ~2,400 characters on every turn explaining the protocol-ack procedure,
# which matters once per toolkit update and which gate-check.sh already prints, in full, in the
# notice it shows exactly when an update is waiting (tests/wave2/test-bug06-freshness.sh asserts
# that notice names the --approved-in-chat path). The rule is unchanged; it now arrives in the
# tool output at the moment it applies instead of in every prompt. The heading also says
# "main session only": a dispatched helper that runs git pull + status.sh on start-up pays for
# both and learns nothing its brief did not already say.
#
# mxtk_ritual_old is the verbatim section init-project.sh wrote before this change (golden:
# tests/wave2/fixtures/ritual-slim/CLAUDE.local.before.md, a captured init output). sync-project.sh
# replaces it only on an EXACT whole-section match, so a section anyone edited is left alone.
#
# Sourced, never executed. Callers are `set -euo pipefail`, so keep this side-effect free.

# Usage: mxtk_ritual_new <toolkit-root>
mxtk_ritual_new() {
  local t="$1"
  cat <<EOF
## Session-start ritual (main session only, before any pipeline work)

A dispatched helper skips this section: its brief is its starting position. For the main
session, your memory of the toolkit's rules is stale by default:

1. \`git -C $t pull --ff-only\`. If \`git -C $t branch --show-current\` isn't
   \`master\`, or the pull could not fast-forward, say so before trusting the clone (a stale
   branch re-stamped a rule master had replaced, 2026-09-16).
2. \`$t/bin/status.sh <project-root> --brief\` — post its three lines as the session's
   first message. They are the position of record, never your memory of last session.
3. If it reports toolkit updates available, run \`$t/bin/gate-check.sh <project-root>\` and
   follow its notice: show the user what changed, ask, record the ack only on a yes. Staleness
   never blocks a gate.
4. State in chat which commit you're working from.
EOF
}

# Usage: mxtk_ritual_old <toolkit-root>  — the pre-#288 section, for an exact-match heal only.
mxtk_ritual_old() {
  local t="$1"
  cat <<EOF
## Session-start ritual (before any pipeline work)

The toolkit's rules change; your memory of them is stale by default. At the start of every
session that will touch the pipeline:

1. \`git -C $t pull --ff-only\`
2. If \`git -C $t branch --show-current\` isn't \`master\`, or the pull above could not
   fast-forward, say so before trusting anything you read from the clone — a session on a stale
   or non-master toolkit branch can re-stamp a rule master already replaced (real incident,
   2026-09-16). \`bin/sync-project.sh\` reports the same check on every sync.
3. \`$t/bin/status.sh <project-root> --brief\` — three lines: where the project is,
   what is done and overdue, and the ONE next action. Post them in chat as the session's first
   message; they are the position of record, never your memory of last session. It runs
   \`gate-check.sh\` underneath, which reports protocol freshness — run gate-check itself when
   you need the per-stage detail.
4. If it says an update is available, **you (the agent) handle it — never ask the user to type
   a command.** Run \`$t/bin/gate-check.sh <project-root> --ack-protocol --verbose\`,
   which shows what changed and **records nothing**. Re-read the named files. Then tell the user
   in plain language what changed and what it means for what they are building, and ask whether
   to take the update. Only if they say yes:
   \`$t/bin/gate-check.sh <project-root> --ack-protocol --approved-in-chat\` — that
   rewrites the \`Toolkit commit:\` line in \`PROJECT.md\` and records which files, how many
   lines, and that it was approved in chat, in \`docs/BUILD-LOG.md\`.
5. State in chat which commit you're working from.

An ack asserts a human was told what changed, so it cannot happen unattended: without a TTY and
without \`--approved-in-chat\` it refuses and names the routes out. \`--approved-in-chat\` is a
claim you are making on the record — set it only after you actually asked and they actually
answered. There is no env-var auto-yes.

By default the output is written for whoever is in the room, not for a maintainer: plain
language, no commit ids, no file paths. Add \`--verbose\` for the ids, paths and diffstat.

**Protocol staleness NEVER blocks a gate.** It prints a notice with lettered options and the
stage verdict is reported on its own merits either way — a project is not broken because
someone else pushed to a shared repo. CI that genuinely wants the old behaviour opts in with
\`--strict-protocol\`.
EOF
}

# Usage: mxtk_ritual_heal <CLAUDE.local.md> <dry-run 0|1>
# Exit 0 = healed (or would heal), 1 = nothing to do. The toolkit path is read from the file's
# own `git -C <path> pull` line, so a project scaffolded from another clone location still heals.
mxtk_ritual_heal() {
  local f="$1" dry="${2:-0}" t old new tmp
  [ -f "$f" ] || return 1
  grep -qx '## Session-start ritual (before any pipeline work)' "$f" || return 1
  t="$(sed -n 's/^1\. `git -C \(.*\) pull --ff-only`$/\1/p' "$f" | head -1)"
  [ -n "$t" ] || return 1
  old="$(mxtk_ritual_old "$t")"
  new="$(mxtk_ritual_new "$t")"
  tmp="$(mktemp "${TMPDIR:-/tmp}/ritual.XXXXXX")" || return 1
  # Whole-section exact match: the section starts at its heading and ends on the line before the
  # next "## " heading (trailing blank lines excluded). Anything else is printed untouched.
  local rc=0
  OLD="$old" NEW="$new" awk '
    BEGIN { old = ENVIRON["OLD"]; new = ENVIRON["NEW"]; insec = 0; buf = ""; done = 0 }
    function flush(   b) {
      b = buf; sub(/\n+$/, "", b)
      if (!done && b == old) { printf "%s\n\n", new; done = 1 } else { printf "%s", buf }
      buf = ""; insec = 0
    }
    {
      if (insec && /^## /) flush()
      if (!insec && !done && $0 == "## Session-start ritual (before any pipeline work)") insec = 1
      if (insec) { buf = buf $0 "\n"; next }
      print
    }
    END { if (insec) flush(); exit done ? 0 : 3 }' "$f" > "$tmp" || rc=$?
  if [ "$rc" -ne 0 ]; then rm -f "$tmp"; return 1; fi
  if [ "$dry" = "1" ]; then rm -f "$tmp"; return 0; fi
  cat "$tmp" > "$f"; rm -f "$tmp"
  return 0
}
