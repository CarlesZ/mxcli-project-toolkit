# Increment 6 — the monolith publishes its core, the Assets & Parts slice consumes it (2026-10-12)

**Result: seam-live (level 2) for the non-Mobile core.** Of increment 5's 89 non-Mobile stub rows, 68 are
now working OData reads or REST calls; 20 are hand-offs with a written reason (16 access-rule XPath that
external entities cannot evaluate, 4 grid columns needing a local-table × remote-set join); 1 stub remains
(`AppSettings…CalculateNativeKeepUntilDate`, native-sync logic). The 31 Mobile stub rows are unchanged and
counted separately. Both apps `mx check` 0 and `BUILD SUCCEEDED`; the cut ledger exits 0; a new Playwright
journey crosses slice → monolith → slice (9/9 PASS) and the increment 5 journey still passes.
Credit: a public Marketplace template (FSM). Written from the worker's handback (commit c9486dd).

**Route.** `skills/decompose-app.md` Stage 2 ("monolith publishes first") and Stage 5. On the FSM 10.24 copy
(`<lab>/web-assets/mono/`, carrying increments 4 and 5) the monolith publishes OData `CoreSeam.CoreAPI`
(`odata/core/v1/`, 12 entity sets) and REST `CoreSeam.CoreActions` (`rest/core/v1/rosters`). In the slice
(`AssetsApp`, 11.13) stub entities are swapped for external entities and every consumer is rewired.

## Gates (verbatim)

| Gate | Result | Capture |
|---|---|---|
| `mx check` 10.24 monolith, after publish | `The app contains: 0 errors.` | 02 |
| `mx check` 10.24 monolith, final | `The app contains: 0 errors.` (30 s) | 15 |
| mxbuild 10.24.0 `--target=deploy`, monolith | `BUILD SUCCEEDED`, 51 s | 15 |
| `mx check` 11.13 slice: 29 → 7 → 19 → 3 → 1 → 4 → 0 | `The app contains: 0 errors.` | 06, 08, 11, 13 |
| mxbuild 11.13.0 `--target=deploy`, slice | `BUILD SUCCEEDED`, 20 s | 16 |
| Runtimes | monolith `running: http://127.0.0.1:8580/` (8580/8590, serve 6643); slice `running: http://127.0.0.1:8480/` (8480/8490) | 17, 18 |
| Endpoints | OData machine role `HTTP 200`, no credentials `401`, human role `404`; REST `created 1` / `deleted 1`, no credentials `401` | 19 |
| Cut ledger | `811 crossing refs -> 709 ledger rows … by resolution: handoff 525, platform 6, resolved 110, retire 36, stub 32`, `exit=0` | 22 |

## Stub count (progress measure)

| | rows | documents |
|---|---|---|
| Before (increment 5, all OUT) | 120 | 67 |
| — non-Mobile | 89 | 36 |
| — Mobile (`Synchronization.*` 11, `NativeMobile*` 20) | 31 | 31 |
| **After, non-Mobile stub** | **1** | **1** |
| After, non-Mobile hand-off (with reason) | 20 | — |
| **After, Mobile hand-off (unchanged, out of scope)** | **31** | **31** |

The 89 non-Mobile rows resolve as `resolved:odata` 47, `resolved:rest` 11, `resolved:local-owner` 7,
`resolved:page-odata` 3, `handoff` 20, `stub` 1.

**Remaining non-Mobile rows:**
- `stub` ×1: `Part.SuggestedPartList_Commit -> AppSettings.ApplicationSettings_CalculateNativeKeepUntilDate` — computes
  a used part's keep-until date on the device: native sync, Mobile partition, not a publishable core service.
- `handoff` ×16, XPath limit: `Account_Technician` ×4 (SuggestedPart, UsedPart, SelectedTool, Tool),
  `WorkOrderAssignment_Technician` ×5, `WorkOrderAssignment_WorkOrder` ×5, `WorkOrderAssignment` ×1 (check-only),
  `Appointment_WorkOrder` ×1 — the "My" access-rule disjuncts walking slice → WorkOrder → WorkOrderAssignment →
  Technician → Account. XPath cannot traverse local ↔ external, so each became `[false()]`. A slice-side fix needs a
  REST-fed local copy of the assignments.
- `handoff` ×3, column dropped: `Asset_Overview -> Customer`, `Part_View -> Customer`, `Part_View -> Technician` —
  database grids showing `Asset_Customer/CustomerName` / `Asset_Technician_Preferred/TechnicianName` across a local →
  external association. Fix: a local copy of the name on Asset.
- `handoff` ×1: `ContactPerson_Dossier` — owned by the monolith's ContactPerson, pointing at the moved
  `AssetManagement.Dossier`; an external entity cannot own an association to a local entity and the monolith does not
  publish dossiers. Level 3 in-edge rewire.
- 6 new extra rows (all `handoff`): basic → token auth; the monolith asset mirror (dual owner); delete cascade from
  WorkOrder/Appointment lost (orphans); availability coupling (capture 21); `NumberOfWorkOrders` column (contract
  change); the journey seed microflow.

## Lane per core entity

| Core entity | Lane | Why |
|---|---|---|
| Technician | OData (key `TechnicianID` AutoNumber) | Pure read: combo boxes, warehouse picker. Journey step 2 picks it. |
| Customer, Contract | OData (key `PublicID`) | Read for combo boxes on slice-owned `Asset_Customer/_Contract/_UmbrellaContract` (local owner, legal). |
| ContactPerson | OData + read-only page `ContactPerson_View` | Read; edits stay in FSM. Grid filters `[ContactPerson_Asset/MonoAsset/SystemID = $Asset/SystemID]`. |
| SLA | OData | `Asset_GetRelevantSLA` rewritten: retrieve by association, filter the external SLA by key; the Standard fallback compares a String (enum arrives as `Edm.String`). |
| Ticket, Priority, TicketType | OData + read-only page `Ticket_View` | Read; ticket handling stays in FSM. `ACT_Asset_Delete` guard reads over OData. |
| WorkOrder, Appointment | OData | Only slice-owned associations point at them; `change $WorkOrder refresh` is now a no-op. |
| Roster | **REST** create/delete, OData read, read-only page | Write with behaviour. The slice cannot create an external object, so a non-persistent `RosterDraft` is posted to `POST rosters`; the monolith upserts its asset mirror and creates the roster. Delete runs the monolith's own `Roster_Delete`. Edit stays in the FSM planner. |
| Asset (monolith copy) | OData `MonoAsset` (key `SystemID`, unique rule) | The cross-app **join key**: tickets, rosters, contacts, SLAs of a slice asset via `…_Asset/MonoAsset/SystemID`. |
| Technician ↔ Warehouse | **Local owner entity** `CoreSeam.TechnicianLink` | XPath access rules need it locally; the slice owns the assignment, the monolith's copy is a second owner (in-edge hand-off). |

No entity needed a full REST-fed local copy; `TechnicianLink` is the one local copy (names copied from OData at link time).

## Removing the Marketplace stub association

`Administration.Account_Technician` was dropped (`slice-core-consume.mdl`); the starter's Administration module is
unmodified again. In its place, local entity `CoreSeam.TechnicianLink` (TechnicianID, name, phone, employee number,
company) owns `TechnicianLink_Account` (→ `Administration.Account`), `TechnicianLink_Warehouse` and
`TechnicianLink_Technician` (→ external Technician), all declared in `CoreSeam`. The "My" rules of Part, Inventory and
Warehouse read `…/CoreSeam.TechnicianLink_Warehouse/CoreSeam.TechnicianLink/CoreSeam.TechnicianLink_Account = '[%CurrentUser%]'`.
The warehouse Technicians tab gets an "Add technician" picker plus Account/Remove buttons — not exercised by a journey.

## Security

- **Monolith: Production.** Adds machine user role `CoreAPIClient`: `CoreSeam.APIClient` plus one read-only `CoreAPI`
  module role in each of Technician, CustomerManagement, TicketManagement, RosterManagement, AssetManagement, granted
  exactly the published members; create/delete on Roster and Asset for the REST actions only. Only role on both
  services. Measured 401 anonymous, 404 human (`journey_fnadm`), 200 machine (capture 19). The `assets_slice` account
  is created at startup only when `CoreSeam.SliceAPIUserPassword` is not the sentinel `__SET_ME__`.
- **Slice: Production.** New module roles `CoreSeam.User`, `CoreSeam.Admin`, `Technician.User` mapped to 7 user roles;
  external entities granted read to their module's `User` role.
- **Credentials:** basic auth, password only in the two machine-local constant stores; model defaults `__SET_ME__`
  (`learned-constants-and-secrets.md` Step 3; increment 5 used `''`).
- **Hand-off:** token-based service auth (OIDC SSO, client credentials), TLS, rotation. Run used plain HTTP on localhost.
- **Trap:** the first generated password had no symbol; the Mendix password policy refused it inside the
  after-startup microflow and the whole monolith failed to boot (capture 03).

## Journeys (Playwright 1.56.1, headless Chromium, both apps running) — verbatim

```
  PASS  [slice login] logged in to the slice as journey_fnadm
  PASS  [slice: technician served by the monolith] combo box lists "Journey Technician" from external entity Technician.Technician (monolith OData CoreAPI) — ledger: out Technician.Technician -> resolved:odata (slice-core-external.mdl)
  PASS  [slice: technician served by the monolith] asset AJ-261012115934 committed in the slice database — [{"AssetID":"AJ-261012115934","SystemID":"…"}]
  PASS  [slice -> monolith: roster created over REST] asset details show preferred technician "Journey Technician" (local -> external association, slice-owned)
  PASS  [slice -> monolith: roster created over REST] roster committed in the MONOLITH database on its asset mirror (SystemID = slice asset) — [{"AssetID":"AJ-261012115934","PublicID":"…","StartDate":"Sun Oct 11 22:00:00 UTC 2026",…}] — ledger: out RosterManagement.Roster -> resolved:rest (CoreSeam.Roster_CreateRemote)
  PASS  [monolith -> slice: roster read over OData] asset tab grid lists the roster from external entity TicketManagement.Roster (Roster_Asset/MonoAsset/SystemID filter) — rows 0 -> 1
  PASS  [slice -> monolith: roster deleted over REST] roster gone from the monolith database (RosterManagement.ACT_Roster_Delete -> POST rosters/delete) — []
  PASS  [monolith -> slice: tickets and contacts tabs over OData] Tickets tab grid … renders with no error dialog — error dialogs: 0
  PASS  [monolith -> slice: tickets and contacts tabs over OData] Contacts tab grid … renders with no error dialog — error dialogs: 0
core-seam journey: 9/9 assertions passed in 7.8 s — PASS
exit=0 wall 8 s
```

Full text in `journey/run-output.txt`. The increment 5 journey (unchanged) passes 4/4 in 5.3 s on the final model
(`journey/inc5-assets-seam-rerun-output.txt`). Two earlier re-runs ended `exit=2` at "New Part": after 4+ journey parts
had accumulated, the Parts grid's sticky header covered the button. Not a seam regression; **the increment 5 journey is
not idempotent.**

Outage probe: with the monolith stopped, opening an asset in the slice raises generic error dialogs and the page is
unusable (capture 21) — recorded as availability-coupling hand-off. The REST error path was not reached (dialogs, then
the trial licence's session cap).

## Timings (wall clock ≈ 1 h, including authoring)

| Step | s | Step | s |
|---|---|---|---|
| exec mono-core-publish / actions | 15.4 / 22.8 | mx check 10.24 | 25–30 |
| exec slice consume / external / rewire | <2 / ~10 / 10 | mx check 11.13 (each) | 10–12 |
| mxbuild 10.24 monolith | 51 | mxbuild 11.13 slice | 24 / 20 |
| monolith boot / restart | 88 / 68 | slice boot / restart | 42 / 39 |
| core-seam journey | 7.8 | increment 5 journey | 5.3 |
| cut-ledger | 0.08 | | |

## mxcli defects (filed in `contrib/inbox/2026-10-12-increment-6-core-services-findings.md`)

1. `check --references` ignores attributes added by `ALTER ENTITY … ADD ATTRIBUTE` earlier in the same script: `retrieve from RosterManagement.Roster: the constraint names "PublicID", which is neither an attribute nor an association of it`.
2. `drop entity` silently removes every cross-module association pointing at it, and their member rights in other entities' access rules (`describe association AssetManagement.Asset_Technician_Preferred` → `Error: association not found`, no message at the drop).
3. A dropped owner-Both association leaves a hidden `MemberAccess` that neither `revoke all` nor `grant` removes: `CE1613 "The selected association 'CustomerManagement.SLA_Asset' no longer exists." at Access rule of entity 'AssetManagement.Asset'` ×3 (surfaced as `CE6593` while a same-named association existed). Workaround: create then drop a same-named association from a throw-away entity (`slice-core-fix2.mdl`).
4. `ConfigurationMicroflow:` holding a headers microflow → `CE6808 "The microflow that configures a consumed OData service should return a System.ConsumedODataConfiguration"` on 11.13 (passed on 10.24). The slot cannot be cleared afterwards (`alter … set (HeadersMicroflow: …)` keeps it; `create or modify` says `Unchanged OData client`). Workaround: drop the consumed service and recreate with `HeadersMicroflow:` only (external entities survive).
5. `alter consumed odata service … set (ConfigurationMicroflow: none)` (also `empty`) stores a microflow **named** `none`; `mx check` then crashes with a .NET stack trace.
6. `check` passes and exec refuses mid-script: `create or modify microflow AssetManagement.Asset_DeleteRosters: this change cannot be spliced into the stored flow … [MDL-V1-REBUILD]`; check flagged the same rule for 5 other flows but missed this one; earlier statements stay applied (capture 07).
7. `create external entities` creates navigation associations only between entities in the same target module; cross-module navigations are silently omitted. A second external entity on the same set in another module passes mxcli and fails `CE6609 "External entity with the same remote source already exists."`
8. `describe consumed odata service` prints `MetadataUrl: 'file:///<lab>/web-assets/AssetsApp/core-metadata.xml'` after `MetadataUrl: 'core-metadata.xml'` — an absolute local path shown (possibly stored) in the model.
9. Confirmed again (increment 5 #1): combo box `Attribute:` on an association passes `check`, exec refuses.

Not mxcli: the Mendix password policy kills boot when an after-startup account create fails (capture 03); trial licence session cap (`Maximum number of sessions exceeded!`) after ~10 logins (capture 21).

## Skill feedback — `skills/decompose-app.md` (first real use)

1. **Missing (Stage 5): replacing a stub by an external entity, and the one-module rule.** Drop the stub and create the external entity under the same qualified name so pages and flows rebind by name — but `drop entity` silently deletes cross-module associations, and navigations exist only within one consumer module (defect 7). Recipe order: drop owned associations → drop entities → `create external entities` into one module → re-create slice-owned associations → rewire by name (`slice-core-regroup.mdl`).
2. **Missing (Stage 2/5): the cross-app join.** The owner publishes its mirror of the slice entity keyed by the slice's key (`MonoAsset`, SystemID); the consumer filters `[Ticket_Asset/MonoAsset/SystemID = $Asset/SystemID]` (capture 19). Writes upsert the mirror (dual-owner hand-off). `mx check` catches some cross-app XPaths (CE0161) and passes others silently (database-grid columns).
3. **Wrong in practice (Stage 5 keys).** Prefer an added `PublicID: AutoNumber default 1` — accepted as key without a unique rule (capture 02), never fails a commit. Put a unique rule on an existing attribute only when every create path fills it. `default 1` is mandatory (MDL023/CE7247). On FSM, 9 of 10 core entities had no safe existing candidate.
4. **Missing (Stage 2): out-edges no service can carry.** Access-rule XPath into far-side entities (16 rows) — pre-check by grepping the slice's access rules for paths into other modules; decide local owner entity / REST-fed copy / hand-off before cutting.
5. **Misleading (Stage 6 level 2).** Add "…or handed off with a written reason when external entities cannot carry it (XPath, aggregates), counted separately from stubs"; Stage 4 gains resolution kinds `rest`, `page-odata`, `local-owner`.
6. **Missing (Stage 5 errors).** OData-backed widgets on a page have no error path; with the owner down the page is unusable (capture 21). Mitigations: lazy tabs, REST-fed copies for pages that must survive an outage.
7. **Wrong for 11.x (consumer config).** Use `HeadersMicroflow:`, not `ConfigurationMicroflow:` (CE6808); add defects 4 and 5 to the traps list.
8. **Incomplete (traps).** `mxcli new` 11.x apps are MPR v2 — back up `<app>.mpr` **and** `mprcontents/`.
9. **Missing (Stage 5 security).** API account passwords must meet the Mendix password policy (a failing after-startup create kills the boot); a `__SET_ME__` sentinel needs a guard where code acts on it.
10. **Missing (Stage 5 writes).** `yyyy-MM-dd` strings shifted by the runtime timezone (`2026-10-11T22:00:00Z`); send DateTime as UTC ISO or agree a date-only convention.

## API skill evaluation

| Skill | Helped? | Wrong/missing for OData + REST between two Mendix apps | Recommendation |
|---|---|---|---|
| `rest-integration-first-time-right.md` | Little ("URL as one string, explicit error path, log ladder" matched) | Scope is consuming a third-party REST API via JSON structure + import mapping; between Mendix apps neither is needed (primitive query params, String result). Nothing on publishing, keys, auth roles, external entities. | **(b)** new skill; fine for its own shape |
| `security-is-not-a-later-script.md` | Yes (predicted CE2729, capture 13; `DESCRIBE USER ROLE` caught unmapped roles) | Nothing on machine roles for published services (401 vs 404), grants for external entities, or a module role granted on another module's entity (`CE0007 "Please re-select module roles."`, capture 08) | **(a)** patch: short "service access" section pointing to the new skill |
| `learned-constants-and-secrets.md` | Yes (sentinel `__SET_ME__`, local store) | A sentinel needs a guard where code acts on it; one secret in two apps' stores; password policy for API accounts (capture 03) | **(a)** patch |
| `architecture-blueprint.md` §6c | No (three questions) | No key choice, versioning, error contract, ownership/dual write, external-entity limits, join pattern | **(b)**, §6c points at it |

**Recommendation: new skill `skills/mendix-service-seam.md`** — pattern / anti-pattern catalogue for OData + REST between Mendix apps:

- P1 Key: add `PublicID: AutoNumber default 1` (01, 02). *Anti:* unique rule on an attribute some flow leaves empty.
- P2 Machine role only on both services: 200 machine / 401 anonymous / 404 human (19).
- P3 REST action, primitive query params, String result, no mappings (19).
- P4 REST error handler `on error without rollback` + log + user message. *Anti:* OData widgets on a page have no error path (21).
- P5 Cross-app join via a published mirror keyed by the consumer's key (19). *Anti:* XPath over local ↔ external (CE0161, 08).
- P6 One consumer module per service where navigations are needed (09; CE6609 in 08).
- P7 Delete through the owner's own delete flow so side effects remain.
- P8 Enumerations arrive as `Edm.String`: consumers compare strings.
- P9 Dates: UTC ISO or an agreed date-only convention (19). *Anti:* zone-less date strings.
- P10 Versioning: a new published attribute is a contract change — version the path.
- P11 Secrets: sentinel default plus guard; API password meets the policy (03).
- P12 Consumer config on 11.x: `HeadersMicroflow`, not `ConfigurationMicroflow` (CE6808, 12).
- P13 Ownership: a slice-owned association to an external entity loses its delete cascade — orphan hand-off.

## Still unmeasured

- The REST error path at runtime (outage probe stopped at the page's error dialogs and the trial session cap).
- Tickets, contacts and SLA with real monolith data (grids rendered empty; `Asset_GetRelevantSLA` never ran).
- `SelectedTool_GetSelectableToolList`'s in-memory filter on an association to an external WorkOrder, at runtime.
- The `TechnicianLink` UI and the Mechanic "My" rules at runtime.
- Monolith in-edges: still 499 hand-off rows (level 3); the monolith's own Technician_Warehouse is now a second owner.
- Paging and latency under load; token auth and TLS; data migration (out of scope); a 9.24 monolith.
- No `tests/wave2` fixture for the new rules (`cut-ledger.sh` unchanged).
