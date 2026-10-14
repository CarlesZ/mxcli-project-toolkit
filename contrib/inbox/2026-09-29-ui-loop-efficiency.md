# UI rounds cost 5.6x the MCP build for the same time — per-script validation in drafters, then re-apply

**From:** a field comparison (mxcli + toolkit build vs a Studio Pro MCP build, same frozen spec)
**Date:** 2026-09-29
**Kind:** process
**Field evidence:** both TIME-LOG.md files: UI 177 min / 1,507 calls (toolkit) vs 181 min / 515 calls (MCP); round 1 alone = 64% of the toolkit build's UI calls; ~20% of UI tokens went to round 2 repairing round-1 regressions. Result: toolkit build clearly closer to wireframes (own re-review 1 → 15 of 43 pages MATCH).
**Proposed target:** `skills/ui-loop.md`, `skills/learned-css-that-never-applied.md`, `project-bin/check-page-shell.sh`

---

Why it was expensive: 7 drafting agents each copied the app and ran check → exec → mx check →
page-fidelity for every script; the lead then applied each script again (~25 calls per applied
fix). Screenshots were not shown to be the cost driver.

Regressions round 1 introduced (N1–N4 are lintable):
N1 `page-column` class landing on the layout root (shell detached); N2 Atlas `.d-none` loses to
`.pill`; N3 Data Grid 2 autoFit starving columns to 32 px; N4 dashed focus ring on the rail.

Promoted 2026-10-14: the round order (SCSS first, apply directly, re-look only changed pages)
and the N1–N4 pre-apply checks are in `skills/learned-page-patterns.md` → "UI fix rounds";
N4's fix was already in `learned-css-that-never-applied.md`.

Still open (not promoted):
- N1–N3 as a mechanical pre-apply check in `project-bin/check-page-shell.sh` (today a prose
  checklist only); needs captured page MDL / SCSS showing each regression as golden input.
- Bundle cap for UI drafters (see 2026-09-29-subagent-context-cost.md).
