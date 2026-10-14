#!/usr/bin/env bash
# token-burn.sh — how many tokens this project has burned, by model, by day and (best effort)
# by stage, read from the Claude Code transcripts on this machine.
#
#   bin/token-burn.sh <project-root>              # the screen: per model, per day, per stage
#   bin/token-burn.sh <project-root> --brief      # one line: "Tokens this stage: …" (status.sh)
#   bin/token-burn.sh <project-root> --scan-all   # look in every transcript dir, not only the
#                                                 # project's own and its ancestors/descendants
#   bin/token-burn.sh <project-root> --json       # the same numbers as one JSON object
#   ... --rates FILE     # + cost per model at YOUR per-Mtok rates (format: "RATES FILE" below)
#   ... --windows FILE   # + per-window table: tokens, cost, agent time, human prompts
#   ... --effort [--gap MIN]  # + agent working time and human prompt count (default gap 5 min)
#
# PRODUCER. The Claude Code harness (CLI, desktop app, IDE extension) writes one JSONL
# transcript per session under `$CLAUDE_CONFIG_DIR/projects/<slug>/<session>.jsonl` (default
# `~/.claude/projects`), plus `<slug>/<session>/subagents/agent-*.jsonl` for Agent-tool
# workers. `<slug>` is the launch directory with every non-alphanumeric character replaced by
# `-`. Nothing else produces that tree: a claude.ai chat, Cowork, Copilot, Cursor and Windsurf
# sessions leave no transcript here, and for them this instrument prints NOT AVAILABLE and
# exits 0 — an absent number, never a zero that reads as "free".
#
# WHAT IS COUNTED. Every `assistant` record's `message.usage`: input_tokens,
# cache_creation_input_tokens (cache write), cache_read_input_tokens, output_tokens, grouped
# by `message.model`. Three facts about the format, each learned from a real transcript
# (2026-09-18, a 17,000-line toolkit session) and each one a silent miscount if ignored:
#   1. The harness writes ONE RECORD PER STREAMED CONTENT BLOCK, all carrying the same
#      `message.id` — that session had 4,336 assistant records for 1,989 messages, so summing
#      records overcounts ~2×. Usage is summed ONCE per `message.id`, taking each counter's
#      MAX over that id's records (in practice the last record; a later record with an empty or
#      zero usage cannot erase real numbers): the usage is NOT the same on every record. In subagent transcripts the early
#      records carry a partial `output_tokens` (the captured fixture: 60 on the first record,
#      1,559 on the last; a 2026-10 multi-agent session: 37,791 vs 84,915 subagent output
#      tokens, first vs last). Keeping the first record undercounted subagent output by up to
#      7× in a field measurement; main-thread records were identical first to last. The
#      message's day and time are its FIRST record's (when it started).
#   2. `message.model` is `<synthetic>` on harness-generated records (aborts, errors). Skipped.
#   3. `cwd` is per RECORD, not per session, and a session launched in `~` can spend most of its
#      tokens inside `~/proj`. So records are attributed to the project by their own `cwd`
#      being at or under the project root (the `app/` two-tree layout is under the root, so it
#      needs nothing special), never by which slug directory they sit in. By default the slug
#      directories of the project itself, its ancestors and its descendants are read;
#      `--scan-all` reads every directory, for a project that moved or was symlinked.
#
# THE HEADLINE NUMBER is input + cache write + output. Cache READS are shown separately: they
# are the bulk of the count on any long session and are billed at a fraction of input, so
# folding them in makes every number meaningless. No currency is printed — pricing is per
# model, per plan and per month, and a number that is wrong next quarter is worse than none.
#
# STAGE ATTRIBUTION is by date, from the dated rows of the Decisions table in PROJECT.md
# (`| <stage> | … | CONFIRMED 2026-07-21 | …`): a day is attributed to the highest stage whose
# dated row is on or before it; days before the first dated row, and every day when there is
# no PROJECT.md, land in UNMAPPED. It is a step function over register dates, not a record of
# which stage a session was actually working — the caveat is printed with the table. Dispatch
# lines (runbook §1c) will sharpen it once they carry a stage and a date.
#
# COST, TIME AND PROMPTS (#296, opt-in — without these flags every output above is byte-for-
# byte what it was). Asked for in the field as "money and time per round and per feature",
# which the project had to answer with ad-hoc scripts over the transcripts.
#   RATES FILE (--rates): no price is built in — rates change per model, plan and month, so they
#     come from the project. One line per model glob, first match wins, `*` as a catch-all:
#         currency EUR                      # optional label, default EUR
#         # glob          input  cache-write  cache-read  output     (per million tokens)
#         claude-fable-*  2.80   3.50         0.28        14.00
#         *               0.90   1.10         0.09        4.50
#     A model no line matches is printed UNPRICED and the total is marked incomplete — never 0.
#   WINDOWS FILE (--windows): one line per window, `<start> <name...>`, start as YYYY-MM-DD or
#     YYYY-MM-DDTHH:MM[:SS] (UTC); a window runs until the next one starts, the last one is
#     open-ended, and anything before the first lands in "(before first window)". Use it for
#     setup / map / round N / wrap-up boundaries.
#   AGENT WORKING TIME: per main-thread transcript file, the sum of gaps between consecutive
#     user/assistant records that are <= --gap minutes, EXCLUDING every gap that ends at a
#     human prompt (that gap is the human thinking, not the agent working). Subagent time is
#     not added: it runs inside the main thread's own gaps.
#   HUMAN PROMPTS: main-thread `user` records that are not tool results, not `isMeta`, not a
#     compact summary; when the harness writes `origin`, only `origin.kind == "human"` counts
#     (task notifications and peer messages are `user` records too); older records without
#     `origin` count unless their text starts with `<` (harness-injected command/notification
#     wrappers). Counted once per `uuid`. The text is read only to make that test and is
#     never printed — every output is an aggregate.
#
# Exit 0 always — this is read, never gated on (a malformed --rates/--windows file is a usage
# error, exit 1). Bash 3.2 + Python 3 via lib/portable.sh.
set -u
TOOLKIT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib/portable.sh
. "$TOOLKIT_ROOT/bin/lib/portable.sh"

PROJECT_DIR=""; MODE=screen; SCAN_ALL=0; RATES=""; WINDOWS=""; EFFORT=0; GAP=5
USAGE="usage: bin/token-burn.sh <project-root> [--brief|--json] [--scan-all] [--rates FILE] [--windows FILE] [--effort] [--gap MIN]"
while [ $# -gt 0 ]; do
  a="$1"
  case "$a" in
    --brief) MODE=brief ;;
    --json) MODE=json ;;
    --scan-all) SCAN_ALL=1 ;;
    --effort) EFFORT=1 ;;
    --rates|--windows|--gap)
      [ $# -ge 2 ] || { echo "$a needs a value" >&2; echo "$USAGE" >&2; exit 1; }
      case "$a" in
        --rates) RATES="$2" ;;
        --windows) WINDOWS="$2" ;;
        --gap) GAP="$2"; EFFORT=1 ;;
      esac
      shift ;;
    -h|--help) sed -n '2,11p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    --*) echo "unknown option: $a" >&2; exit 1 ;;
    *) PROJECT_DIR="$a" ;;
  esac
  shift
done
[ -n "$PROJECT_DIR" ] || { echo "$USAGE" >&2; exit 1; }
for f in "$RATES" "$WINDOWS"; do
  [ -z "$f" ] || [ -f "$f" ] || { echo "not a file: $f" >&2; exit 1; }
done
case "$GAP" in ''|*[!0-9.]*) echo "--gap takes minutes (a number), got: $GAP" >&2; exit 1 ;; esac
PROJECT_DIR="$(cd "$PROJECT_DIR" 2>/dev/null && pwd)" || { echo "not a directory: $PROJECT_DIR" >&2; exit 1; }

TRANSCRIPTS="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/projects"
if [ ! -d "$TRANSCRIPTS" ]; then
  case "$MODE" in
    brief) echo "Tokens this stage: NOT AVAILABLE (no Claude Code transcript tree at $TRANSCRIPTS — claude.ai chat, Cowork, Copilot and Cursor sessions leave none)" ;;
    json)  printf '{"available": false, "reason": "no transcript tree at %s"}\n' "$TRANSCRIPTS" ;;
    *)     echo "NOT AVAILABLE — no Claude Code transcript tree at $TRANSCRIPTS (claude.ai chat, Cowork, Copilot and Cursor sessions leave none)" ;;
  esac
  exit 0
fi

require_py
"$PY" - "$PROJECT_DIR" "$TRANSCRIPTS" "$MODE" "$SCAN_ALL" "$RATES" "$WINDOWS" "$EFFORT" "$GAP" <<'PYEOF'
import json, os, re, sys, fnmatch, calendar
from collections import defaultdict

project, root, mode, scan_all = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4] == "1"
rates_file, windows_file = sys.argv[5], sys.argv[6]
want_effort = sys.argv[7] == "1" or bool(windows_file)
gap_s = float(sys.argv[8]) * 60.0

def die(msg):
    sys.stderr.write("token-burn: " + msg + "\n")
    sys.exit(1)

def epoch(ts):
    """ISO-8601 UTC (the transcript's `2026-09-08T00:59:57.347Z`, or a windows-file start) ->
    seconds. None when it does not parse — such a record carries no time, never time 0."""
    m = re.match(r"^(\d{4})-(\d{2})-(\d{2})(?:[T ](\d{2}):(\d{2})(?::(\d{2})(\.\d+)?)?)?(Z|[+-]00:?00)?$", ts or "")
    if not m:
        return None
    y, mo, d, hh, mi, ss, frac = m.group(1, 2, 3, 4, 5, 6, 7)
    t = calendar.timegm((int(y), int(mo), int(d), int(hh or 0), int(mi or 0), int(ss or 0), 0, 0, 0))
    return t + (float(frac) if frac else 0.0)

# --- --rates: per-Mtok prices from the project's own file, never built in -------------------
currency, rates = "EUR", []
if rates_file:
    with open(rates_file, encoding="utf-8", errors="replace") as fh:
        for n, line in enumerate(fh, 1):
            line = line.split("#", 1)[0].strip()
            if not line:
                continue
            f = line.split()
            if f[0] == "currency" and len(f) == 2:
                currency = f[1]
                continue
            if len(f) != 5:
                die("%s:%d: want `<model-glob> <input> <cache-write> <cache-read> <output>` (per Mtok), got %d field(s)" % (rates_file, n, len(f)))
            try:
                rates.append((f[0], [float(x) for x in f[1:]]))
            except ValueError:
                die("%s:%d: rates must be numbers" % (rates_file, n))
    if not rates:
        die("%s: no rate lines" % rates_file)

def rate_for(model):
    for glob, r in rates:
        if fnmatch.fnmatchcase(model, glob):
            return r
    return None

def cost_of(model, vals):
    r = rate_for(model)
    return None if r is None else sum(v * x for v, x in zip(vals, r)) / 1e6

# --- --windows: named time windows, each running until the next one starts ------------------
windows = []
if windows_file:
    with open(windows_file, encoding="utf-8", errors="replace") as fh:
        for n, line in enumerate(fh, 1):
            line = line.split("#", 1)[0].strip()
            if not line:
                continue
            f = line.split(None, 1)
            t = epoch(f[0])
            if t is None or len(f) < 2:
                die("%s:%d: want `<YYYY-MM-DD[THH:MM[:SS]]> <name>`" % (windows_file, n))
            windows.append((t, f[1].strip(), f[0]))
    if not windows:
        die("%s: no window lines" % windows_file)
    windows.sort()
BEFORE = "(before first window)"

def window_for(t):
    name = BEFORE
    for start, wname, _raw in windows:
        if t is not None and t >= start:
            name = wname
    return name

def slug(path):
    return re.sub(r"[^A-Za-z0-9]", "-", path)

proj_slug = slug(project)

# --- which slug directories to read -------------------------------------------------------
dirs = []
for name in sorted(os.listdir(root)):
    full = os.path.join(root, name)
    if not os.path.isdir(full):
        continue
    if scan_all or name == proj_slug or proj_slug.startswith(name + "-") or name.startswith(proj_slug + "-"):
        dirs.append(full)

def jsonl_files(d):
    for entry in sorted(os.listdir(d)):
        p = os.path.join(d, entry)
        if entry.endswith(".jsonl") and os.path.isfile(p):
            yield p
        elif os.path.isdir(p):
            sub = os.path.join(p, "subagents")
            if os.path.isdir(sub):
                for e in sorted(os.listdir(sub)):
                    if e.endswith(".jsonl"):
                        yield os.path.join(sub, e)

def under_project(cwd):
    if not cwd:
        return False
    cwd = cwd.rstrip("/\\")
    return cwd == project or cwd.startswith(project + "/") or cwd.startswith(project + "\\")

# --- read ---------------------------------------------------------------------------------
KEYS = ("input_tokens", "cache_creation_input_tokens", "cache_read_input_tokens", "output_tokens")
seen = set()
by_model = defaultdict(lambda: [0, 0, 0, 0, 0])   # + message count
by_day = defaultdict(lambda: [0, 0, 0, 0, 0])
day_model = defaultdict(lambda: defaultdict(int)) # day -> model -> headline
sidechain = [0, 0]                                 # headline tokens: main, subagent
n_files = n_records = n_synthetic = 0
msgs = []                                          # (epoch, model, vals, is_sidechain) per message
last, msg_order = {}, []                             # message.id -> [first ts, model, max usage, sidechain]
human_seen = set()
humans = []                                        # epoch per human prompt
timeline = defaultdict(list)                       # main-thread file -> [(epoch, is_human)]

def is_human_prompt(rec):
    if rec.get("type") != "user" or rec.get("isSidechain") or rec.get("isMeta") or rec.get("isCompactSummary"):
        return False
    c = (rec.get("message") or {}).get("content")
    if isinstance(c, list):
        if any(isinstance(b, dict) and b.get("type") == "tool_result" for b in c):
            return False
        texts = [b.get("text") for b in c if isinstance(b, dict) and b.get("type") == "text"]
        c = texts[0] if texts else ""
    if isinstance(rec.get("origin"), dict):
        return rec["origin"].get("kind") == "human"
    return isinstance(c, str) and not c.lstrip().startswith("<")

for d in dirs:
    for f in jsonl_files(d):
        n_files += 1
        with open(f, encoding="utf-8", errors="replace") as fh:
            for line in fh:
                try:
                    rec = json.loads(line)
                except ValueError:
                    continue
                if want_effort and rec.get("type") in ("user", "assistant") and not rec.get("isSidechain") \
                        and os.sep + "subagents" + os.sep not in f and under_project(rec.get("cwd")):
                    t = epoch(rec.get("timestamp"))
                    if t is not None:
                        hp = is_human_prompt(rec)
                        if hp:
                            key = rec.get("uuid") or (f + "@" + str(rec.get("timestamp")))
                            if key in human_seen:
                                continue
                            human_seen.add(key)
                            humans.append(t)
                        timeline[f].append((t, hp))
                if rec.get("type") != "assistant":
                    continue
                msg = rec.get("message") or {}
                model = msg.get("model") or "?"
                if model == "<synthetic>":
                    n_synthetic += 1
                    continue
                if not under_project(rec.get("cwd")):
                    continue
                n_records += 1
                mid = msg.get("id") or rec.get("uuid") or (f + str(n_records))
                u = msg.get("usage") or {}
                vals = [int(u.get(k) or 0) for k in KEYS]
                if mid in seen:
                    # later record of the same message: per-field max, so a later record's
                    # larger (final) count wins but an empty/zero usage never erases real numbers
                    last[mid][2] = [max(x, y) for x, y in zip(last[mid][2], vals)]
                    continue
                seen.add(mid)
                msg_order.append(mid)
                last[mid] = [rec.get("timestamp") or "", model, vals, bool(rec.get("isSidechain"))]

# one entry per message.id: first record's time, per-field max over its records (header, fact 1)
for mid in msg_order:
    ts, model, vals, side = last[mid]
    day = ts[:10] or "????-??-??"
    for i, v in enumerate(vals):
        by_model[model][i] += v
        by_day[day][i] += v
    by_model[model][4] += 1
    by_day[day][4] += 1
    head = vals[0] + vals[1] + vals[3]
    day_model[day][model] += head
    msgs.append((epoch(ts), model, vals, side))
    sidechain[1 if side else 0] += head

def headline(v):
    return v[0] + v[1] + v[3]

# --- stage attribution from PROJECT.md ----------------------------------------------------
reg = os.path.join(project, "PROJECT.md")
stage_rows = []   # (date, stage_rank, stage_label)
def rank(s):
    return -1 if s == "P" else int(s)
if os.path.isfile(reg):
    with open(reg, encoding="utf-8", errors="replace") as fh:
        for line in fh:
            m = re.match(r"^\|\s*(P|\d{1,2})\s*\|", line)
            if not m:
                continue
            for dt in re.findall(r"\b(\d{4}-\d{2}-\d{2})\b", line):
                stage_rows.append((dt, rank(m.group(1)), m.group(1)))
stage_rows.sort()

def stage_for(day):
    best = None
    for dt, r, label in stage_rows:
        if dt <= day and (best is None or r > best[0]):
            best = (r, label)
    return best[1] if best else "UNMAPPED"

current = None
if os.path.isfile(reg):
    with open(reg, encoding="utf-8", errors="replace") as fh:
        txt = fh.read()
    m = re.search(r"^## Current stage.*?\n\s*\*\*Stage\s+(P|\d{1,2})", txt, re.S | re.M)
    if m:
        current = m.group(1)

by_stage = defaultdict(lambda: [0, 0, 0, 0, 0])
stage_days = defaultdict(int)
stage_model = defaultdict(lambda: defaultdict(int))
for day, v in by_day.items():
    s = stage_for(day)
    for i in range(5):
        by_stage[s][i] += v[i]
    stage_days[s] += 1
    for mdl, h in day_model[day].items():
        stage_model[s][mdl] += h

def k(n):
    return "%dk" % round(n / 1000.0) if n >= 1000 else str(n)

def short(model):
    return re.sub(r"^claude-", "", model)

def split(mm):
    tot = sum(mm.values()) or 1
    parts = sorted(mm.items(), key=lambda kv: -kv[1])
    return " · ".join("%s %d%%" % (short(m), round(100.0 * h / tot)) for m, h in parts[:4])

total = [0, 0, 0, 0, 0]
for v in by_model.values():
    for i in range(5):
        total[i] += v[i]

caveat = ("stage = highest stage whose dated PROJECT.md row is on or before that day (UTC); "
          "UNMAPPED = before the first dated row" if stage_rows else
          "no dated stage rows in PROJECT.md — every day is UNMAPPED")

# --- opt-in: cost, agent time, human prompts, windows (#296) -------------------------------
def money(x):
    return "UNPRICED" if x is None else "%.2f" % x

cost = None
if rates_file:
    cm = {}
    unpriced = set()
    for t, mdl, vals, side in msgs:
        r = rate_for(mdl)
        if r is None:
            unpriced.add(mdl)
            continue
        e = cm.setdefault(mdl, [0.0, 0.0, 0.0, 0.0])
        for i in range(4):
            e[i] += vals[i] * r[i] / 1e6
    side_cost = [0.0, 0.0]
    for t, mdl, vals, side in msgs:
        c = cost_of(mdl, vals)
        if c is not None:
            side_cost[1 if side else 0] += c
    cost = {"currency": currency, "rates_file": rates_file,
            "by_model": {m: [round(x, 4) for x in v] + [round(sum(v), 4)] for m, v in cm.items()},
            "total": round(sum(sum(v) for v in cm.values()), 4),
            "main": round(side_cost[0], 4), "subagents": round(side_cost[1], 4),
            "unpriced_models": sorted(unpriced), "complete": not unpriced}

def agent_seconds(pred=lambda t: True):
    tot = 0.0
    for f, evs in timeline.items():
        evs = sorted(evs)
        for (t0, _h0), (t1, h1) in zip(evs, evs[1:]):
            d = t1 - t0
            if 0 < d <= gap_s and not h1 and pred(t1):
                tot += d
    return tot

def hm(sec):
    mins = int(round(sec / 60.0))
    return "%dh %02dm" % (mins // 60, mins % 60)

effort = None
if want_effort:
    effort = {"agent_seconds": round(agent_seconds()), "human_prompts": len(humans),
              "gap_minutes": gap_s / 60.0, "main_thread_files": len(timeline)}

win = None
if windows:
    names = [BEFORE] + [w for _t, w, _r in windows]
    win_names = []
    for n in names:
        if n not in win_names:
            win_names.append(n)
    win = {n: {"messages": 0, "usage": [0, 0, 0, 0], "cost": 0.0 if rates_file else None,
               "unpriced": 0, "agent_seconds": 0, "human_prompts": 0} for n in win_names}
    starts = {}
    for t, n, raw in windows:
        starts.setdefault(n, raw)
    for t, mdl, vals, side in msgs:
        w = win[window_for(t)]
        w["messages"] += 1
        for i in range(4):
            w["usage"][i] += vals[i]
        if rates_file:
            c = cost_of(mdl, vals)
            if c is None:
                w["unpriced"] += 1
            else:
                w["cost"] += c
    for t in humans:
        win[window_for(t)]["human_prompts"] += 1
    for n in win_names:
        win[n]["agent_seconds"] = round(agent_seconds(lambda t, n=n: window_for(t) == n))
        if win[n]["cost"] is not None:
            win[n]["cost"] = round(win[n]["cost"], 4)
        win[n]["start"] = starts.get(n)
    if not any(win[BEFORE][k] for k in ("messages", "human_prompts", "agent_seconds")):
        del win[BEFORE]
        win_names.remove(BEFORE)
    win = {"order": win_names, "windows": win}

# --- output -------------------------------------------------------------------------------
if mode == "json":
    out = {
        "available": True, "project": project, "transcript_root": root, "dirs": dirs,
        "files": n_files, "records": n_records, "messages": len(seen), "synthetic_skipped": n_synthetic,
        "keys": list(KEYS) + ["messages"],
        "by_model": {m: v for m, v in by_model.items()},
        "by_day": {d: {"stage": stage_for(d), "usage": v} for d, v in sorted(by_day.items())},
        "by_stage": {s: {"days": stage_days[s], "usage": v, "models": dict(stage_model[s])} for s, v in by_stage.items()},
        "headline": {"main": sidechain[0], "subagents": sidechain[1]},
        "current_stage": current, "caveat": caveat,
    }
    # opt-in keys only: without the flags the object is exactly what it was
    if cost is not None:
        out["cost"] = cost
    if effort is not None:
        out["effort"] = effort
    if win is not None:
        out["windows"] = win
    print(json.dumps(out, indent=1, sort_keys=True))
    sys.exit(0)

if not seen:
    if mode == "brief":
        print("Tokens this stage: NOT AVAILABLE (no Claude Code transcript records with cwd under %s in %d dir(s) — try --scan-all)" % (project, len(dirs)))
    else:
        print("NOT AVAILABLE — %d transcript dir(s) read under %s, no assistant records with cwd under %s (try --scan-all)" % (len(dirs), root, project))
    sys.exit(0)

if mode == "brief":
    if current is None:
        s, note = "UNMAPPED", "no Current stage line in PROJECT.md"
    elif current in by_stage:
        s, note = current, "stage " + current
    else:
        s, note = None, "no day attributed to stage " + current
    if s:
        v = by_stage[s]
        print("Tokens this stage: %s (%s · %s cache-read · %d days · %s)" % (
            k(headline(v)), split(stage_model[s]), k(v[2]), stage_days[s], note))
    else:
        print("Tokens this stage: 0 (%s; project total %s · %s cache-read)" % (note, k(headline(total)), k(total[2])))
    sys.exit(0)

print("token-burn — %s" % os.path.basename(project))
print("  %d transcript file(s) in %d dir(s) under %s · %d messages (from %d records; %d synthetic skipped)" % (
    n_files, len(dirs), root, len(seen), n_records, n_synthetic))
print("  headline = input + cache-write + output · cache-read shown apart · no currency (see header)")
print()
fmt = "%-22s %9s %11s %11s %9s %9s %8s"
print(fmt % ("MODEL", "INPUT", "CACHE-WRITE", "CACHE-READ", "OUTPUT", "HEADLINE", "MSGS"))
for m, v in sorted(by_model.items(), key=lambda kv: -headline(kv[1])):
    print(fmt % (short(m), k(v[0]), k(v[1]), k(v[2]), k(v[3]), k(headline(v)), v[4]))
print(fmt % ("TOTAL", k(total[0]), k(total[1]), k(total[2]), k(total[3]), k(headline(total)), total[4]))
if sidechain[0] + sidechain[1]:
    print("  subagents (Agent tool): %s of headline (%d%%)" % (
        k(sidechain[1]), round(100.0 * sidechain[1] / (sidechain[0] + sidechain[1]))))
print()
fmt2 = "%-12s %-9s %9s %11s %6s  %s"
print(fmt2 % ("DAY (UTC)", "STAGE", "HEADLINE", "CACHE-READ", "MSGS", "MODEL SPLIT"))
for d, v in sorted(by_day.items()):
    print(fmt2 % (d, stage_for(d), k(headline(v)), k(v[2]), v[4], split(day_model[d])))
print()
fmt3 = "%-9s %5s %9s %11s %6s  %s"
print(fmt3 % ("STAGE", "DAYS", "HEADLINE", "CACHE-READ", "MSGS", "MODEL SPLIT"))
def stage_sort(s):
    return (99, "") if s == "UNMAPPED" else (rank(s), s)
for s in sorted(by_stage, key=stage_sort):
    v = by_stage[s]
    print(fmt3 % (s, stage_days[s], k(headline(v)), k(v[2]), v[4], split(stage_model[s])))
print("  caveat: %s" % caveat)
if current:
    print("  register says current stage %s%s" % (current, "" if current in by_stage else " — no day attributed to it yet"))
if cost is not None:
    print()
    print("COST (%s per Mtok from %s)" % (currency, rates_file))
    fmtc = "%-22s %9s %11s %11s %9s %10s"
    print(fmtc % ("MODEL", "INPUT", "CACHE-WRITE", "CACHE-READ", "OUTPUT", "TOTAL"))
    for m in sorted(by_model, key=lambda m: -headline(by_model[m])):
        if m in cost["by_model"]:
            v = cost["by_model"][m]
            print(fmtc % (short(m), money(v[0]), money(v[1]), money(v[2]), money(v[3]), money(v[4])))
        else:
            print(fmtc % (short(m), "", "", "", "", "UNPRICED"))
    print(fmtc % ("TOTAL", "", "", "", "", money(cost["total"]) + ("" if cost["complete"] else "+")))
    if cost["main"] + cost["subagents"]:
        print("  subagents (Agent tool): %s %s of %s" % (money(cost["subagents"]), currency, money(cost["total"])))
    if not cost["complete"]:
        print("  INCOMPLETE — no rate line matches: %s (add a line or a `*` catch-all)" % ", ".join(cost["unpriced_models"]))
if effort is not None:
    print()
    print("agent working time: %s (main thread, gaps <= %g min, gaps ending at a human prompt excluded) · human prompts: %d" % (
        hm(effort["agent_seconds"]), gap_s / 60.0, effort["human_prompts"]))
if win is not None:
    print()
    print("WINDOWS (from %s; each runs until the next starts)" % windows_file)
    fmtw = "%-24s %-17s %6s %9s %11s %10s %10s %8s"
    print(fmtw % ("WINDOW", "FROM", "MSGS", "HEADLINE", "CACHE-READ", "COST", "AGENT-TIME", "PROMPTS"))
    for n in win["order"]:
        w = win["windows"][n]
        c = "-" if w["cost"] is None else money(w["cost"]) + ("+" if w["unpriced"] else "")
        print(fmtw % (n[:24], w["start"] or "", w["messages"], k(headline(w["usage"])), k(w["usage"][2]),
                      c, hm(w["agent_seconds"]), w["human_prompts"]))
    print("  agent time = main-thread gaps <= %g min not ending at a human prompt; a trailing + = some messages unpriced" % (gap_s / 60.0))
PYEOF
