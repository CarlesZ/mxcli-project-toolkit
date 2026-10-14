# Increment 8 — Dispatch & Workforce out of the FSM monolith, run from the skills (2026-10-13)

**Level reached: 1 (build-green).** The seam is live on every lane the slice uses, but **level 2 is not claimed**:
3 behaviour-carrying web stub rows remain. Strangle (Stage 5b) was not started. Slice: `Scheduler`,
`RosterManagement`, `Technician`, `Skill`, `TimeRegistration` (21 entities) into a `mxcli new` 11.13.0 web app
`DispatchApp`, integrated with a **fresh** 10.24 copy of the FSM 9.24.2 monolith. Playbook: `skills/decompose-app.md`,
`skills/mendix-service-seam.md`, `skills/security-is-not-a-later-script.md`, `skills/learned-constants-and-secrets.md`.
Files, commands, captures: `CAPTURE.txt`. Credit: a public Marketplace template (FSM). Written from the worker's handback (c97df34).

| Measure | Build-green (04:34) | End (05:55) |
|---|---|---|
| Out-edge **stub** rows, web | **271** | **3** |
| Out-edge stub rows, Mobile | 0 (+1 second-order, extra row) | 1 |
| Out-edge hand-off rows, web / Mobile | 5 / 33 | 27 / 33 |
| Out-edge resolved rows | 115 | 365 |
| In-edge hand-off rows, web / Mobile (not strangled) | 347 / 70 | 347 / 70 |
| Slice `mx check` | 0 | 0 (Production security) |
| Monolith `mx check` | 0 | 0 |
| Journeys | — | read + write + auth, 2 consecutive runs, exit 0 |

## Gates (verbatim)

- **Stage 0:** `mx convert` (56 s): `The project contains 6 errors, 241 warnings and 9 deprecations.`; after the increment 4 fixes `The app contains: 0 errors.` (`captures/03`).
- **Stage 1:** 8-partition cut `verdict blocked`; two-app view OUT 281 (none 74, OData 184, copy 16, deep-link 6, write 1), IN 340 (`captures/04`).
- **Stage 1b (unattended, user opt-in):** `target-architecture.md`, 8 sections, **42/42 own modules assigned**, 8 CONFIRMED and 13 ASSUMED register lines.
- **Stage 2:** pre-check found 11 access-rule XPaths across the cut (out: `RosterManagement.Roster` ViewMy walks Roster → asset → ticket → assignment → technician → account; in: rules on Note, Part, Inventory, Warehouse).
- **Stage 3:** `The app contains: 1301 errors.` (all CE1613) → … → `The app contains: 0 errors.` (`captures/20`); `BUILD SUCCEEDED` (`captures/23`).
- **Stage 4 build-green** (`captures/22`), exit 0: `cut-ledger: 1081 crossing refs -> 875 ledger rows … by resolution: handoff 452, platform 6, resolved 115, retire 31, stub 271`.
- **Stage 4 end** (`captures/58`), exit 0: `by resolution: handoff 477, platform 6, resolved 365, retire 31, stub 4`.
- **Fidelity** 10.24 vs 11.13: 338 identical, 4 drift, 22 not-expressible (converted legacy widgets) (`captures/24`).

## Remaining stubs (why level 2 is not claimed)

- `TicketManagement.Appointment_Validate_ManualPlanning` — its monolith body calls 2 validators which call 2 more; third-order copy not done.
- `DeepLink.DeepLinkHome` — DeepLink module not in the slice.
- `Visualizations.User_Refresh` — monolith dashboard refresh; a REST action would carry it.
- Mobile: second-order `NativeMobile.NativeAppointment`.

## Lane per crossing entity

| Entity (owner) | Lane in the slice | Key |
|---|---|---|
| WorkOrder, Appointment, Ticket, Priority, WorkOrderAssignment, AppointmentAssignment (monolith) | OData read, same-name external entities in `TicketManagement` (recipe A), `odata/dispatchcore/v1` | PublicID AutoNumber |
| Technician, TechnicianGroup, Skill as seen by monolith associations | OData read of mirrors `MonoTechnician`, `MonoTechnicianGroup`, `MonoSkill`; join by key (recipe B) | SystemID / Name / SkillName |
| FeatureToggle, ApplicationSettings, Warehouse, Asset (monolith) | OData read, same-name external entities in their own modules | PublicID |
| Appointment planning (`Appointment_PlanManual`) | REST `POST rest/dispatchcore/v1/appointments/plan` | PublicID + technician SystemID |
| Plan a work order into a timeslot | REST `POST …/workorders/plan-for-technician` | PublicID |
| Remove a technician from work orders | REST `POST …/workorders/remove-technician`, one call per work order | PublicID |
| Technician, Skill, Roster, TimeRegistration, WorkBreak, RegistrationCode, PlannerContext (slice) | local owner (moved) | — |
| Ticket_Asset (monolith association) | hand-off (Asset would arrive as `TicketManagement.Asset`, P6) | — |
| Create-draft appointment, 5 monolith pages, 1 snippet | hand-off: deep link (a consumer cannot create an external object) | — |
| Mobile partition (146 refs) | hand-off (CONFIRMED out of scope) | — |

The rebind wrote hand-off brackets that drop a filter rather than translate it: 24 technician-group filters on planner
queries became `[true()]` (read-only lists); 12 reverse-navigation traversals became `[false()]`. Each is listed in the
generated MDL headers (`mdl/slice-seam-rebind*.mdl`, `captures/49`).

## Security

- **Slice:** `alter app security ( SecurityLevel: PRODUCTION )`; the 6 FSM user roles get the slice module roles they hold in the monolith, plus `TicketManagement.CoreRead`, `DispatchSeam.User` and one `StubRead` role per remaining stub module (without them 108 × CE2729).
- **Monolith:** one machine user role `DispatchCoreClient` holds the only grants on both services (P2). Measured (`captures/27`):
  ```
  GET odata/dispatchcore/v1/WorkOrder (machine role)      HTTP 200
  GET odata/dispatchcore/v1/WorkOrder (no credentials)    HTTP 401
  GET odata/dispatchcore/v1/WorkOrder (wrong password)    HTTP 401
  GET odata/dispatchcore/v1/WorkOrder (human role SDE)    HTTP 404
  POST rest/dispatchcore/v1/appointments/plan (machine)   HTTP (200, b'absent 0')
  POST rest/dispatchcore/v1/appointments/plan (no creds)  HTTP 401
  POST rest/dispatchcore/v1/appointments/plan (human SDE) HTTP 404
  ```
- **Secrets (P11):** one generated password with a symbol in each app's machine-local `.mxcli/constants.json` (mode 600, not committed, never printed); model defaults `__SET_ME__`, guarded in `EnsureAccount`. Token auth is the CONFIRMED later target. `constants-audit.sh` not run.
- **Availability coupling (P4), probed:** with the monolith stopped the slice page shows `Error / An error occurred, please contact your system administrator.`; runtime logs `ERROR - Client: Internal server error` (`captures/61`).

## Journeys (verbatim, `journey/run-output.txt`)

```
=== final state run 1 (all data stubs external; fresh starts of both apps)
  PASS  [read: monolith appointment listed in the slice over OData (ledger: TicketManagement.Appointment out-rows)] row J8-APPT-1 visible in the slice grid, and present in the MONOLITH database
  PASS  [write: plan in monolith over REST (ledger: TicketManagement.Appointment_PlanManual out-row)] PlanRequest J8-… in the SLICE database with the monolith's answer
  PASS  [write: plan in monolith over REST (…)] the MONOLITH database holds the same planned start, status Planned (behaviour ran)
  PASS  [auth: machine role only on both monolith services] OData 200 machine / 401 none; REST 401 none — 200/401/401
exit=0
=== final state run 2 …   (4 × PASS)   exit=0
```

Run-unique IDs and planned starts; both databases checked with `mxcli oql`. `journey/run-output-failed-after-probe.txt`
keeps two FAILs on purpose: a side-effecting REST probe (`remove-technician` → `WorkOrderList_ResetAll`) deleted the seeded
appointment, which the seed only recreated together with its ticket; the seed now ensures each row on its own. Not covered:
the planner board UI (drag/drop); plan-for-technician and remove-technician were proven by REST probes with
monolith-database checks (`captures/54`).

## Stage timing (build work 04:00:38 → 05:55, then write-up)

| Stage | Window | min |
|---|---|---|
| 0 preconditions + `mx convert` + one-time fixes (incl. reading the 4 skills) | 04:00–04:06 | 6 |
| 1 read and score | 04:06–04:07 | <1 |
| 1b target architecture | 04:07–04:09 | 3 |
| 2 sequence + XPath pre-check | 04:09 | <1 |
| 3+4 MPK move, stubs, Java, widgets, ledger → build-green | 04:09–04:34 | 24 |
| 5 monolith publishes first (OData, REST, keys, roles, accounts, endpoint matrix) | 04:34–04:45 | 11 |
| 5 recipe A, first attempt (stopped at 45 errors) | 04:45–04:56 | 11 |
| 5 lane beside the stubs + journeys (consistent fallback) | 04:56–05:09 | 13 |
| 5 recipe A to 0 errors, stub replacement, journeys, outage probe (= Stage 6) | 05:10–05:55 | 45 |
| 5b strangle | not run | — |
| 7 learnings, ledger, write-up | 05:56–≈06:40 | ≈45 |
| **Total** | | **≈ 2 h 40** |

Increments 5 + 6 + 7 for Assets & Parts took ≈ 4 h 50 including authoring. This run reached the equivalent of
increments 5 + 6 in **≈ 1 h 55 of build work** (build-green plus a working core seam; stubs 271 → 3 vs Assets 120 → 32)
on a slice with ~1.8× the no-lane calls. Most of the saving came from reusing the tools the skills point at and the
written seam patterns.

## Skill log

1. **Stage 0.3** gives no commands for the 10.24 conversion; fell back to `seam-probe/FINDINGS.md` and `slice-assets/captures/03, 20–23`. A hand-written grid2 patch matched the `]` inside `'[%CurrentObject%]'` and left CE0161. Fix: put the 7-step recipe with commands in Stage 0; ship the grid2 byte patch as a script.
2. **Stage 3 bound** ("target `mx check` errors are crossing edges only"): install left 1301 CE1613 and no step says how to reach 0; fell back to `slice-assets/tools/gen-stubs.py`. Fix: "Generate CUT STUBS from the CE1613 list (`gen-stubs.py`); it does not cover rules, snippets, Java actions, user roles — copy those."
3. **Stage 3.4:** `gen-widgets.py` hard-codes Assets signatures; rewritten as `tools/react-widgets.py` (signatures from describe, DropDown and ReferenceSetSelector, Selection Multi for list buttons). Widgets inside a legacy `Forms$Table` are invisible to `replace`; replace the whole table.
4. **Stage 3.5:** 10.24 → 11.13 also needs Java edits (`BUILD FAILED`): `context()` → `getContext()`, removed `Core.isSubClassOf(String,String)`, proxy-typed `item.getId()`. Fix: "Mendix 9 **and 10** API calls", list these.
5. **Stage 1.4 blind spots:** expression references (pluggable-widget and `create variable` expressions) are not in the catalog; the publish list missed `Appointment.AppointmentID` and `WorkOrder.MinutesPlanned` (CE0117 after the swap). Fix: "grep describe output for `$…/Attr` of the entities you publish".
6. **Stage 5:** recipe A worked by name for 9 entities, but reaching 0 took a scripted rebind (R1–R13), BSON page edits and 4 publisher changes. Fix: on a chatty slice expect a rebind pass per flow; keep a consistent fallback first (a seam lane in its own consumer module beside the stubs).
7. **service-seam XPath limits missing:** XPath on an attribute not published Filterable → `CE0161 "Error(s) in XPath constraint."` (30 probe flows, `captures/45`); OData publishes a navigation on its owner only — reverse traversal → CE0161, a gallery over one → `CE8812`; sorting needs Sortable → `CE7247 "Cannot sort on attribute 'PlannedWorkStart' because it does not support sorting."`. Fix: add all three; publish exposed attributes Filterable and Sortable.
8. **P8** cost is wider: enum-attribute visibility rules → `CE0749`; `getCaption($x/Status)` and enum literals → CE0117. List the three rewrites.
9. **P4** inside a loop is refused: `CE0644 "Error handling type must be 'Rollback' inside a looped activity."` Fix: move the call into a per-item sub-microflow.
10. **P12** must be general: after **any** publisher change, `create external entities` answers `0 created, 0 updated, 9 skipped`; refresh = drop + create the consumed service.
11. **Stage 5b.7** root cause: a **rule-based** decision describes as `if not(Rule(...)) then`; re-created it is an expression split, which cannot call a rule. Fix used: inline the role test (`retrieve … System.UserRole where [id = '[%UserRole_ServiceDeskEmployee%]'][System.UserRoles = $currentUser]`, condition `= empty`).
12. **Stage 4/journeys:** `mx check` text output has no document names; `mx check -j <file>` has `locations[].document-name`. Add `-j` everywhere.
13. **Stage 6 idempotency:** seed data must ensure each row on its own; run no probe that deletes seed rows between runs.
14. **Stage 1b:** no gap; the eight sections drove the run (architecture-blueprint steps not read, time).
15. **P2/P11, security skill:** followed as written; 200/401/404 first try; stub module roles correct (CE2729 × 108 → 0).

Fallbacks used: `seam-probe` FINDINGS; `slice-assets` captures 03/20–23 and tools `gen-stubs`, `legacy-extract`,
`gen-widgets`, `edges-A-layout`; `slice-assets-core` `mono-core-publish.mdl`, `mono-core-actions.mdl` (skill points
there); `slice-assets-strangled` `bson-rename.py` and `strangled.journey.js` (skill points there).

## Three-app relocation (paper only; full version in `target-architecture.md` §9)

- **Publishes after the move:** DispatchApp publishes Technician, TechnicianGroup, Roster, TechnicianRoster at `odata/workforce/v1` with its own machine role, and roster REST actions at `rest/workforce/v1/rosters` (delete via `Roster_Delete`, P7).
- **Re-points:** AssetsApp adds a second consumed service in its own consumer module (P6) and a second secret; the monolith keeps serving `odata/core/v1` until AssetsApp re-pointed, then publishes `v2` without those entities (P10).
- **Ledgers:** AssetsApp's `resolved:odata` rows for Technician and Roster keep their resolution, new evidence; during the overlap each entity is a dual-owner hand-off (P13); in the monolith's increment 7 ledger the roster `resolved:rest` rows become `resolved:rewired`; a cross-app consumer appears in no catalog, so it needs an `--extra` row.
- **Exposed interaction:** the slice's recipe-B mirrors live in modules that leave the monolith at strangle, so strangling Dispatch would break DispatchCore v1 for the slice itself. The monolith's associations must first point at the slice's published Workforce entities.

## mxcli defects (v0.26.0; new ones in `contrib/inbox/2026-10-13-increment-8-dispatch-findings.md`)

1. describe page → create refuses its own output: `ContentParams: ({1} = $currentObject/FilterCaption)` → `dynamictext "text7": ContentParams parameter {1} is written as "$currentObject/FilterCaption" — a template parameter is evaluated against the widget's own context object`.
2. describe page → create resolves a nested visibility rule against the wrong entity: `Visible: Status in (…): Scheduler.PlannerContext_WorkOrder_Selected has no attribute Status`; exec not atomic.
3. exec pre-check does not see what an earlier statement created: `the constraint names "PublicID", which is neither an attribute nor an association of it`; `entity not found: DispatchSeam.Appointment`; needs `--no-check` (variant of mendixlabs/mxcli#1061).
4. A rule-based decision describes as `if not(Rule(...)) then`; drop + create → `[CE0117] "Error(s) in expression." at Decision 'User is SDE?'` (root cause of increment 7 inbox #6).
5. `alter microflow … { insert before return true … }` is not idempotent (three runs, three identical calls in `General.ASU_General`).

Confirmed again: BUG-87 (`entity <>` in describe java action); bare `TypeParameter` → `CE1613 "The selected entity '.TypeParameter' no longer exists."`; `format (decimalPrecision: -1)` not re-parsable; `replace` cannot find widgets in a legacy container; consumed-service metadata not refreshable; exec not atomic; some `create or modify microflow` splices refused (drop first).

Platform/Mendix: CE0644 in loops; Filterable/Sortable/reverse-navigation limits; `mx check -j`; Mendix 11 Java API edits; an FSM after-startup flow kills boot when the oldest appointment has no `PlannedWorkStart` (`Failed to evaluate expression … $Appointment_Oldest/PlannedWorkStart < [%CurrentDateTime%]`); `Appointment_PlanManual` needs an AppointmentAssignment (HTTP 500 `Change object 'Some(AppointmentAssignment)' should not be null`).

## Still unmeasured

- Strangle (5b): 347 web and 70 Mobile in-edge hand-off rows untouched.
- The planner board UI (drag/drop → REST); only the REST actions were probed.
- The effect in use of the 24 `[true()]` and 12 `[false()]` hand-off brackets.
- Data migration (CONFIRMED out of scope); the dual-owner technician row the journey uses (P13).
- `constants-audit.sh`, TLS, token auth; outage behaviour of the REST writes (only the OData page was probed).
- Trial-licence 402 did not occur (runtimes restarted between batches); the run allowance was not measured.
