#!/usr/bin/env python3
# mx-metadata-note.py -- write the Studio Pro revision note (refs/notes/mx_metadata) for commits
# made outside Studio Pro, WITH the list of changed documents.
#
#   bin/mx-metadata-note.py changes  [<commit>]          # print the ModelChanges JSON array
#   bin/mx-metadata-note.py write    [<commit>] [--force] # write that commit's note
#   bin/mx-metadata-note.py backfill [<rev-range>] [--dry-run] [--force]
#   bin/mx-metadata-note.py sync     <remote>            # fetch + merge the remote's notes, then push
#   (all take --mpr <path-from-git-top> when there is more than one candidate .mpr)
#   Run it as "$PY" bin/mx-metadata-note.py, PY from _common.sh's resolve_py -- never through the
#   shebang: on Windows "python3" is often the Microsoft Store stub.
#
# A note whose ModelChanges is already non-empty is Studio Pro's (or an earlier run's) and is left
# alone; --force recomputes it. sync never lets our note replace a colleague's non-empty one.
#
# WHY (2026-10-12, field project). Studio Pro's History pane does not read the changed documents
# from the commit. It reads the "ModelChanges" array of the commit's git note in
# refs/notes/mx_metadata, which Studio Pro writes when IT commits. Everything else (mxcli, agents,
# people at a shell) wrote that note by hand from platform-link.md trap 6c with
# "ModelChanges":[], so 270 of 270 notes on the field project showed "Model changes 0", and the
# "which microflow, which page" history was gone for every CLI commit.
#
# HOW. MPR v2 keeps one BSON file per document under <mpr dir>/mprcontents/xx/yy/<uuid>.mxunit,
# and the document tree (ContainerID) in the .mpr's SQLite Unit table. A commit's changed
# documents are its changed .mxunit files; $Type and Name are top-level BSON strings; the module
# is the first Projects$ModuleImpl up the ContainerID chain, in that commit's own .mpr. Entry
# shape is Studio Pro's, field for field:
#   {"Status":"Added|Modified|Deleted","UnitID":..,"UnitType":..,"UnitName":..,"Module":..}
# Project-level units (ProjectSecurity, Navigation) carry "" for UnitName and Module, as Studio
# Pro writes them.
#
# MEASURED, not assumed: against Studio Pro's own notes on 51 Studio Pro commits in 5 local apps,
# 3387 of 3389 entries reproduce exactly on all five fields. The misses: 2 entries Studio Pro
# listed whose .mxunit did not change in git, and 21 extra entries on commits whose PARENT was a
# CLI commit -- Studio Pro diffs against its own last state, not the git parent. Field run: 158
# notes backfilled on a 357-commit field app, pushed, and Studio Pro 11.15 History shows them (screenshot
# confirmed by the user, 2026-10-12).
#
# PRODUCER/CONSUMER. Reads only git objects -- no working tree, no mxcli, no mxbuild. Run by the
# post-commit / post-rewrite hooks bin/install-project-hooks.sh installs (init-project.sh and
# sync-project.sh run that installer). Studio Pro is the consumer. Never blocks a commit: every
# failure prints one warning and exits 0, because a missing note costs a History entry and a
# refused commit costs work.
#
# Stdlib only (sqlite3, json, subprocess): runs under any python3 on mac, Linux and Git Bash.

import json, os, re, sqlite3, struct, subprocess, sys, tempfile

REF = "mx_metadata"
STATUS = {"A": "Added", "M": "Modified", "D": "Deleted"}
UNIT_RE = re.compile(r"([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})\.mxunit$")


def git(*args, binary=False, check=True):
    r = subprocess.run(["git", *args], capture_output=True, check=check)
    return r.stdout if binary else r.stdout.decode("utf-8", "replace")


def top_level_strings(b, keys=("$Type", "Name")):
    """Read top-level string fields of a BSON document, skipping every other value by length.
    Handles every BSON element type, so no unit can make it raise on an unexpected value."""
    out, i, end = {}, 4, struct.unpack_from("<i", b, 0)[0] - 1
    fixed = {0x01: 8, 0x06: 0, 0x07: 12, 0x08: 1, 0x09: 8, 0x0A: 0, 0x10: 4, 0x11: 8, 0x12: 8,
             0x13: 16, 0x7F: 0, 0xFF: 0}
    while i < end:
        t = b[i]; i += 1
        j = b.index(b"\x00", i); k = b[i:j].decode("utf-8", "replace"); i = j + 1
        if t in (0x02, 0x0D, 0x0E):                      # string, JS code, symbol
            n = struct.unpack_from("<i", b, i)[0]
            if k in keys and t == 0x02:
                out[k] = b[i + 4:i + 3 + n].decode("utf-8", "replace")
            i += 4 + n
        elif t in (0x03, 0x04, 0x0F):                    # document, array, code-with-scope
            i += struct.unpack_from("<i", b, i)[0]
        elif t == 0x05:                                  # binary
            i += 5 + struct.unpack_from("<i", b, i)[0]
        elif t == 0x0B:                                  # regex: two cstrings
            i = b.index(b"\x00", b.index(b"\x00", i) + 1) + 1
        elif t == 0x0C:                                  # DBPointer
            i += 4 + struct.unpack_from("<i", b, i)[0] + 12
        elif t in fixed:
            i += fixed[t]
        else:
            raise ValueError(f"unknown BSON type 0x{t:02x} at key {k!r}")
    return out


def guid(blob):
    """SQLite Unit table GUIDs are .NET byte order (first three groups little-endian)."""
    b = bytes(blob)
    h = (b[3::-1] + b[5:3:-1] + b[7:5:-1] + b[8:]).hex()
    return f"{h[:8]}-{h[8:12]}-{h[12:16]}-{h[16:20]}-{h[20:]}"


def find_mpr(arg=None):
    """The .mpr path relative to the git top level, symlinks resolved (two-tree layout keeps
    app/App.mpr with a root symlink, and git stores the symlink, not the model)."""
    top = git("rev-parse", "--show-toplevel").strip()
    if arg:
        cands = [os.path.join(top, arg) if not os.path.isabs(arg) else arg]
    else:
        cands = [os.path.join(top, f) for f in sorted(os.listdir(top)) if f.endswith(".mpr")]
        if not cands and os.path.isdir(os.path.join(top, "app")):
            cands = [os.path.join(top, "app", f) for f in sorted(os.listdir(os.path.join(top, "app")))
                     if f.endswith(".mpr")]
    real = sorted({os.path.realpath(c) for c in cands if os.path.exists(c)})
    if len(real) != 1:
        raise SystemExit(f"mx-metadata-note: expected one .mpr, found {len(real)} -- pass --mpr <path>")
    return os.path.relpath(real[0], os.path.realpath(top)).replace(os.sep, "/")


class Rev:
    """The model as it stood at one commit."""

    def __init__(self, rev, mpr):
        self.rev, self.mpr = rev, mpr
        self.contents = (os.path.dirname(mpr) + "/mprcontents").lstrip("/")
        self._units, self._parent = {}, None

    def parent_of(self, uid):
        if self._parent is None:
            fd, path = tempfile.mkstemp(suffix=".mpr")
            try:
                with os.fdopen(fd, "wb") as f:
                    f.write(git("show", f"{self.rev}:{self.mpr}", binary=True))
                db = sqlite3.connect(path)
                try:
                    self._parent = {guid(u): (guid(c) if c else None)
                                    for u, c in db.execute("select UnitID, ContainerID from Unit")}
                finally:
                    db.close()
            finally:
                os.unlink(path)
        return self._parent.get(uid)

    def unit(self, uid):
        if uid not in self._units:
            path = f"{self.contents}/{uid[:2]}/{uid[2:4]}/{uid}.mxunit"
            r = subprocess.run(["git", "show", f"{self.rev}:{path}"], capture_output=True)
            self._units[uid] = top_level_strings(r.stdout) if r.returncode == 0 else {}
        return self._units[uid]

    def module_of(self, uid):
        seen, cur = set(), uid
        while cur and cur not in seen:
            seen.add(cur)
            d = self.unit(cur)
            if d.get("$Type") == "Projects$ModuleImpl":
                return d.get("Name", "")
            cur = self.parent_of(cur)
        return ""


def model_changes(commit, mpr):
    parents = git("rev-list", "--parents", "-n1", commit).split()[1:]
    if not parents:
        return []
    contents = (os.path.dirname(mpr) + "/mprcontents").lstrip("/")
    diff = git("diff", "--name-status", "--no-renames", parents[0], commit, "--", contents)
    revs, out = {}, []
    for line in diff.splitlines():
        st, path = line.split("\t", 1)
        m = UNIT_RE.search(path)
        if not m:
            continue
        uid = m.group(1)
        side = parents[0] if st == "D" else commit       # a deleted unit is read where it last lived
        rev = revs.setdefault(side, Rev(side, mpr))
        d = rev.unit(uid)
        out.append({"Status": STATUS.get(st[0], "Modified"), "UnitID": uid,
                    "UnitType": d.get("$Type", ""), "UnitName": d.get("Name", ""),
                    "Module": rev.module_of(uid)})
    return out


def modeler_version(commit, mpr):
    fd, path = tempfile.mkstemp(suffix=".mpr")
    try:
        with os.fdopen(fd, "wb") as f:
            f.write(git("show", f"{commit}:{mpr}", binary=True))
        db = sqlite3.connect(path)
        try:
            return db.execute("select * from _MetaData").fetchone()[1]
        finally:
            db.close()
    finally:
        os.unlink(path)


def touches_model(commit, mpr):
    contents = (os.path.dirname(mpr) + "/mprcontents").lstrip("/")
    return bool(git("diff-tree", "--no-commit-id", "--name-only", "-r", "--root", commit, "--", mpr, contents).strip())


def write_note(commit, mpr, dry=False, force=False):
    """Keep every key an existing note has (Studio Pro reads ModelerVersion from it); fill
    ModelChanges. A note that already lists changes is left alone unless force: Studio Pro diffs
    against its own last state, not the git parent, so its list is the authoritative one. A commit with no note gets one only if it touches the model -- a docs commit
    then shows in History exactly as Studio Pro would show it (Studio Pro falls back to the
    newest note for the version, platform-link.md trap 6c)."""
    commit = git("rev-parse", commit).strip()
    r = subprocess.run(["git", "notes", f"--ref={REF}", "show", commit], capture_output=True)
    if r.returncode == 0:
        try:
            note = json.loads(r.stdout)
        except ValueError:
            return f"{commit[:7]} existing note is not JSON -- left alone"
        if note.get("ModelChanges") and not force:
            return None
    elif touches_model(commit, mpr):
        branch = git("rev-parse", "--abbrev-ref", "HEAD", check=False).strip()
        note = {"BranchName": "" if branch == "HEAD" else branch,
                "ModelerVersion": modeler_version(commit, mpr), "ModelChanges": [],
                "RelatedStories": [], "isWebModelerCommit": False}
    else:
        return None
    changes = model_changes(commit, mpr)
    if note.get("ModelChanges") == changes and r.returncode == 0:
        return None
    note["ModelChanges"] = changes
    if not dry:
        subprocess.run(["git", "notes", f"--ref={REF}", "add", "-f", "-m",
                        json.dumps(note, separators=(",", ":")), commit], check=True, capture_output=True)
    return f"{commit[:7]} {len(changes):4} model changes"


def _ref_ok(ref):
    return subprocess.run(["git", "rev-parse", "-q", "--verify", ref], capture_output=True).returncode == 0


def _show(ref, commit):
    r = subprocess.run(["git", "notes", f"--ref={ref}", "show", commit], capture_output=True)
    return r.stdout if r.returncode == 0 else None


def _changes(raw):
    try:
        return bool(json.loads(raw).get("ModelChanges"))
    except (ValueError, AttributeError, TypeError):
        return False


def sync(remote):
    """Merge the remote's notes before pushing ours -- a 3-way merge of the notes history, never a
    force push. A note only one side changed takes that side's version. A note BOTH sides changed
    since they last agreed keeps ours (-s ours) -- unless theirs lists model changes: then theirs
    wins, so our computed notes are never pushed over a colleague's (Studio Pro's) non-empty one."""
    git("fetch", remote, f"+refs/notes/{REF}:refs/notes/{REF}-remote")
    if not _ref_ok(f"refs/notes/{REF}-remote"):
        subprocess.run(["git", "push", remote, f"refs/notes/{REF}:refs/notes/{REF}"], check=True)
        return 0
    base = None
    if _ref_ok(f"refs/notes/{REF}"):
        base = git("merge-base", f"refs/notes/{REF}", f"refs/notes/{REF}-remote", check=False).strip() or None
    if base:
        git("update-ref", f"refs/notes/{REF}-base", base)
    try:
        subprocess.run(["git", "notes", f"--ref={REF}", "merge", "-q", "-s", "ours",
                        f"refs/notes/{REF}-remote"], check=True)
        kept = 0
        for line in git("notes", f"--ref={REF}-remote", "list").splitlines():
            blob, commit = line.split()
            theirs = git("cat-file", "blob", blob, binary=True)
            if not _changes(theirs) or _show(REF, commit) == theirs:
                continue
            if base and _show(f"{REF}-base", commit) == theirs:
                continue                                 # only we changed it (write --force): ours stands
            subprocess.run(["git", "notes", f"--ref={REF}", "add", "-f", "-C", blob, commit],
                           check=True, capture_output=True)
            kept += 1
        if kept:
            print(f"mx_metadata sync: kept {kept} colleague note(s) that list model changes over ours")
    finally:
        if base:
            git("update-ref", "-d", f"refs/notes/{REF}-base", check=False)
    subprocess.run(["git", "push", remote, f"refs/notes/{REF}:refs/notes/{REF}"], check=True)
    return 0


def main(argv):
    args = list(argv)
    dry, force = "--dry-run" in args, "--force" in args
    args = [a for a in args if a not in ("--dry-run", "--force")]
    mpr_arg = None
    if "--mpr" in args:
        i = args.index("--mpr"); mpr_arg = args[i + 1]; del args[i:i + 2]
    cmd = args.pop(0) if args else "help"
    if cmd == "sync":
        if not args:
            raise SystemExit("usage: mx-metadata-note.py sync <remote>")
        return sync(args[0])
    if cmd not in ("changes", "write", "backfill"):
        print("usage: mx-metadata-note.py changes|write [<commit>] [--force] | backfill [<range>] [--dry-run] [--force] | sync <remote>  [--mpr <path>]")
        return 2
    mpr = find_mpr(mpr_arg)
    if cmd == "changes":
        print(json.dumps(model_changes(git("rev-parse", args[0] if args else "HEAD").strip(), mpr), indent=1))
    elif cmd == "write":
        msg = write_note(args[0] if args else "HEAD", mpr, dry, force)
        if msg:
            print(f"mx_metadata note: {msg}")
    else:
        n = 0
        for c in git("rev-list", "--reverse", args[0] if args else "HEAD").split():
            msg = write_note(c, mpr, dry, force)
            if msg:
                n += 1; print(msg)
        print(f"{'would update' if dry else 'updated'} {n} notes")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv[1:]))
    except SystemExit:
        raise
    except Exception as e:  # never break a commit over a note
        print(f"⚠ mx-metadata-note: {type(e).__name__}: {e}", file=sys.stderr)
        sys.exit(0 if os.environ.get("MXTK_HOOK") else 1)
