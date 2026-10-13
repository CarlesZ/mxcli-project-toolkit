#!/usr/bin/env bash
# test-scratch.sh — run `mxcli test` on a scratch COPY of the model, under a lock on the test ports.
#
#   ./bin/test-scratch.sh [--keep] [--ports "8081 8091"] -- <mxcli test args, without -p>
#   e.g. ./bin/test-scratch.sh -- tests/unit/Orders.test.mdl --local
#
# Exit: mxcli's own exit code · 2 usage · 3 refused (nothing copied or run)
#
# WHY (#278, field run 2026-10-12; testing-shape.md § "mxcli test --local does NOT leave a warm
# run --local app alone"). `mxcli test` injects a TestRunner, sets security off, builds into
# <app dir>/deployment and restores — all in the LIVE project. One unlocked run in the live repo
# broke the running app (NoClassDefFoundError) with the .mpr unchanged; the remedy that worked was
# a scratch copy of the project plus a lock around the fixed test ports, and it lived only in that
# run's private helper. This is that helper:
#   1. takes this project's exec lock (.mpr-snapshots/.exec.lock, the same file and format as
#      exec.sh) for the COPY only, so the copy is never a half-written model — a live exec.sh
#      refuses this, a dead holder is taken over;
#   2. copies the model tree to a scratch dir, leaving out .git, .mpr-snapshots, deployment and
#      .mxcli (the last holds the LIVE app's run --local record; a copy carrying it would point
#      app-restart.sh and test-stack-up.sh at the live app);
#   3. takes a MACHINE-wide lock on the test ports (they are machine-global: two test runs on one
#      machine collide on 8081/8091 whatever project they belong to), refusing while another live
#      holder has it and taking over a dead one;
#   4. runs `mxcli test <args> -p <scratch>.mpr` in the scratch dir, then releases both and deletes
#      the copy (--keep leaves it, and says where).
# Refused (exit 3, nothing copied) when the live model's after-startup is still an mxcli test injection
# (MxTest.RegisterEndpoint / MxTest.TestRunner, left by a run stopped by a signal — #244, BUG-157):
# the copy would carry it and the test runtime would recurse in its after-startup. The repair is printed.
# --attach is refused: it hot-applies into the live app and runs against its database, which is
# the opposite of a scratch run. Never touches the live model, the live app, or Studio Pro.
# Bash 3.2 / Git Bash / macOS / Linux; no flock (absent on macOS and Git Bash).
set -uo pipefail
. "$(dirname "$0")/_common.sh"

KEEP=0; PORTS="${MXTK_TEST_PORTS:-8081 8091}"
while [ $# -gt 0 ]; do
  case "$1" in
    --keep)  KEEP=1 ;;
    --ports) shift; PORTS="${1:-}" ;;
    --)      shift; break ;;
    -h|--help) sed -n '2,7p' "$0"; exit 0 ;;
    *) break ;;
  esac
  shift
done
[ $# -gt 0 ] || { echo "usage: $0 [--keep] [--ports \"8081 8091\"] -- <mxcli test args>" >&2; exit 2; }
for _a in "$@"; do
  case "$_a" in
    --attach) echo "✗ test-scratch: --attach runs against the LIVE app and its database — not a scratch run. Use mxcli test --attach directly, deliberately, and restart the app after (testing-shape.md)." >&2; exit 3 ;;
    -p|--project|-p=*|--project=*) echo "✗ test-scratch: do not pass -p; the scratch copy's .mpr is passed for you." >&2; exit 2 ;;
  esac
done

MPR="$(find_mpr)" || exit 2
MODEL_DIR="$(find_model_dir 2>/dev/null || dirname "$MPR")"
MPR_NAME="$(basename "$MPR")"
[ -f "$MODEL_DIR/$MPR_NAME" ] || MODEL_DIR="$(cd "$(dirname "$MPR")" && pwd)"
if [ -x "$PROJECT_ROOT/mxcli" ]; then MXCLI="$PROJECT_ROOT/mxcli"
elif [ -x "$MODEL_DIR/mxcli" ]; then MXCLI="$MODEL_DIR/mxcli"
elif command -v mxcli >/dev/null 2>&1; then MXCLI="$(command -v mxcli)"
else echo "✗ test-scratch: no mxcli (project root or PATH)." >&2; exit 3; fi

# ── After-startup left on an mxcli test injection (#244, BUG-157) ───────────
# `mxcli test` and `mxcli run --test-endpoint` point the model's after-startup microflow at
# MxTest.RegisterEndpoint (MxTest.TestRunner for a plain test run) and chain the original; only a
# clean exit puts it back. A run stopped by a signal leaves it, and the next injection then chains
# RegisterEndpoint to itself: StackOverflowError in the after-startup, the runtime never starts.
# Read straight from the model bytes — no mxcli, no running app: the setting is the BSON string
# element "AfterStartupMicroflow" of the project-settings unit (mprcontents/**/*.mxunit; inside the
# .mpr itself on a v1 model). Layout checked against real settings units (mxcli's own test models).
mxtest_after_startup() {  # $1 = file, or - for stdin. Prints the value ('' = none); 1 = no such element
  { if [ "$1" = - ]; then od -An -v -tx1; else od -An -v -tx1 "$1"; fi; } 2>/dev/null | awk '
    BEGIN { for (i = 0; i < 256; i++) hv[sprintf("%02x", i)] = i
            for (i = 32; i < 127; i++) { c = sprintf("%c", i); ch[sprintf("%02x", i)] = c; hx[c] = sprintf("%02x", i) }
            s = "AfterStartupMicroflow"; T = length(s) + 2; t[1] = "02"; t[T] = "00"
            for (i = 1; i <= length(s); i++) t[i + 1] = hx[substr(s, i, 1)]
            k = 0; st = 0; found = 0 }
    { for (f = 1; f <= NF; f++) { b = $f
        if (st == 0) { if (b == t[k + 1]) k++; else k = (b == t[1]) ? 1 : 0
                       if (k == T) { st = 1; L = 0; m = 1; n = 0; v = "" } }
        else if (st == 1) { L += hv[b] * m; m *= 256
                            if (++n == 4) { if (L < 1 || L > 1024) { st = 0; k = 0 } else if (L == 1) { found = 1; exit } else { st = 2; n = 0 } } }
        else { if (++n < L) v = v ((b in ch) ? ch[b] : "?"); else { found = 1; exit } } } }
    END { if (!found) exit 1; print v }'
}
MXTEST_LEFT=""; MXTEST_UNIT=""; MXTEST_HEAD=""
mxtest_left() {  # $1 = model dir, $2 = .mpr. 0 = after-startup is an mxcli test injection (sets MXTEST_*)
  local unit val
  MXTEST_LEFT=""; MXTEST_UNIT=""; MXTEST_HEAD=""
  if [ -d "$1/mprcontents" ]; then
    unit="$(LC_ALL=C grep -rla --include='*.mxunit' 'AfterStartupMicroflow' "$1/mprcontents" 2>/dev/null | head -1)"
  else unit="$2"; fi
  [ -n "$unit" ] && [ -f "$unit" ] || return 1
  val="$(mxtest_after_startup "$unit")" || return 1
  case "$val" in MxTest.RegisterEndpoint|MxTest.TestRunner) ;; *) return 1 ;; esac
  MXTEST_LEFT="$val"; MXTEST_UNIT="$unit"
  case "$unit" in *.mxunit)   # what HEAD has, so the repair can name it; "?" = not tracked / no git
    MXTEST_HEAD="$(git -C "$(dirname "$unit")" show "HEAD:./$(basename "$unit")" 2>/dev/null | mxtest_after_startup -)" || MXTEST_HEAD="?" ;;
  *) MXTEST_HEAD="?" ;; esac
  return 0
}
mxtest_refusal() {  # $1 = tool name. Prints the refusal and the repair to stderr.
  local was="$MXTEST_HEAD" rel="${MXTEST_UNIT#"$PROJECT_ROOT"/}"
  echo "✗ $1: this model's after-startup microflow is $MXTEST_LEFT — left behind by an mxcli test or" >&2
  echo "  run --test-endpoint that did not exit cleanly (stopped by a signal or killed; BUG-157)." >&2
  echo "  Starting on it recurses (the next injection chains $MXTEST_LEFT to itself: StackOverflowError)," >&2
  echo "  or fails the build with CE1613 if the MxTest module is already gone. Either way the app never starts." >&2
  echo "  set in: $rel" >&2
  case "$was" in '?') was="<your own after-startup microflow, or '' for none>"
                      echo "  HEAD: not readable (no git, or the unit is untracked)" >&2 ;;
                 '')  echo "  HEAD: no after-startup microflow" >&2 ;;
                 *)   echo "  HEAD: $was" >&2 ;; esac
  echo "  → If this project's app is running with --test-endpoint right now, this is its live injection:" >&2
  echo "    stop it with Ctrl+C in its own terminal (a clean stop restores the setting), then retry." >&2
  echo "  → Otherwise restore it, then retry:" >&2
  echo "      git checkout -- '$rel'      (then git status: the run may have left an MxTest module too)" >&2
  echo "    or through ./bin/exec.sh (an ALTER SETTINGS — say so in chat; it is what mxcli's own cleanup runs):" >&2
  echo "      mdl 1;" >&2
  echo "      alter settings runtime (AfterStartupMicroflow: '$was');" >&2
  echo "    or Studio Pro: App Settings → Runtime → After startup." >&2
}

# A model whose after-startup is an mxcli test injection must not be copied and tested: the copy
# carries it, and mxcli test then chains the injection to itself (#244 observation 1).
if mxtest_left "$MODEL_DIR" "$MODEL_DIR/$MPR_NAME"; then
  mxtest_refusal "test-scratch"
  echo "  Nothing was copied or run." >&2
  exit 3
fi

# Same liveness rule as exec.sh's lock: alive, not a zombie, and (where ps can say) one of ours.
holder_live() {
  [ -n "${1:-}" ] || return 1
  case "$1" in *[!0-9]*) return 1 ;; esac
  kill -0 "$1" 2>/dev/null || return 1
  case "$(sed 's/.*) //' "/proc/$1/stat" 2>/dev/null | cut -d' ' -f1)" in Z) return 1 ;; esac
  _args="$(ps -o args= -p "$1" 2>/dev/null || true)"
  case "$_args" in ""|*exec.sh*|*test-scratch.sh*) return 0 ;; esac
  return 1
}
# Taking over a stale lock is itself serialised (#304 review): two runs that both read the same
# dead holder must not both remove "the stale lock" — the second would remove the lock the first
# had just taken, and both would run. So a takeover first wins "$f.takeover" (noclobber: O_EXCL;
# one older than 30s is a takeover that died midway and is cleared), re-reads the lock, and
# removes it only if it still holds the stale line it judged. It moves the lock aside before
# checking; a lock that changed in between is put back with `ln`, which refuses to overwrite,
# never `mv -f`, which would clobber a lock taken meanwhile.
take_over() {  # $1 = lock file, $2 = the stale line. 0 = handled (retry the take), 1 = another takeover runs
  local f="$1" held="$2" t="$1.takeover" ts
  if ! ( set -o noclobber; printf '%s %s\n' "$$" "$(date +%s)" > "$t" ) 2>/dev/null; then
    ts="$(cut -d' ' -f2 "$t" 2>/dev/null | head -1)"
    case "$ts" in ''|*[!0-9]*) ;; *) [ $(( $(date +%s) - ts )) -gt 30 ] && rm -f "$t" ;; esac
    return 1
  fi
  if [ "$(head -1 "$f" 2>/dev/null || true)" = "$held" ] && mv "$f" "$f.stale.$$" 2>/dev/null; then
    if [ "$(head -1 "$f.stale.$$" 2>/dev/null || true)" != "$held" ]; then
      ln "$f.stale.$$" "$f" 2>/dev/null || true   # not the line we judged: put it back, never over a newer one
    fi
    rm -f "$f.stale.$$"
  fi
  rm -f "$t"
  return 0
}
take_lock() {  # $1 = lock file, $2 = what it guards (for messages). 0 = taken, 1 = live holder
  local f="$1" held hpid i
  for i in 1 2 3 4 5 6 7 8; do
    if ( set -o noclobber; printf '%s %s %s\n' "$$" "$(date +%s)" "test-scratch.sh" > "$f" ) 2>/dev/null; then return 0; fi
    held="$(head -1 "$f" 2>/dev/null || true)"
    if [ -z "$held" ] && [ "$i" -lt 3 ]; then sleep 1; continue; fi
    hpid="${held%% *}"
    if holder_live "$hpid"; then
      echo "✗ test-scratch: $2 is held by PID $hpid ($(printf '%s' "$held" | cut -d' ' -f3-)) — wait for it to finish." >&2
      return 1
    fi
    if take_over "$f" "$held"; then
      echo "  (stale lock on $2 from PID ${hpid:-?}, not running — taking it over)"
    else
      sleep 1   # another run is taking the same stale lock over; see who won
    fi
  done
  echo "✗ test-scratch: could not take the lock on $2 after 8 attempts." >&2; return 1
}
release() { local f="$1" own; own="$(head -1 "$f" 2>/dev/null || true)"; [ "${own%% *}" = "$$" ] && rm -f "$f"; return 0; }

EXEC_LOCK="$PROJECT_ROOT/.mpr-snapshots/.exec.lock"
PORT_LOCK="${TMPDIR:-/tmp}/mxtk-test-ports-$(printf '%s' "$PORTS" | tr -c '0-9' '-').lock"
SCRATCH=""
cleanup() {
  release "$EXEC_LOCK"; release "$PORT_LOCK"
  if [ -n "$SCRATCH" ] && [ -d "$SCRATCH" ]; then
    if [ "$KEEP" = 1 ]; then echo "  scratch copy kept: $SCRATCH"; else rm -rf "$SCRATCH"; fi
  fi
}
trap cleanup EXIT

# 1+3. Port lock first (machine-wide, cheap to fail), then the project lock for the copy.
take_lock "$PORT_LOCK" "test ports $PORTS" || exit 3
for _p in $PORTS; do
  if curl -s -o /dev/null --max-time 2 "http://localhost:$_p/" 2>/dev/null; then
    echo "✗ test-scratch: :$_p already answers — another test runtime (or app) is up there. Not starting a second." >&2
    exit 3
  fi
done
mkdir -p "$(dirname "$EXEC_LOCK")"
take_lock "$EXEC_LOCK" "this project's model (an exec.sh is writing it)" || exit 3

# 2. The copy.
SCRATCH="$(mktemp -d "${MXTK_SCRATCH_DIR:-${TMPDIR:-/tmp}}/$(basename "$MPR_NAME" .mpr)-test.XXXXXX")" || exit 3
echo "→ test-scratch: copying $(basename "$MODEL_DIR")/ → $SCRATCH (no .git, .mpr-snapshots, deployment, .mxcli)"
if ! tar -C "$MODEL_DIR" --exclude=./.git --exclude=./.mpr-snapshots --exclude=./deployment \
       --exclude=./.mxcli --exclude=./node_modules -cf - . | tar -C "$SCRATCH" -xf -; then
  echo "✗ test-scratch: copy failed." >&2; exit 3
fi
release "$EXEC_LOCK"
[ -f "$SCRATCH/$MPR_NAME" ] || { echo "✗ test-scratch: $MPR_NAME missing from the copy." >&2; exit 3; }

# 4. Run.
echo "→ $(basename "$MXCLI") test $* -p $SCRATCH/$MPR_NAME   (ports $PORTS locked)"
( cd "$SCRATCH" && "$MXCLI" test "$@" -p "$SCRATCH/$MPR_NAME" )
RC=$?
echo "← mxcli test exit $RC — the live model and the live app were not touched."
exit "$RC"
