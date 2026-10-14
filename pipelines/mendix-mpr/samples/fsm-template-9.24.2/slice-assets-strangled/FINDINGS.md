# Increment 7 — Assets & Parts strangled: the four modules are deleted from the monolith (2026-10-12)

**Result: level 3 (strangled), with 157 reasoned in-edge hand-offs.** `AssetManagement`, `Part`,
`WarehouseManagement` and `Tool` (plus helper modules `NativeModelCheck`, `LoadTest`) are gone from the FSM 10.24
monolith: 61 → 56 modules, 3250 → 2972 documents. Every one of the 536 in-edge rows is resolved (175), retired (204)
or a hand-off with a written reason (157); none references a deleted module, because the monolith builds without them.
Both apps `mx check` 0 and `BUILD SUCCEEDED`. A new Playwright journey crosses both running apps both ways with data
checked in both databases: 16/16, and 16/16 again on a second consecutive run (idempotent). The increment 6 journey
passes 9/9 after two reasoned changes. Credit: a public Marketplace template (FSM). Written from the worker's handback (commit fa3c416).

**Qualification.** The level 3 row asks for "one journey per crossing edge"; this run has 2 journeys covering the 5
crossing kinds (read, write, join, sync pull, offline forward), not one per in-edge (skill log item 2).

**Route.** Slice (`AssetsApp`, 11.13) publishes `AssetManagement.AssetsAPIv2` (`odata/assets/v2/`, 11 entity sets) and
REST `Part.SeamAPIv2` (`rest/assets/v2`: parts, usedparts, usedparts/delete, inventories/amount). Monolith
(`<lab>/web-assets/mono/`): the 11 published entities were **moved** into one consumer module `AssetsClient`, each
swapped for an external entity of the same qualified name, the modules dropped, then the remaining references rewired
group by group.

## Gates (verbatim)

| Gate | Result | Capture |
|---|---|---|
| `mx check` slice after v2 publish | `4 errors.` (inherited attributes, defect 2), then `0 errors.` | 02 |
| `mx check` monolith after drop + swap | `The app contains: 328 errors.` | 06 |
| … after XPath-text rebind | `183 errors.` (all CE1613) | 08 |
| … microflows / pages / feed | 67 → 3 → 53 (CE0161/CE0463) → 10 → 6 → 4 → 3 → 205 (CE2729) → `0 errors.` | 11–17 |
| `mx check` monolith, final | `The app contains: 0 errors.` (24 s) | 27 |
| mxbuild 10.24.0 monolith | `BUILD SUCCEEDED`, 56 s / final 46 s | 19, 27 |
| `mx check` slice, final | `The app contains: 0 errors.` (11 s) | 23, 25 |
| mxbuild 11.13.0 slice | `BUILD SUCCEEDED`, 22 s | 23 |
| Runtimes | monolith `running: http://127.0.0.1:8580/` (66 / 61 s); slice `running: http://127.0.0.1:8480/` (55 s) | 20, 24, 28 |
| Endpoints (P2) | AssetsAPIv2 and SeamAPIv2: machine 200 / none 401 / human 404; monolith MonoAsset 404; nativesync without credentials 401 | 30 |
| Cut ledger | `811 crossing refs -> 713 ledger rows … handoff 186, platform 6, resolved 285, retire 204, stub 32`, exit=0 | 31 |
| Modules deleted | `AssetManagement: 0 Part: 0 WarehouseManagement: 0 Tool: 0`; also NativeModelCheck, LoadTest | — |

## In-edges, before → after (536 catalog rows)

| | before (inc 6) | after (inc 7) |
|---|---|---|
| handoff | **499** | **157** (+4 new extra rows) |
| retire | 36 | 204 |
| resolved | 1 | 175: rebind 49 · rewired 54 · pull 54 · rest 10 · association 7 · odata 1 |

`rebind` = the reference follows the moved-then-swapped entity by name; `pull` = a native-copy chain fed from the
slice's OData. The 10.24 catalog behind these rows holds 642 in-edge refs in 194 documents. Per-row detail in
`cut-ledger.tsv`, per-document in `inedge-ledger.tsv`.

**Gaps left in the 157 hand-offs:** slice changes to used/suggested parts no longer reach devices; a custom part or new
inventory from a device only gets as far as the part; planning suggested parts/tools on a work order is not possible
from the monolith; deleting an appointment or work order leaves orphan rows in the slice; four "my records" access
rules return nothing; asset-view links and some slice-only fields removed from monolith pages.

## Rewire per group

| Group | Rows | Rewire | Wall clock |
|---|---|---|---|
| All entity refs | — | Move entity into `AssetsClient`, swap for a same-name external entity (recipe A at module scale). 62 XPath strings in 24 units still named the old modules; `tools/bson-rename.py` rebound them (defect 1). | 14:16–14:24 |
| MasterData | 131 | **Retire**: 33 MxAdmin pages/flows over slice data plus WorkOrder_NewEdit_MxAdmin — admin of slice data lives in the slice. | in the swap |
| Synchronization | 146 | **Pull 54** (native copies of Asset, Part, UoM, Warehouse, Inventory, AssetPart fed by `AssetsClient.NativeSync_*`, POST `rest/core/v1/nativesync[/reference]`); **REST 10** (device offline used-part/part actions forward to `rest/assets/v2`); **retire 31**; **hand-off 48** (slice → device push of used/suggested parts; device custom part and new inventory); rebind 3. | 14:24–14:44, 15:32–15:35 |
| TicketManagement | 106 | **Rewired 33** (SLA via CustomerPublicID, preferred technician via PreferredTechnicianID, used/suggested part and tool grids via published key copies); rebind 11, association 2; **hand-off 61** (work-order planning of suggested parts/tools, lost delete cascades, asset-view link, unpublished AgreementGroup/Dossier/Structure fields). | 14:24–15:08 |
| NativeMobile* | 37 | Rebind 7, rewired 13 (Asset_Customer XPath → CustomerName copy); hand-off 17 ("my warehouse" and BOM filters in part search). | in the rewire |
| FSMPublishedAPI | 26 | **Proxy per endpoint** (rebind 12 + rewired 4: GetAssetsForQuery, TicketRequest_GetAsset, TicketResponse_GenerateForTicket, SLA and scheduling validation read the external Asset); hand-off 10 (MapToAssetResponse loses Manufacturer/Structure/Dossier/AgreementGroup). | in the rewire |
| CustomerManagement | 15 | Association 2 (SLA_Asset, ContactPerson_Asset re-created local → external), rewired 2, hand-off 10 (Dossier; "My" rules `[false()]`; asset pickers). | 14:44–15:10 |
| Technician | 11 | Association 1 (Technician_Warehouse as reference set to the external entity), rebind 6, hand-off 4 (selector removed, CE6634; slice owns the link since inc 6). | 15:04 |
| Dashboard | 10 | Rebind 6, association 1, OData 1, hand-off 3 (asset links). | — |
| AppSettings | 6 | Retire (removing slice rows is the slice's job). | — |
| Navigation | 5 | Hand-off (menu items to slice pages removed; deep links). | — |
| Scheduler | 3 | Rebind 2, rewired 1 (planner filters on Ticket.AssetID/AssetFullAddress copies). | 14:54–15:01 |
| RosterManagement | 1 | Association (Roster_Asset → external Asset); delete cascade lost (hand-off). | — |
| Join key (new) | — | Ticket.AssetSystemID/AssetID/AssetDescription/AssetFullAddress and Roster.AssetSystemID set before commit; CoreAPI publishes them; MonoAsset removed. | 14:54–15:18 |
| Security | — | `AssetsClient.User` (read on all 11 external entities) mapped to 7 user roles (CE2729 ×205). | 15:08–15:10 |

**Mobile.** Offline profiles cannot hold external entities, so devices keep their native copies and the monolith now
**pulls** them from the slice: the push ran from the deleted modules' commit flows and can no longer fire. Device writes
forward to the slice over REST. Two sync paths not rewired in the time box (hand-offs, neither references a deleted
module): (1) slice → device push of used/suggested parts — device copies are keyed by the inherited
`SelectedPart.SystemID`, which mxcli cannot publish (defect 2); chain retired. (2) Device custom part and new inventory —
the slice has no inventory-create REST action.

## Module deletion

`drop module` AssetManagement (3 entities, 24 microflows, 10 pages, 3 snippets), Part (2 entities, 63 microflows,
10 nanoflows, 7 pages, 3 snippets), WarehouseManagement (26 microflows, 5 pages, 2 snippets), Tool (24 microflows,
4 pages, 1 snippet), NativeModelCheck, LoadTest (capture 05); moved entities first. The asset mirror was
AssetManagement.Asset and is gone; rosters reference the slice asset directly. `publish entity AssetsClient.Asset as
'MonoAsset'` (an external entity republished) passed `mx check` but answered 404 at runtime, so it was removed
(capture 21). Journey seeds kept and marked `-- TEST-ONLY … remove before real use` above the
`AssetsSeam.ASU_EnsureJourneyAccounts` call in General.ASU_General.

## E2E journey (Playwright 1.56.1, headless Chromium, both apps running) — verbatim

```
  PASS  [slice: asset and part created in the slice] asset AS-261012154038 in the SLICE database, preferred technician picked from the monolith (key copy PreferredTechnicianID set before commit) — [{"AssetID":"AS-261012154038","PreferredTechnicianID":"1",…}]
  PASS  [slice: asset and part created in the slice] part PS-261012154038 in the SLICE database — [{"Name":"Strangled part 261012154038","PartID":"PS-261012154038",…}]
  PASS  [slice: asset and part created in the slice] inventory of PS-261012154038 (amount 10) in warehouse WS-261012154038, SLICE database — [{"Amount":"10",…}]
  PASS  [monolith server flow: native copies fed from the slice] POST rest/core/v1/nativesync answers — HTTP 200 native copies fed from the slice: assets 1, parts 1
  PASS  [monolith server flow: native copies fed from the slice] native asset copy written in the MONOLITH database from the slice OData (AssetsClient.Asset -> Synchronization.AssetList_UpdateNativeAssets) — [{"AssetID":"AS-261012154038",…}]
  PASS  [monolith server flow: native copies fed from the slice] native part copy written in the MONOLITH database from the slice OData — [{"Name":"Strangled part 261012154038",…}]
  PASS  [monolith server flow: native copies fed from the slice] POST rest/core/v1/nativesync/reference answers (units, warehouses, inventories, BOM) — HTTP 200 native reference copies fed from the slice: units 8, warehouses 8, inventories 5, asset parts 0
  PASS  [monolith server flow: native copies fed from the slice] native inventory copy in the MONOLITH database, linked to the native part and warehouse (navigations over the slice OData) — [{"Amount":"10",…}]
  PASS  [monolith: no local asset tables] the monolith no longer publishes an asset mirror (odata/core/v1/MonoAsset) — HTTP 404
  PASS  [monolith: no local asset tables] OQL on AssetManagement.Asset fails in the monolith (module deleted)
  PASS  [slice -> monolith -> slice: roster on the slice asset] roster in the MONOLITH database on the slice asset (external entity), key copy AssetSystemID set before commit — [{"AssetSystemID":"38414e1f-…","PublicID":"9"}]
  PASS  [slice -> monolith -> slice: roster on the slice asset] the slice reads it back over OData by the published key copy (Roster.AssetSystemID) — rows 0 -> 1
  PASS  [slice -> monolith -> slice: roster on the slice asset] deleted from the slice grid -> gone from the MONOLITH database — []
  PASS  [monolith -> slice: used part over REST] used part UJ-261012154038 created in the SLICE database by the monolith machine account, stock booked (Amount 10 -> 8) — HTTP 200 created UJ-261012154038 [{"Amount":"8","IsFromWarehouse":true,"Quantity":"2"}]
  PASS  [monolith -> slice: used part over REST] delete through the slice's own UsedPart_Delete restores the stock (P7) — HTTP 200 deleted UJ-261012154038 amount 10
  PASS  [monolith -> slice: used part over REST] the REST action refuses wrong credentials — HTTP 401

strangled journey: 16/16 assertions passed in 29.1 s — PASS
  timings: step 1 (slice UI) 7.5 s; step 2 (native-sync pull) 15.0 s; step 3 (no asset tables) 0.2 s; step 4 (roster round trip) 4.9 s; step 5 (used part REST) 1.5 s
exit=0 wall 30 s
```

A second consecutive run passed 16/16 in 20.9 s (run-timestamped IDs, no step relies on an empty grid).
**core-seam (inc 6) re-run: 9/9 in 8.0 s** after two changes: its monolith OQL now joins on `Roster.AssetSystemID`
(the joined asset table is gone), and the "New Asset" click is dispatched because the legacy grid's sticky column
header intercepts pointer events once the grid holds enough rows — the root cause of the increment 5 non-idempotency.

**Not covered:** no ticket, work order or appointment created through the FSM UI (the monolith database holds none).
Monolith → slice writes are proven at the service boundary (the REST action that `OfflineUsedPartAction_Process` and
the new "Add used part" button call, with the monolith's machine account); the monolith-side microflow → REST path has
not run.

## Timings (wall clock 14:03 → 15:43, 1 h 40 min including authoring)

| Step | s | Step | s |
|---|---|---|---|
| exec slice v2 publish (+fix) | 3.5 | mx check 11.13 | 10–11 |
| exec monolith move (11 entities) | 62 | exec drop + swap | 27 |
| bson-rename (62 strings) | <1 | mx check 10.24 | 19–25 |
| exec rewire (48 flows drop+create), run 3 | 270 | exec feed + pages | 36 |
| mxbuild 10.24 | 56 / 46 | mxbuild 11.13 | 22 |
| monolith boot | 66 / 61 | slice boot | 55 / ~40 |
| strangled journey | 29 / 21 | core-seam journey | 8.0 |
| cut-ledger | 0.12 | | |

## Skill log (skills not edited)

1. **`decompose-app.md` level 3 has no recipe.** Add Stage 5b "Strangle": `move entity` into one consumer module →
   same-name external entities → re-create monolith-owned associations local → external → drop modules → work the
   `mx check` phases (CE1613, then CE0161/CE0463, then CE2729). Warn that describe → sed → exec is not an option: 25 of
   38 referencing pages held widgets mxcli cannot author (34 DataGrid, 21 ReferenceSelector).
2. **"One journey per crossing edge" is undefined for 536 rows.** Use one journey per crossing kind with data checked
   in both databases, plus a second consecutive passing run.
3. **`mendix-service-seam.md` P1 "never fails a commit" is wrong.** Page-created objects fail: `Failed to commit: Value
   of auto-number attribute 'PublicID' not available, could be caused by insufficient access rights to serialize the
   mendix object to the client` (capture 25). Grant read on the key to every module role with an access rule on the entity.
4. **Recipe B's mirror is temporary.** At level 3 it is the module being deleted. Recipe B′: the owner-side entity
   carries a key copy set before commit and publishes it; removing the mirror is a breaking change (P10).
5. **XPath limits incomplete.** A local entity cannot compare its own local → external association with an object
   (`[TicketManagement.Ticket_Asset = $Asset]` → CE0161); retrieving an external entity by reverse association → CE0161;
   retrieve over the navigation instead.
6. **Offline: push chains die** when the owner's commit flows move; rebind them and add a pull entry (NativeSync_Pull*).
7. **Stage 4 at level 3:** the measure is in-edge hand-offs; add resolution kinds rebind, pull, rewired, association;
   a hand-off must not reference a deleted module.
8. **P13 covers only the slice side:** the monolith's own cascades into slice rows are lost
   (AppointmentList_Delete, WorkOrderList_Delete) — REST delete-for-parent or an orphan hand-off.
9. **Association limits incomplete:** reference sets local → external work but entity-path widgets over them fail
   CE6634; slice-owned associations to monolith entities cannot be published (need key copies); inherited attributes are
   not publishable via mxcli, so each specialization needs its own key.
10. **"ALTER cannot replace a decision" is misleading at scale:** edited flows needed drop + create (MDL-V1-REBUILD),
    which resets layout and broke one decision (defect 6). Edit only what needs edits; keep a per-unit restore path.
11. **Trap: trial licence.** Machine OData sessions count against the cap: `The OData endpoint returned 402 Payment Required` (capture 29).
12. **Trap: DataGrid 2 on 10.24** gives `CE0463 "The definition of this widget has changed"` until `mxcli fix widgets`.

## mxcli defects (filed in `contrib/inbox/2026-10-12-increment-7-strangled-findings.md`)

1. `move entity` does not rewrite qualified names in XPath/expression text (62 strings in 24 units kept `AssetManagement.Asset…`).
2. Published OData stores inherited attributes under the specialization: `[CE1613] "The selected attribute 'Part.UsedPart.PublicID' no longer exists."`; the qualified form is a parse error.
3. `alter snippet … { drop w; }` cannot find a widget nested in a legacy widget: `widget "referenceSetSelector2" not found`.
4. `grant read (…) on entity E to R where […]` adds a second access rule when R already has one.
5. A consumed service's cached `$metadata` cannot be refreshed (`create or modify external entities` reports `4 updated`, adds nothing); drop and re-create the service.
6. describe → drop/create broke an unchanged decision: `[CE0117] "Error(s) in expression." at Decision 'User is SDE?'`.
7. describe output not re-executable: `microflow returns Boolean but not all code paths have a return statement [MDL003]`.
8. `mxcli oql --json` returns numbers as strings.
9. Confirmed again: `drop module` leaves access-rule references to dropped associations (CE1613 ×35 in a probe).

Not mxcli: CE0161 on local → external association compares; AutoNumber read requirement at commit; trial 402; an
external entity republished passes `mx check` and answers 404; DataGrid 2 CE0463 until `fix widgets`.

## Still unmeasured

- Monolith flows calling the slice's REST (`OfflineUsedPartAction_Process`, `ACT_UsedPartDraft_Save`) — no offline actions or appointments existed.
- FSM ticket/work-order/appointment UI over external assets (TicketNP picker, planner key-copy filters, Appointment_View and WorkOrder_View grids).
- Legacy grid columns over local → external paths at runtime; FSMPublishedAPI at runtime; outage with the slice down.
- Not built: slice → monolith change notification for key copies, a scheduled pull, token auth/TLS, data migration (databases were empty).
- No `tests/wave2` fixture for the new resolution kinds.
