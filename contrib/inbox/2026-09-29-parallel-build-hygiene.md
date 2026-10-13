# Parallel build: mxbuild collisions, a per-script gate that grows with the model, undercounted output

**From:** a field comparison (mxcli + toolkit build vs a Studio Pro MCP build, same frozen spec)
**Date:** 2026-09-29
**Kind:** process
**Field evidence:** toolkit build BUILD-LOG.md and METRICS.md: 11 of 96 script applies failed (11.5%); 2 were "gate could not run: mxbuild exit 1" from concurrent builds (rows 16, fix-39; row 119 was a glyph error, not a collision); per-script apply grew from 22–30 s (slice 1) to 55–65 s (slice 2) as the mxbuild gate grew.
**Proposed target:** `bin/exec.sh` (or its project-bin wrapper), `skills/iterative-build-loop.md`

---

Parallel drafting is the toolkit build's speed advantage (2.6 vs 5.5 min/row; equal calls per
row), so keep it and remove its friction:
- Lock/queue mxbuild — half done: the per-project exec lock in `project-bin/exec.sh` (#304)
  refuses a second apply at once (no collision), but does not queue it; the agent re-runs.
- ~~Usage measurement~~ — promoted 2026-10-14 to `skills/measured-claims.md` §7 (re-measured:
  sub-agent transcripts carry partial output_tokens on early records, up to 7x low).
- **Still open — batch the gate**: one mxbuild per 3–5 consecutive clean scripts; per-script
  only after a failure. [hypothesis: 10–20 min wall time saved in slice 2]. Needs an `exec.sh`
  mode (it has none today; `skills/iterative-build-loop.md` → "Gate cost as the model grows"
  says not to imitate one with overrides).
