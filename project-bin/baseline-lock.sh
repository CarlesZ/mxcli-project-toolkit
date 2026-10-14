#!/usr/bin/env bash
# baseline-lock.sh — the shared lock behind every ratchet baseline a person must approve.
#
# WHY (#348, 2026-10-14). `lint-gate.sh --update-baseline` took `--approved-in-chat` as the
# proof that the user said yes. The agent whose script caused the rise could type that flag
# itself, so "re-baselining is the user's call" was honour-system. A baseline that LOOSENS now
# moves only against a row in .claude/baseline-approvals.tsv whose sha256 is the exact
# proposed content — a row only bin/baseline-approve.sh writes, from a terminal, after a person
# reads the change and types `approve`.
#
# THE RECORD IS CHECKED, NOT BELIEVED (#375 review). Every instrument write is logged with a
# snapshot of its content, and `verify` replays the log: each recorded write must be no looser
# than the one before it, or carry an approval. So appending a row by hand — or running
# `record` directly after a hand edit — does not launder a rise: the forged row is looser than
# its predecessor and verify says FAIL. Only content can pass, never a claim about content.
#
# What it does NOT stop, said plainly: a forged row in baseline-approvals.tsv (Claude Code denies
# the approve command, file-tool edits and shell redirection into it — bin/install-claude-
# permissions.sh — but an agent determined to evade those, e.g. via an interpreter, can still
# write one); a harness with no deny rules whose agent terminal is a real TTY; deleting the whole
# log (verify then reads "predates the lock": MANUAL, not PASS); and a loosening committed to git
# (reported MANUAL, below, so a merge never reads as tampering). Each of those is a deliberate
# forgery visible in git, not a flag the rule allowed.
#
# Covered baselines (kind -> file, relative to the project root):
#   lint         .claude/lint-baseline.json     project-bin/lint-gate.sh
#   conformance  docs/conformance/baseline.tsv  project-bin/conformance-check.sh
# "Looser" means: lint — any rule's count above the previous one; conformance — any row OK in the
# previous baseline and present but not OK now. Content is compared with CR stripped, so a CRLF
# checkout (Windows autocrlf) hashes the same as LF.
#
# Records (commit them with the baseline):
#   .claude/baseline-approvals.tsv            ts kind sha256 by note   — ONLY baseline-approve.sh
#   .claude/baseline-writes.tsv               ts kind sha256 basis     — every write an instrument made
#   .claude/baseline-history/<kind>/<sha256>  the content of each recorded write
#   .claude/baseline-pending/<kind>[.summary] the refused proposal, for the person to review
#
# Usage (instruments, baseline-approve.sh and gate-check call it; a person never needs to):
#   baseline-lock.sh file     <kind>                         print the baseline path (relative)
#   baseline-lock.sh sha      <file>                         sha256 of the file, CR stripped
#   baseline-lock.sh verify   <root> <kind>                  print STATE<TAB>note, exit 0
#       NONE    no baseline and no record                    (a first write needs no approval)
#       GONE    no baseline, but records exist               (re-creating it needs approval)
#       PASS    approved, or no looser than the last verified write
#       FAIL    looser than the last verified write with no approval, or a recorded write that
#               loosened without one (a forged record)
#       MANUAL  no record at all (predates the lock), or the looser content is exactly what git
#               HEAD holds (a merge or checkout brought it in, not an uncommitted local edit)
#   baseline-lock.sh approved <root> <kind> <sha>            exit 0 iff an approval row matches
#   baseline-lock.sh record   <root> <kind> <basis>          log the baseline now on disk
#   baseline-lock.sh propose  <root> <kind> <file> <summary> save the proposal, print the ask
#
# Producer of the records: the two instruments above (writes, proposals) and
# project-bin/baseline-approve.sh (approvals). Consumer: those instruments and
# bin/gate-check.sh's "Baselines" line (toolkit copy, run against the project root).
set -uo pipefail

PY=""
for _c in python3 python py; do  # portability-ok: this IS the interpreter probe
  case "$(command -v "$_c" 2>/dev/null)" in *[Ww]indows[Aa]pps*) continue ;; esac
  if "$_c" -c 'import sys; sys.exit(0 if sys.version_info[0] == 3 else 1)' >/dev/null 2>&1; then PY="$_c"; break; fi
done
[ -n "$PY" ] || { echo "baseline-lock: Python 3 is required and was not found" >&2; exit 2; }

IFS= read -r -d '' _LOCK_PY <<'PY' || true
import datetime, hashlib, json, os, shutil, subprocess, sys

FILES = {"lint": ".claude/lint-baseline.json", "conformance": "docs/conformance/baseline.tsv"}
APPROVALS, WRITES, HISTORY = ".claude/baseline-approvals.tsv", ".claude/baseline-writes.tsv", ".claude/baseline-history"

def norm(b):
    return b.replace(b"\r", b"")

def sha_bytes(b):
    return hashlib.sha256(norm(b)).hexdigest()

def sha_file(p):
    return sha_bytes(open(p, "rb").read())

def rows(root, name, kind):
    p = os.path.join(root, name)
    if not os.path.isfile(p):
        return []
    out = []
    for line in open(p, encoding="utf-8", errors="replace"):
        f = line.rstrip("\r\n").split("\t")
        if len(f) >= 3 and f[1] == kind and f[0] != "ts":
            out.append(f)
    return out

def load(kind, b):
    t = norm(b).decode("utf-8", "replace")
    if kind == "lint":
        return {k: int(v) for k, v in (json.loads(t).get("counts") or {}).items()}
    d = {}
    for line in t.splitlines():
        f = line.split("\t")
        if len(f) >= 3 and f[0]:
            d[(f[0], f[1])] = f[2]
    return d

def looser(kind, prev, new):
    if kind == "lint":
        return [r for r in sorted(new) if new[r] > prev.get(r, 0)]
    return ["%s %s" % k for k in sorted(new) if prev.get(k) == "OK" and new[k] != "OK"]

def head_blob(root, rel):
    try:
        r = subprocess.run(["git", "-C", root, "show", "HEAD:./" + rel], capture_output=True, timeout=20)
        return r.stdout if r.returncode == 0 else None
    except (OSError, subprocess.SubprocessError):
        return None

def verify(root, kind):
    rel = FILES[kind]
    path = os.path.join(root, rel)
    w, a = rows(root, WRITES, kind), rows(root, APPROVALS, kind)
    approved = {r[2] for r in a}
    hw = head_blob(root, WRITES)
    committed = set(norm(hw).decode("utf-8", "replace").splitlines()) if hw else set()
    last, manual = None, []
    for r in w:
        snap = os.path.join(root, HISTORY, kind, r[2])
        if not os.path.isfile(snap) or sha_file(snap) != r[2]:
            return "FAIL", "recorded write %s (%s) has no matching snapshot under %s — the record cannot be checked" % (r[2][:12], r[0], HISTORY)
        try:
            c = load(kind, open(snap, "rb").read())
        except ValueError:
            return "FAIL", "recorded write %s (%s) is not a readable %s baseline" % (r[2][:12], r[0], kind)
        up = [] if last is None or r[2] in approved else looser(kind, last, c)
        if up and "\t".join(r) in committed:
            # Committed rows came through git: two branches that each wrote a baseline, merged.
            manual.append("recorded write %s (%s) is looser than the row before it (%s) but is committed — "
                          "a merge of two branches' baselines, not a local edit; review the history" % (r[2][:12], r[0], ", ".join(up[:5])))
            up = []
        if up:
            return "FAIL", ("recorded write %s (%s, basis %s) loosens the baseline (%s) and no approval matches it — "
                            "a record is checked against its content, not believed" % (r[2][:12], r[0], r[3] if len(r) > 3 else "?", ", ".join(up[:5])))
        last = c
    if not os.path.isfile(path):
        if w or a:
            return "GONE", "%s is missing but was recorded before — re-creating it needs a person: bin/baseline-approve.sh %s" % (rel, kind)
        return "NONE", "no %s baseline yet" % kind
    raw = open(path, "rb").read()
    s = sha_bytes(raw)
    if s in approved:
        return ("MANUAL", manual[0]) if manual else ("PASS", "%s matches a human approval" % rel)
    if last is None:
        return "MANUAL", "%s has no write record (it predates the lock) — cannot tell who moved it; the next instrument write starts the record" % rel
    try:
        cur = load(kind, raw)
    except ValueError:
        return "FAIL", "%s is not a readable %s baseline" % (rel, kind)
    up = looser(kind, last, cur)
    if not up:
        return ("MANUAL", manual[0]) if manual else ("PASS", "%s is no looser than its last recorded write" % rel)
    hb = head_blob(root, rel)
    if hb and sha_bytes(hb) == s:
        return "MANUAL", ("%s is looser than its last recorded write (%s) but is exactly what git HEAD holds — "
                          "it came through git (a merge or checkout), not a local edit; review its history, and if the "
                          "user accepts it they run: bin/baseline-approve.sh %s --current" % (rel, ", ".join(up[:5]), kind))
    return "FAIL", ("%s moved without approval: looser than its last recorded write (%s) — a person reviews it and runs: "
                    "bin/baseline-approve.sh %s --current" % (rel, ", ".join(up[:5]), kind))

def record(root, kind, basis):
    path = os.path.join(root, FILES[kind])
    raw = open(path, "rb").read()
    s = sha_bytes(raw)
    d = os.path.join(root, HISTORY, kind)
    os.makedirs(d, exist_ok=True)
    open(os.path.join(d, s), "wb").write(norm(raw))
    p = os.path.join(root, WRITES)
    new = not os.path.isfile(p)
    with open(p, "a") as f:
        if new:
            f.write("ts\tkind\tsha256\tbasis\n")
        f.write("%s\t%s\t%s\t%s\n" % (datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"), kind, s, basis))
    for n in (kind, kind + ".summary"):
        try:
            os.remove(os.path.join(root, ".claude", "baseline-pending", n))
        except OSError:
            pass

cmd, args = sys.argv[1], sys.argv[2:]
if cmd == "sha":
    print(sha_file(args[0]))
elif cmd == "verify":
    st, note = verify(args[0], args[1])
    print("%s\t%s" % (st, note))
elif cmd == "approved":
    sys.exit(0 if any(r[2] == args[2] for r in rows(args[0], APPROVALS, args[1])) else 1)
elif cmd == "record":
    record(args[0], args[1], args[2])
PY

_file() {
  case "$1" in
    lint)        echo ".claude/lint-baseline.json" ;;
    conformance) echo "docs/conformance/baseline.tsv" ;;
    *) echo "baseline-lock: unknown kind '$1' (lint | conformance)" >&2; return 2 ;;
  esac
}

cmd="${1:-}"; [ $# -gt 0 ] && shift
case "$cmd" in
  file)
    _file "$1" ;;
  sha)
    "$PY" -c "$_LOCK_PY" sha "$1" ;;
  verify|approved)
    _file "$2" >/dev/null || exit 2
    "$PY" -c "$_LOCK_PY" "$cmd" "$@" ;;
  record)
    _file "$2" >/dev/null || exit 2
    "$PY" -c "$_LOCK_PY" record "$@" ;;
  propose)
    root="$1"; kind="$2"; src="$3"; summary="$4"
    d="$root/.claude/baseline-pending"; mkdir -p "$d"
    cp "$src" "$d/$kind" && printf '%s\n' "$summary" > "$d/$kind.summary"
    echo "" >&2
    echo "   Moving this baseline is the user's call, and a flag the agent can type is not their" >&2
    echo "   answer. Show the user the change above, then ask THEM to run, in a separate terminal" >&2
    echo "   window (not the agent's, and not Claude Code's ! mode, which has no TTY):" >&2
    echo "       bin/baseline-approve.sh $kind" >&2
    echo "   (it shows the proposal and asks them to type 'approve'). Agents: do not run it —" >&2
    echo "   it is denied to you and refuses without a terminal. Then re-run the same command." >&2
    ;;
  *)
    sed -n '2,57p' "$0"; exit 2 ;;
esac
