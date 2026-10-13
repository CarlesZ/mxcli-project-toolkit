# Acceptance testing: what made the toolkit build's tests stronger

**From:** a field comparison (mxcli + toolkit build vs a Studio Pro MCP build, same frozen spec)
**Date:** 2026-09-29
**Kind:** learning
**Field evidence:** both builds ran the same acceptance rows, seed data and DONE bullets. Toolkit build: 149 microflow unit tests (428 @expect) + 33 Playwright scripts with OQL DB checks, all committed; 20/20 scenario bullets (stitched from 3 runs); final E2E 62 pass / 0 fail / 7 not run. MCP build: 0 committed unit tests or scripts; 11/20 in its official run; timers skipped.
**Proposed target:** `skills/testing-shape.md`, `skills/test-result-audit.md`

---

Keep (measured to matter):
- Tests and results committed per run, with a pass/fail trend (38/18 → 62/0).
- **Timer compression** (1-minute days) made timer scenarios testable — that run found an
  escalation bug (uncommitted change) the other build never exercised.
- Fresh data per variant, not reuse of rehearsal data.

The three gaps this comparison found (server-side permission probe, unexpected 4xx as a failure,
one clean-database final run) were promoted on 2026-10-13 into `skills/testing-shape.md` §4/§7 and
`skills/test-result-audit.md` 2e (#172). The "Keep" items above are not yet promoted.
