# Increment 5 (web) — Assets & Parts out of FSM into its own Mendix 11.13 app (2026-10-12)

**Result: build-green (level 1) reached. Seam-live (level 2) NOT reached for the slice.**
Both seam lanes are proven end to end with security on (OData reads with basic auth, a REST write
action) and one browser journey crosses the seam (PASS). Of the monolith's 536 in-edge rows, 1 is
rewired to OData and one more write path is a dual write. The slice still carries 120 behaviour stub
rows (67 documents). Credit: a public Marketplace template (FSM). Written from the worker's handback (commit 59bd714).

**Route.** `AssetManagement`, `Part`, `WarehouseManagement`, `Tool` moved by MPK into
`mxcli new AssetsApp --version 11.13.0`: FSM 9.24.2 copy → `mx convert` 10.24 → `export-module-mpk.py`
→ `marketplace install --file`; edges in MDL (stubs generated from source, legacy widgets converted for
the React client); seam scripts; both apps run locally; one Playwright journey.

**Monolith side ran on the 10.24 converted copy**, runtime included (mxcli 0.26 cannot author
microflows in 9.x, increment 4). Increment 4's one-time fixes reapplied (captures 20–23).

## Gates (verbatim)

| Gate | Result | Capture |
|---|---|---|
| `mx check` 11.13, build-green | `The app contains: 0 errors.` (287 CE1613 after installs → 55 → 60 → 38 → 0) | 08, 10, 12, 14, 15 |
| mxbuild 11.13.0 `--target=deploy` | `BUILD SUCCEEDED`, 22.8 s | 16 |
| Fidelity, 10.24 source vs 11.13 target | 207 identical, 5 drift (Atlas design-property renames), 19 not-expressible (pages/snippets with converted legacy widgets); Part nanoflows 10/10 identical | 17, 18 |
| Cut ledger, build-green | 703 rows, `exit=0`, 0 unresolved | 19 |
| `mx check` 11.13, seam-live (Production security, OData + REST published) | `The app contains: 0 errors.` | 28 |
| `mx check` 10.24 monolith after the seam | `The app contains: 0 errors.` | 31 |
| Runtimes | slice `Mendix Runtime 11.13.0 … successfully started` (8480/8490); monolith `Mendix Runtime 10.24.0.73019 … successfully started` (8580/8590) | 29, 32, 34 |
| Cut ledger, seam-live (`--refs`, byte-identical to `--catalog`) | 703 rows, `exit=0` | 36 |

## Cut ledger — 811 catalog refs → 703 rows, 0 unresolved

| Direction | resolved | stub | handoff | retire | platform |
|---|---|---|---|---|---|
| out (167: 155 catalog + 7 check-only + 5 extra) | 41 | **120** | 0 | – | 6 |
| in (536) | 1 (`resolved:odata`) | – | 499 | 36 (NativeModelCheck, LoadTest) | – |

Out `resolved`: copy-drift (layout) 17, marketplace (CommunityCommons) 10, starter (Atlas_Core,
Administration) 10, convert-drift (widgets) 1, fix (design properties) 1, copy (enumerations) 1, security 1.

**Stub count (progress measure): 120 rows / 67 documents at build-green and at seam-live.** The seam
work went IN (monolith consumes the slice); every stub is OUT. Clearing them needs the monolith to
publish services (Technician, Customer, Ticket, WorkOrder, Roster) or the Mobile partition to take the
native sync.

**Behaviour-carrying stubs:**
- `Technician.*`: empty, so technician pickers/grids are empty; the Part/Tool/Warehouse "My" access rules go
  through `Administration.Account_Technician`, a stub association added to a Marketplace module.
- `CustomerManagement.*`: Customer/Contract/Contact pickers list nothing; SLA lookup empty; `ContactPerson_View` stub.
- `TicketManagement.*`: asset ticket tab empty; work-order used/suggested parts and tools invisible; `Ticket_View` stub.
- `RosterManagement.*`: rosters from the asset tab never reach the planner; `ACT_Roster_Delete` does nothing; `Roster_NewEdit` stub.
- `Synchronization.*` (11 flows) and `NativeMobile{Asset,Part,Warehouse}.*`: device push does nothing (hand-off to the Mobile partition).
- `AppSettings.ApplicationSettings_CalculateNativeKeepUntilDate` returns empty.

## Seam — OData vs REST

| Edge | Lane | State |
|---|---|---|
| Slice publishes `AssetManagement.AssetsAPI` (`odata/assets/v1/`): Assets, Parts, UnitsOfMeasure, Warehouses; read-only; basic auth; role `APIConsumer` | OData | live |
| Monolith consumes it: `AssetsSeam.AssetsAPI`, 4 external entities, auth via headers microflow (`CommunityCommons.Base64Encode`) | OData | live; journey read Parts through it |
| `Dashboard.DS_CountAssets` → `AssetsSeam.Assets` (in-edge E168) | OData | rewired, `mx check` 0; not opened at runtime |
| New monolith page `AssetsSeam.Parts_FromSlice` | OData | live; new consumer, not a catalog in-edge |
| Slice publishes `Part.SeamPartAPI`, `POST rest/assets/v1/parts` → `Part.SeamAPI_UpsertPart` | REST | live: `created P-SEAM-1`, then `updated P-SEAM-1`; 401 without/wrong credentials (capture 33) |
| `MasterData.ACT_Part_Save_MxAdmin`: REST upsert after local save, `on error without rollback` + log | REST | built, `mx check` 0; stays handoff (dual write); not exercised (empty monolith DB, admin Part tab is Edit only) |

- **OData for reads:** the lane the done-criterion names; mxcli authors both ends (published on 11.13, consumed + `create external entities` on 10.24).
- **REST for the write:** published entities are read-only; a REST action with query parameters needs no mappings.
- **Tool not published:** an OData key needs a unique validation rule (CE6624) and no Tool attribute is ever set uniquely.
- **Assumed blocker removed:** a local → external association (`TicketManagement.Ticket` → `AssetsSeam.Assets`) passes
  `mx check` on 10.24 (capture 35). `Ticket_Asset`, `ContactPerson_Asset`, `Roster_Asset`, `Technician_Warehouse` can be
  re-pointed: per-consumer rewiring work, not a platform limit. Unmeasured at runtime and on 11.13.

## Security

- **Slice: Production.** Six FSM human roles recreated with exactly the slice module roles they held in FSM;
  stub-module `User` roles for read access to stub entities (CE2729 ×278 without them). Machine role `AssetsAPI` is
  the only role granted on both services (a human role gets 404 on OData). Demo users off; accounts created at
  startup from constants whose values live only in the machine's mxcli constant store, never in git.
- **Monolith: Production, unchanged.** New module role `AssetsSeam.User` mapped to 5 FSM roles; API password a machine-local constant.
- **Not done:** plain HTTP on localhost (no TLS, no rotation); no per-user identity reaches the slice.

## Journey (Playwright 1.56.1, headless Chromium, both apps running) — verbatim

```
  PASS  [slice login] logged in to the slice as journey_fnadm; home page is Parts — ledger: in Navigation.Responsive -> slice menu (handoff)
  PASS  [slice: new unit of measure] unit Box-261012093950 committed in the slice database — [{"SystemID":"82cbeb68-…","UnitName":"Box-261012093950"}]
  PASS  [slice: new part] part PW-261012093950 committed in the slice with Part_UnitOfMeasure = Box-261012093950 — [{"Name":"Journey part 261012093950","PartID":"PW-261012093950","UnitName":"Box-261012093950"}]
  PASS  [monolith: part visible over OData] monolith page lists PW-261012093950 from external entity AssetsSeam.Parts — row: "PW-261012093950 Journey part 261012093950 12.5 ACME" — ledger: in-edge read of Part.Part rewired to OData (seam-mono-rewire.mdl)

assets-seam journey: 4/4 assertions passed in 5.2 s — PASS
  trace rung: NOT RUN (no OTel exporter on either app)
exit=0 wall 5.7 s
```

Shape follows `project-tests/e2e/journey-runner.js` (landing guard per step, data effects by `mxcli oql`,
ledger pointer; exit 2 = instrument fault). `helpers.js` login not reused: it is single-app, and FSM signs
in through anonymous page `General.Login_Web`, not `login.html`.

## Timings (wall clock ~2 h 10 min including authoring)

| Step | s | Step | s |
|---|---|---|---|
| copy FSM | 0.3 | `mx check` 11.13 (each) | ~10 |
| graph-report (9.24) | 20.0 | mxbuild 11.13 | 22.8 |
| `mx convert` 10.24 | 34.6 | compare-mdl (4 modules + nanoflows) | ~150 |
| exports ×8 | <1 each | cut-ledger | 0.14 |
| `mxcli new` 11.13 | 34.2 | exec seam-slice / security / stubs / nav | 2.4 / 2.3 / <2 / <2 |
| CommunityCommons install | 17.6 | slice `mxcli run` (build + boot) | 62.0 |
| 4 × `install --file` | 8.7 + 8.4 + 8.4 + 7.7 | monolith marketplace updates (`--force`) | 12.3 + 29.8 |
| exec edges A + B | 0.4 + 5.9 | exec seam-mono / rewire | 5.8 / 19.5 |
| exec edges C (widgets) | 5.3 | monolith `mxcli run` | 71.3 / 63.3 |
| `mx check` 10.24 (each) | ~25 | journey | 5.7 |

## mxcli defects (filed in `contrib/inbox/2026-10-12-increment-5-web-assets-findings.md`)

1. Combo box bound to an association via `Attribute:` passes `check`, exec refuses: `property attributeEnumeration binds Asset_Customer, which is an association … not an attribute`.
2. Combo box in association mode bound straight to a snippet parameter: `check` and exec pass, `mx check` `CE7007 "Selected value is not valid for entity 'Asset_Customer/Customer'"` ×9. Workaround: wrap in `dataview (DataSource: $Asset)`.
3. Quoted keyword attribute in an OData `expose` list stored with its quotes: `expose ("Description")` → `CE1613 … 'AssetManagement.Asset."Description"' no longer exists` ×4. Bare `Description` works.
4. Published OData passes `check` without a KEY, then `CE6585 "Published entity '…' must have a key defined."`; a KEY without a unique rule passes `check`, then `CE6624`.
5. `create external entities` names entities after the entity set (`AssetsSeam.Parts`), not the entity type (`Part`) as Studio Pro does.
6. `describe entity` emits `index ( desc);` with no column (`NativeMobileAsset.NativeAsset`) — confirms increment 3 defect 9 and the native bug hunt's D1.
7. No headless route from legacy widgets to the React client: `-- Forms$DataGrid (grid1) -- NOT re-executable` with no datasource/columns/buttons; `install --file` of a 10.x package into 11.x does not warn about the CE0582 to come (×22). Workaround: `mxcli bson dump` + `tools/legacy-extract.py` + `tools/gen-widgets.py`.
8. Data grid 2 written by `create page` on 10.24 (DataWidgets 2.5.6) fails `CE0463` until `mxcli fix widgets`.
9. `marketplace update` refuses without `--force` on a freshly converted copy, reporting local JS action edits (`Wait`, `Vibrate`) nobody made.

**Mendix platform tool (`mx` 10.24):** `mx update-widgets fsm.mpr` with a relative path → `System.ArgumentNullException: Value cannot be null. (Parameter 'path')`; absolute works.
**Possible, unverified:** `fix design-properties` left `'Make card': on` where the source began with `'Spacing bottom'` (`Snippet_Asset_Notes`, `Warehouse_View`).

## Changes to the monolith copy (10.24)

One-time build fixes from increment 4 (none touches the seam): NanoflowCommons 5.2.1 and
NativeMobileResources 10.1.17 updates (`--force`); `mx update-widgets`; Scheduler grid2 XPath same-length
patch (drops the TechnicianGroup filter); `JavaVersion: '21'`; `theme/web/index.html` removed; 3 Java edits.

Seam: new module `AssetsSeam` (6 constants, 2 machine-local passwords; consumed OData service with 4 external
entities; auth headers microflow; page `Parts_FromSlice`; module role `User` mapped to 5 user roles; journey-account
microflows). `Dashboard.DS_CountAssets` reads `AssetsSeam.Assets`. `MasterData.ACT_Part_Save_MxAdmin` saves locally
then upserts over REST. `General.ASU_General` calls `AssetsSeam.ASU_EnsureJourneyAccounts` — **remove before any real use**.

## Changes to the slice beyond the moved modules

- Copied with drift: `FSM_Specific.LeftMenuLayout` (brand image, alerts snippet, sidebar toggle dropped) and FSM `themesource/fsm_specific/web` without its images/fonts (404s, capture 34).
- Generated: 67 stub documents + 9 enumerations verbatim; 26 legacy widgets converted on 19 pages/snippets. Drift: 3 Select buttons dropped, 2 association sorts dropped, 1 selectable-objects microflow not carried, 1 microflow+paging source rewritten as XPath, 9 combo boxes wrapped in a data view.
- Edits to moved entities/roles/pages: unique rule on `SystemID` of Asset, Part, UnitOfMeasure, Warehouse (OData key); API module roles in 4 modules; `Part.SeamAPI_UpsertPart`; page grants on `Part_Overview` and `Tool_Overview` (none in FSM).
- New: `SliceSetup` module, navigation, Production security.

## Still unmeasured

- The monolith-side REST call at runtime; `DS_CountAssets` not opened in a browser.
- The other 499 in-edge rows: Synchronization 146, MasterData 131, TicketManagement 106, NativeMobile* 37, FSMPublishedAPI 26, CustomerManagement 15, Technician 11, Dashboard 10, AppSettings 6, Navigation 5, Scheduler 3, RosterManagement 1.
- All 120 stubs (need monolith-published services or the Mobile partition).
- Runtime behaviour of local → external associations, and the same on 11.13.
- Data migration of existing asset/part/warehouse rows (both databases started empty).
- A 9.24 monolith calling the slice (authoring blocked, increment 4).
- Latency, slice outage, OData paging under load; consistency in the dual-write window.
- No `tests/wave2` fixture for the three lab generators in `tools/`.
