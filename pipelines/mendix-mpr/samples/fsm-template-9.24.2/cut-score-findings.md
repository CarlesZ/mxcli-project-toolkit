# FSM template 9.24.2 — first `bin/cut-score.sh` run on a real monolith (2026-10-12)

Increment 2 of the Decompose track (`process/decompose-and-rehost-plan-2026-10-12.md` §5).
Inputs beside this file: `dependencies.json` (verbatim `project-bin/app-facts.sh --skip-loops`,
42 own modules, 312 own edges, 4508 refs, 16 ref kinds) and `app-layer-map.json` (verbatim
`bin/app-layer-map.sh`: 14 levels, 73 backward edges, one 36-module tangle). MPR v1 read path:
no v1-specific failure. Timings: app-facts 25 s (graph-report 14 s), layer map 1 s, each
cut-score run ≤ 1 s.

Re-run any cut with `bin/cut-score.sh --facts <this dir> --layer-map app-layer-map.json --cut "…"`.

## Cuts scored (all verdicts `blocked`)

| Cut | Partitions | Crossing edges / refs | Bidir pairs | Blocker rows |
|---|---|---|---|---|
| default, one app per layer level | 14 | 312 / 4508 | 33 | 894 — meaningless on a 36-module tangle |
| web \| mobile, Synchronization web-side | 29 \| 13 | 103 / 1388 | 1 | 84 |
| web \| mobile, Synchronization mobile-side | 28 \| 14 | 109 / 1316 | 1 | 88 |
| web \| mobile \| Synchronization alone | 3 | 126 / 2022 | 3 | 210 |
| + test modules as a third partition | 3 | 126 / 1520 | 2 | 180 |
| **+ Utils copied to mobile (best found)** | 25 \| 14 \| 3 | **132 / 1442** | 2 | 162 |
| four apps (AssetManagement + 4 split out) | 4 | 169 / 2027 | 4 | worse on every count |

Reading: `Synchronization` belongs mobile-side (`Synchronization.Synchronize` is a nanoflow
calling NativeMobile nanoflows). `NativeModelCheck`, `LoadTest`, `TEST_NativeLocalLogin` are
test tooling with 1 inbound edge: retire, do not cut. `Utils` is pulled by mobile (131 inbound
refs) more than by web (22): copy it. `FSM_Specific` is the opposite (96 layout refs in from
web): keep it web-side, move only `Snippet_TimerHelper`. Best landscape found:
**Planner/Web (25 modules) | Mobile + Synchronization + Utils (14) | retire (3)**.

## What the classifier got wrong on real data (spot-checked 6 edges with `describe`)

All 6 blocker rows are real references. The **classification** is wrong in 2 of 6:

1. **`call` conflates five things.** Catalog: microflow→microflow 732, nanoflow→nanoflow 302,
   microflow→rule 50, nanoflow→JavaScript action 49, microflow→Java action 10. A nanoflow or JS
   action runs client-side and cannot become a published OData action; its lane is *copy*. On
   the main seam 142 of 491 crossing calls are client-side, so ~30 % of the blocker mass is
   mis-laned. Example: NativeMobile → `Utils.JS_GetCurrentValue`, 66 calls.
2. **Eight catalog ref kinds never reach `dependencies.json`** (`sync` 51, `widget` 57,
   `schedule` 9, `event` 6, `publish` 6, `validate`, `login_page`, `settings`). `sync` is the
   dangerous one: the `NativePhone` profile syncs 19 Synchronization entities, 27 Native*
   entities, plus `Administration.Account` and `AppSettings.ApplicationSettings` to the device.
   A Mendix 9 offline profile cannot sync an external entity, so a synced entity that lands in
   the other app is a hard blocker the score cannot see today.
3. The aggregate detector fires on nanoflows aggregating the device store
   (`NativeMobile.DS_GetObjectCounts`, 51 retrieve + 51 count): a false positive class.

True blocker confirmed: `TimeRegistration.RegistrationCodeList_Delete` pushes server-side
into NativeMobileTimeRegistration microflows — needs an OData action.

## Changes this run caused

- `project-bin/app-facts.sh` no longer requires the `sqlite3` CLI.
- `bin/cut-score.sh` caps the per-partition blocker cell and stdout line (one cell was 10 KB).

## Proposed next changes (not built)

1. Sub-type `call` by target kind in app-facts (`call:mf`, `call:nf`, `call:js`, `call:java`,
   `call:rule`); client-side kinds lane *copy*.
2. Carry `sync`, `widget`, `schedule`, `event`, `publish` into `dependencies.json`; a `sync` ref
   to a foreign entity is a blocker.
3. `--copy M1,M2` and `--retire M1,…` flags; named partitions (`Planner=A,B|Mobile=C`).
4. Default per-level cut refuses or warns loudly on a large tangle.
5. Aggregate detection skips nanoflow sources; sort rows by weight.

## Recommended first slice

Retire the three test modules, copy `Utils`, then move **`NativeNote`** (3 entities, 16
microflows, 35 nanoflows, 2 pages; 12 web refs vs 44 native + 65 sync) with its
`Synchronization_Note` flows. Rewiring: the Note→NativeNote server-side push (OData action) and
one MasterData admin page. Runner-up: `NativeTechnician`.
