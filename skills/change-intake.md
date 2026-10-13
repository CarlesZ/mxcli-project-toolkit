# Change Intake — Log Feedback Before You Build It

**Applies to:** any project with `PROJECT.md`, Stage 2 onward.
**Purpose:** log a mid-project change before any edit, then edit the highest artifact it alters; MDL last. Why, example, apply/prove, gate check: `change-intake-detail.md`.

**Trigger:** the user, or a relayed stakeholder, asks for anything to differ from artifacts or build. Not a gate answer or review finding.

## Row first, in `PROJECT.md` `## Change log`

Columns: CR-NN (never reused), Date, Source, Verbatim ask (`\|` for a pipe), Class, Size, Entry artifact, Status, Closed-by. One ask, one row. Status: open → refined → agreed → applied → proven, or `rejected — reason` (kept).

## Class → entry artifact (never the MDL)

- **requirement** → BRD.
- **decision** → new `CONFIRMED` row `supersedes D-NN`; old row's Status `SUPERSEDED by CR-NN`, text untouched.
- **structure** → `architecture/` or module brief.
- **visual** → wireframe while unbuilt; once built, before/after pair in `design/ui-reviews/`.
- **impl**, **bug** → regression journey (a bug's fails first).

## Size → ask (ask, then stop)

- **S** (one artifact per layer, one module, contradicts nothing `CONFIRMED`), user-typed: no question; receipt `Logged CR-07: visual, S → wireframe`, `agreed`, lead edits.
- **M** (several artifacts or modules): restate (`refined`); one batched question at the module gate, one ba-agent pass.
- **L** (new feature or module, or contradicts `CONFIRMED`): ask now (two options, a recommendation); re-enter the owning stage.
- **Relayed**: `open` until the next gate asks. **Ambiguous**: one "A or B?".

## Owners

Lead: all CR/decision rows, S edits; helpers never write `PROJECT.md`. ba-agent: BRDs, briefs. architect-agent: wireframes, `design/`, `architecture/`.

## Done when

- N asks → N rows.
- Every CR script ran via `./bin/exec.sh --cr CR-NN`.
- At a module gate, `Change log:` reads `PASS`, or each listed row is named with a reason.
- Zero "no Closed-by evidence" rows.
- Decisions superseded, not edited.
