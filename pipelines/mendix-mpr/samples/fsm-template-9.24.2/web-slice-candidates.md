# FSM template 9.24.2 — web-only slice candidates (2026-10-12)

Follow-up to `cut-score-findings.md`. Native/mobile modules are out of scope for the candidate
table; they appear only as the "other side" of a crossing. Read-only on the model (`show`/`describe`).

## 1. Web module set (26 own modules)

Own modules (42) minus `Native*` (12), `Synchronization`, `Utils` (copy to mobile), `LoadTest`,
`TEST_NativeLocalLogin`. Marketplace modules and System/Atlas excluded by the facts rule.

AppSettings, AssetManagement, CustomerManagement, Dashboard, FSMPublishedAPI, FSM_Specific,
FeatureToggle, Form, General, IDCreation, MasterData, ModuleIntegration_Administration_Impl,
ModuleIntegration_DeepLink_Impl, ModuleIntegration_Logging_Impl, Note, Part, Reason,
RosterManagement, Scheduler, Skill, Technician, TicketManagement, TimeRegistration, Tool,
Visualizations, WarehouseManagement.

## 2. Role x web-module matrix

8 user roles. Cell = number of module roles of that module the user role holds (`-` = none).
Columns: Anon = Anonymous, CCE = CallCenterEmployee, API = FSMAPIConsumer, FnAdm = FunctionalAdministrator,
Mech = Mechanic, SDE = ServiceDeskEmployee, SRM = ServiceRegionManager, TechAdm = TechnicalAdministrator.

| Module | Anon | CCE | API | FnAdm | Mech | SDE | SRM | TechAdm |
|---|---|---|---|---|---|---|---|---|
| AppSettings | - | - | - | - | 1 | - | - | 1 |
| AssetManagement | - | 2 | - | 3 | 2 | 3 | 2 | 2 |
| CustomerManagement | - | 1 | - | 1 | 1 | 1 | 1 | 2 |
| Dashboard | - | 1 | - | - | - | 1 | 1 | 1 |
| FSMPublishedAPI | - | - | 1 | - | - | - | - | - |
| FSM_Specific | - | - | - | 1 | - | - | - | - |
| FeatureToggle | - | - | - | - | 1 | 1 | 1 | 1 |
| Form | - | 2 | - | 2 | 1 | 2 | 1 | 1 |
| General | 1 | 1 | - | 1 | 1 | 1 | 2 | 2 |
| IDCreation | - | - | - | - | - | - | - | - |
| MasterData | - | - | - | - | - | - | - | 1 |
| ModuleIntegration_Administration_Impl | - | - | - | 1 | - | - | - | 1 |
| ModuleIntegration_DeepLink_Impl | - | - | - | - | - | - | - | 1 |
| ModuleIntegration_Logging_Impl | - | - | - | - | - | - | - | 1 |
| Note | - | 1 | - | 2 | 2 | 2 | 1 | 1 |
| Part | - | 2 | - | 2 | 1 | 2 | 1 | 1 |
| Reason | - | 1 | - | 1 | 1 | 1 | 1 | 1 |
| RosterManagement | - | 1 | - | 1 | 1 | 1 | 1 | 2 |
| Scheduler | - | - | - | 1 | 2 | 2 | 1 | - |
| Skill | - | 1 | - | 1 | 1 | 1 | 1 | 1 |
| Technician | - | 1 | - | 1 | 1 | 1 | 1 | 3 |
| TicketManagement | - | 13 | - | 12 | 9 | 15 | 11 | 11 |
| TimeRegistration | - | 1 | - | 3 | 3 | 2 | 3 | 4 |
| Tool | - | 2 | - | 2 | 1 | 2 | 1 | 1 |
| Visualizations | - | 1 | - | 1 | 1 | 4 | 1 | 1 |
| WarehouseManagement | - | 1 | - | 3 | 1 | 1 | 1 | 2 |

Reading: `FSMAPIConsumer` touches only `FSMPublishedAPI` (a machine role). `Anonymous` only `General`.
Every human role reaches `TicketManagement`; the role split does not separate capabilities, so
roles are weak evidence and module/entity cohesion carries the grouping. `Dashboard` is the one
module that CCE/SDE/SRM/TechAdm reach but Mechanic and FnAdm do not.

## 3. Candidates and cost

Scored with `bin/cut-score.sh` directly on one 8-partition cut (6 web candidates | mobile+Sync+Utils |
retire 3). Numbers are ref weight crossing the candidate's boundary against ALL other partitions
(other web candidates and mobile), by the tool's lane. "no-lane" = `call`/`action` refs the tool
marks as blocking (no lane for the verdict); OData-ext = associate/retrieve/datasource/xpath/member/
parameter/return/type; write = create/change/commit/delete; REST = call lane. `generalize`/`workflow`/
`role` refs: none exist in this model's `dependencies.json` (kinds present: action, associate, call,
change, commit, create, datasource, delete, layout, member, parameter, retrieve, return, show_page,
type, xpath), so there are no hard blockers of that class; the blockers below are no-lane calls.

| Candidate | Modules | Ent. | Roles using it | OUT (OData-ext / write / REST / no-lane / deep-link / copy) | IN (same) | Biggest no-lane calls | Business fit |
|---|---|---|---|---|---|---|---|
| Insights | Dashboard, Visualizations | 8 | CCE, SDE, SRM, TechAdm (+Mech/FnAdm on Visualizations) | 82 / 0 / 0 / 12 / 10 / 5 | 0 / 0 / 0 / 6 / 0 / 0 | Dashboard->TicketManagement 10, ->Technician 1, ->Scheduler 1 | A reporting/analytics app owned by ops management; read-mostly, releases on its own cadence. Small. |
| Assets & Parts | AssetManagement, Part, WarehouseManagement, Tool | 16 | CCE, FnAdm, Mech, SDE, SRM, TechAdm | 56 / 4 / 1 / 26 / 4 / 17 | 335 / 8 / 29 / 43 / 7 / 0 | Part->NativeMobilePart 8, Part->Sync 7, <-Sync->Part 16, <-MasterData->Part 8 | Asset registry + spare-parts/warehouse is a classic separate system of record (ERP/EAM-adjacent); consumed by reads from everywhere. |
| Dispatch & Workforce | Scheduler, RosterManagement, Technician, Skill, TimeRegistration | 21 | SDE, SRM, Mech, FnAdm, CCE, TechAdm | 184 / 1 / 0 / 74 / 6 / 16 | 260 / 12 / 9 / 52 / 7 / 0 | Scheduler->TicketManagement 16, Scheduler->ModuleIntegration_Administration_Impl 15, TimeReg->NativeMobileTimeRegistration 12 | The planner/dispatch board plus workforce master; a distinct product (dispatchers, rosters, skills), but chatty with tickets. |
| Service Desk & Customers | TicketManagement, CustomerManagement, IDCreation, Reason, Note | 28 | all human roles (CCE 13+, SDE 15, FnAdm 12) | 271 / 4 / 19 / 97 / 10 / 34 | 797 / 22 / 20 / 125 / 16 / 0 | <-Sync->Ticket 36, Ticket->Form 21, <-Scheduler->Ticket 16 | The core domain; nobody splits the core off first. Heaviest crossing in the model. |
| Forms & Checklists | Form | 25 | CCE, FnAdm, Mech, SDE, SRM, TechAdm | 43 / 3 / 0 / 21 / 0 / 4 | 248 / 8 / 0 / 48 / 1 / 0 | <-Sync->Form 19, <-Ticket->Form 21, Form->Sync 12 | Inspection/form builder is separable in product terms but is entwined with tickets and mobile sync. |
| Platform & API | AppSettings, FeatureToggle, General, MasterData, FSM_Specific, FSMPublishedAPI, MI_Administration/DeepLink/Logging_Impl | 7 | TechAdm, API; General for all | 412 / 28 / 0 / 160 / 3 / 0 | 9 / 0 / 0 / 61 / 7 / 129 copy | FSMPublishedAPI->TicketManagement 10, MasterData->NativeMobile 10, MasterData->Part 8 | Not a business capability: shared shell, layouts and glue. It is the residue, not a slice. |

## 4. Ranked recommendation

1. **Insights (Dashboard + Visualizations).** Nearly one-way: 6 refs in, 82 OData-readable refs out, and no write traffic,
   so it becomes a read-only consumer of the other app; only 12 microflow calls (mostly into TicketManagement) need a
   published action or rewrite. Real organisations do run analytics as a separately released app. Small (8 entities),
   so it is a pilot rather than a capability win.
2. **Assets & Parts.** The only substantial candidate whose traffic is mostly the acceptable lane: 335 inbound reads as
   OData external entities, 56 outbound, writes just 12 total. 69 no-lane calls (mobile sync and MasterData callers) are the
   work, and they largely overlap with the mobile partition that must be rewired anyway. Asset/parts master data is
   what a business plausibly owns and releases separately. Dispatch & Workforce is the stronger business story but
   carries about 1.8x the no-lane calls (126 vs 69) and 6x the OData-ext traffic out, so it follows once the pattern works.

## 5. Commands (paths with `<lab>/`)

```
<lab>/mxcli -p "<lab>/fsm/app/<fsm>.mpr" -c "show user roles"
<lab>/mxcli -p "<mpr>" -c "describe user role <Role>"      # x8; ModuleRoles list -> matrix
<lab>/mxcli -p "<mpr>" -c "show entities in <Module>"      # x24 web modules with entities; entity counts
bin/cut-score.sh --facts pipelines/mendix-mpr/samples/fsm-template-9.24.2 \
  --layer-map pipelines/mendix-mpr/samples/fsm-template-9.24.2/app-layer-map.json --json \
  --cut "Scheduler,RosterManagement,Technician,Skill,TimeRegistration|TicketManagement,CustomerManagement,IDCreation,Reason,Note|AssetManagement,Part,WarehouseManagement,Tool|Form|Dashboard,Visualizations|AppSettings,FeatureToggle,General,MasterData,FSM_Specific,FSMPublishedAPI,ModuleIntegration_Administration_Impl,ModuleIntegration_DeepLink_Impl,ModuleIntegration_Logging_Impl|NativeMobile,NativeMobileAsset,NativeMobileForm,NativeMobilePart,NativeMobileRelated,NativeMobileTimeRegistration,NativeMobileWarehouse,NativeNote,NativeReason,NativeRestAPI,NativeTechnician,Synchronization,Utils|NativeModelCheck,LoadTest,TEST_NativeLocalLogin"
```

The per-candidate in/out lane sums come from a throwaway Python tally over the tool's `--json` `rows`
(grouped by `from_partition`/`to_partition`, `lane`, weight). Caveats: tool verdict for the cut is `blocked`
as for every cut on this model; aggregates NOT DETECTED (no catalog); the "no-lane" calls are counted
as blockers by the tool, not as `generalize`/`workflow`/`role`.
