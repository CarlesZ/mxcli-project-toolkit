# token-burn fixture — capture notes

**Captured, not hand-written.** `transcripts/s-1.jsonl` and
`transcripts/s-1/subagents/agent-1.jsonl` are records taken verbatim in *shape* from a real
Claude Code transcript (captured 2026-09-18: a toolkit-maintenance session of ~17,000 lines,
plus one of its Agent-tool subagent transcripts), then scrubbed. Every structural fact
`bin/token-burn.sh` depends on is present because the real harness wrote it that way — none of
it was imagined:

- one `assistant` record **per streamed content block**, all carrying the same `message.id`
  (the ~2× overcount if summed per record) — but NOT always the same `usage`: in the subagent
  transcript `msg` ids with a later record carry a larger `output_tokens` on that last record
  (60 on the first records of the 2026-09-17 messages, 1559 summed over last records). The
  instrument takes each id's LAST record; the numbers below were recomputed that way;
- `message.model` = `<synthetic>` on a harness-generated record (exactly one kept);
- `cwd` is **per record**: a session launched in `~` spends records in `~`, `~/proj` and
  `~/proj/app`;
- subagent files carry `isSidechain: true` and `agentId`, and sit under
  `<session>/subagents/`;
- `usage` has the four integer counters plus `cache_creation{…}` and
  `output_tokens_details` — and `output_tokens_details` is **`null` on some real records**
  (the scrubber crashed on it first; the instrument reads only the four integers, so it is
  unaffected, but any reader that walks `usage` deeper must guard for it).

## Selection

From the session: 5 days (2026-08-31, 09-01, 09-08, 09-15, 09-18), the first 6 distinct
assistant `message.id`s per day **with all their duplicate records kept**, at most 2
`user`/`queue-operation`/`system` records per day, and one `<synthetic>` record. From the
subagent transcript: the first 25 assistant records and their user turns (one day, 2026-09-17).
All records of the first in-project message id (`msg_14`) were rewritten to
`cwd: /srv/example/proj/app` to stand in for the two-tree (`.mpr` under `app/`) layout.

## Scrubbing

| Field | Replacement |
|---|---|
| `uuid` / `parentUuid` | `u-<n>` (one consistent map) |
| `message.id` | `msg_<n>` (one consistent map — duplicates stay duplicates) |
| `sessionId` | `s-1`; `agentId` → `agent-1` |
| `cwd` | home → `/srv/example`; the toolkit clone → `/srv/example/proj`; anything else → `/srv/example/other` |
| `message.content` | the string `"[scrubbed]"` |
| dropped | `gitBranch`, `slug`, `requestId`, and every other key not listed under "kept" |

Kept: `type`, `sessionId`, `uuid`, `parentUuid`, `isSidechain`, `timestamp`, `version`, `cwd`,
(`agentId`), and `message{model, id, type, role, content, stop_reason, usage{input_tokens,
cache_creation_input_tokens, cache_read_input_tokens, output_tokens, cache_creation,
output_tokens_details}}`. No real path, id, name or content survives; the fixture is safe to
publish.

## Expected numbers (computed independently of the instrument)

One Python one-liner over both files: unique `message.id` (usage from its LAST record),
`type == assistant`, model not `<synthetic>`, `cwd` at or under `/srv/example/proj`. Columns are
input · cache-write · cache-read · output · messages; headline = input + cache-write + output.

| | input | cache-write | cache-read | output | msgs | headline |
|---|---|---|---|---|---|---|
| claude-fable-5-1 | 288 | 31365 | 2607781 | 15524 | 9 | 47177 |
| the subagent model (subagent) | 26 | 59772 | 998476 | 1559 | 13 | 61357 |
| **total** | 314 | 91137 | 3606257 | 17083 | 22 | 108534 |

(Taking the FIRST record per id, as the instrument did until 2026-10-13, gives subagent output
60 and headline 59858 — a 26× undercount of that model's output on this sample.)

Records: 52 in-project assistant records collapse to 22 messages; 76 records at
`/srv/example` are excluded; 6 records of `msg_14` are at `/srv/example/proj/app` and count.

Per day (headline): 2026-09-08 → 38527 (5 msgs) · 2026-09-17 → 61357 (13) · 2026-09-18 → 8650 (4).
With `PROJECT.md` beside: stage 1 = 2026-09-08 = 38527 (`39k`); stage 2 = 09-17 + 09-18 =
70007 (`70k`, subagent model 88% · fable-5-1 12%, cache-read 1438109 → `1438k`); current stage 2.

## `effort/s-3.jsonl` — hand-built, and why (#296)

**This file is NOT a capture.** The captured `s-1.jsonl` carries no main-thread human prompt
(its `user` records were not selected), so the human-prompt classifier has nothing captured to
run on. A fresh capture was taken from a real session and refused at commit time — a real
session's transcript, even scrubbed, is not something to publish from a shared machine. So
`s-3.jsonl` is built by hand, with every key and value shape taken from a profile of a real
harness transcript (harness 2.1.29x, 2026-10): only keys and value kinds were read, never text.
The facts it encodes, each seen in that profile:

- human prompts are `type: user` with `origin: {"kind": "human"}` and `promptSource: "sdk"`;
  some carry `promptId`/`userType`, some (written by a remote client) do not; content is a
  string or a list holding `text` blocks;
- task notifications and peer messages are ALSO `type: user`, distinguished only by
  `origin.kind` (`task-notification`, `peer`) — peer ones also `isMeta: true`;
- tool results are `type: user` with a `tool_result` block and a top-level `toolUseResult`;
- `isMeta: true` and `isCompactSummary: true` records are `type: user` too;
- records with no `origin` exist (older harness versions, and harness-injected command
  wrappers whose text starts with `<`);
- a human prompt record can be written twice with the same `uuid`.

Plus one record whose `cwd` is outside the project, one `isSidechain: true` record, and a
second `msg_e1` record at the same timestamp with all-zero usage (the instrument takes each
counter's max per message id, so a late empty record cannot erase real numbers; day
2026-09-20 totals stay 121 · 1500 · 30000 · 286 over 6 messages).
Field proof is a run, not this file: on the real transcript profiled above the instrument
counted the same number of human prompts (89) as an independent count of `origin.kind ==
"human"`, non-meta, non-compact records.

Expected (independent Python over the files, not the instrument): main-thread agent time
with the 5-minute cut-off = 220.465 s (captured `s-1.jsonl`; 164.6 s before
2026-09-18T02:00, 55.8 s after) + 371 s (`s-3.jsonl`) = **591 s**; with a 1-minute cut-off
the 114 s gap drops out of `s-3` → **477 s**. Human prompts: **4** (`h-1`, `h-2`, `h-3` once,
`h-4` with no `origin`). Windows `2026-09-01 setup` / `2026-09-17 round 1` /
`2026-09-18T02:00 wrap-up`: setup 5 msgs 38527 headline; round 1 13 msgs 61357; wrap-up 4
captured + 6 `s-3` msgs = 10, 10557 headline, 427 s, 4 prompts. Rates
`claude-fable-* 2/2.5/0.2/10` + `* 1/1/0.1/5` per Mtok on the captured pair: 0.7557847 +
0.1674406 = 0.9232253.
