# Increment 3 — NativeNote slice out of FSM into Mendix 11.13 (2026-10-12)

**Result: build-green.** `NativeNote` moved by MPK into a fresh Mendix 11.13.0 app, every crossing
edge accounted for in MDL. Route: FSM 9.24.2 copy → `mx convert` 10.24 → `export-module-mpk.py` →
`marketplace install --file` → edge scripts (`mdl/`) → `mx check` 0 → mxbuild `BUILD SUCCEEDED`.
Captures are numbered in `captures/`; `CAPTURE.txt` is the manifest. Credit: a public Marketplace template (FSM).

## Gates (verbatim)

| Gate | Result | Capture |
|---|---|---|
| `mx check` 11.13 | `The app contains: 0 errors.` (112 CE1613 after installs → 1 CE0115 after first edge pass → 0) | 21 |
| mxbuild 11.13.0 `--target=deploy` | `BUILD SUCCEEDED`, 18.7 s (first build FAILED on Utils' three known Java hand-offs) | 24 |
| Package self-check (9.24 `mx check` on the package's `project.mpr`) | `The project contains: 186 errors.` — all CE1613, all naming modules outside the package; 0 format errors | 05 |
| Fidelity | 66/66 NativeNote documents `emitted-identical` between 10.24 source and 11.13 target (31 from `with all` + 35 nanoflows described one by one) | — |
| Exporter | crossing-edge list identical on the 9.24 copy and the 10.24 copy | — |

## Cut ledger — 308 rows, 0 unresolved, from 346 catalog refs (`cut-ledger.tsv`)

| Direction | resolved | stub | handoff | retire | platform |
|---|---|---|---|---|---|
| out (70) | 37 | 26 | 4 | – | 3 |
| in (238) | 129 (generic offline-action base copied; monolith keeps its own) | – | 94 | 15 (NativeModelCheck) | – |

Out-rows include 2 names only `mx check` saw (App events widget action, icon images) and 13 rows the
catalog does not hold (Utils' own edges, the Java edits, app settings, security).

**Stubs that carry behaviour — these are not resolutions, the stub count is the progress measure:**
- `Synchronization.Synchronize` is empty: offline note actions are created on the device but never pushed.
- `NativeWorkOrder`, `NativeTicket`, `NativeTechnician` are empty local stubs. The monolith syncs them to
  the device, and an offline profile cannot sync external entities → this seam needs REST-fed copies, not OData.
- Loading pages not shown. `JS_GetOriginalValue`'s generic parameter narrowed to `NativeNote.NativeNote`.
- `Administration.Account_NativeTechnician` added to a Marketplace module — an Administration update removes it.
- The two native layouts lost their SafeAreaView wrapper.
- Security is Off in the starter (source: Production, 8 user roles); new module roles mapped to no user role.

## Decision: the target is a Marketplace starter, not `mxcli new`

`mxcli new` worked but a web-only app cannot hold this slice: every nanoflow `show page` of a native
page fails CE6081 and mxcli cannot create a native navigation profile. Target switched to **Blank
Native Mobile App 11.13.0** (Marketplace id 109511) via `marketplace download` + `mx create-project`
(absolute `--output-dir` only — relative fails with `UriFormatException`). Same MPK+MDL route.

## Timings

| Step | s | Step | s |
|---|---|---|---|
| copy | 0.9 | CommunityCommons install | 15 |
| graph-report | 21 | ValidationFeedback install | 10 |
| describe with all | 16 | Utils `install --file` | 7 |
| export | 0.3 | NativeNote `install --file` | 9 |
| `mx convert` (6 errors, 241 warnings) | 35 | exec edge scripts (total) | 9.4 |
| package check | 3.7 | `mx check` | ~9 |
| starter download | 20 | mxbuild | ~18.5 |
| create-project | 12 | cut-ledger | 0.15 |
| describe 35 nanoflows | 41 | | |

## mxcli defects (filed in `contrib/inbox/2026-10-12-increment-3-nativenote-findings.md`)

1. `describe javascript action` emits `Name<Entity>(Entity: "Entity" …)` → `check`: `mismatched input '<'`; a
   type-parameter object cannot be expressed (`Entity: Entity` → entity `.Entity`; `entity <Entity>` passes exec, CE0115 at caller).
2. Native layout with SafeAreaView: `describe layout` emits `content { }` → exec `content needs a name`; after
   `widget init` → `declares no placeholder at all` (placeholders inside a pluggable-widget slot unseen).
3. exec pre-check does not see an image collection created earlier in the same script → refuses the whole script.
4. exec is not atomic: a later error left 18 statements already written.
5. Re-exec of a JS action rewrites a hand-restored `.js`; the EXTRA CODE import (`import {Platform} from "react-native"`) is only a comment in describe output.
6. No native navigation profile can be created.
7. Commands without `-p` silently pick any `.mpr` in the working directory.
8. `with all` omits all 35 nanoflows.
9. Possible: `index ( desc);` emitted with no column (untested).

## Toolkit changes in commit 0399695

- **New `bin/cut-ledger.sh`** (engine `bin/lib/cut-ledger.py`): document-level edges from the mxcli catalog +
  check-log names the catalog misses + extra rows; applies `cut-rules.tsv`; exits 1 while any edge is unresolved.
  Ran on this slice; `--refs` mode rebuilds the identical ledger from `crossing-refs.tsv`. **No `tests/wave2` fixture yet.**
- `export-module-mpk.py`: crossing refs need a name boundary (`Note×54`, `Technician×2` were substrings of
  `NativeNote.`/`NativeTechnician.`); Utils' list unchanged, package database byte-identical.
- Not fixed, left for a quiet tree: `lib/topo-order-mdl.py` cannot order an entity whose after-commit microflow
  takes that entity, nor a grant naming an association created later (both hand-fixed in `mdl/edges-B.mdl`);
  `rehost-extract.sh` timing code uses `date +%s.%N`/`bc` (not on macOS).

## Monolith side — documented only, the copy carries only the conversion

1. Publish REST on the slice: NativeNote/NativeImage upsert + delete; uploaded OfflineNoteAction/OfflineImageAction.
2. Replace the server-side push in `Synchronization` with calls to that service: `Note_ProcessUpdatingNativeNote`,
   `Note_UpdateNativeNote`, `NoteImage_ProcessUpdatingNativeImage`, `NoteImage_UpdateNativeNoteImage`,
   `NativeNoteList_AddAndSynchronize`, `NativeNoteList_Synchronize_Initial`, `NativeImageList_AddAndSynchronize`,
   `NativeImageList_Synchronize_Initial`, `Rule_Note_HasChanged`.
3. Feed `OfflineNoteAction_Process/_Validate/_NewNote/_UpdateNote` and `OfflineImageAction_Process/_Validate` from the slice.
4. Rewire deletes to a REST delete: `Note.NoteList_Delete`, `Note.ImageList_Delete`, the two Form delete flows.
5. Keep the MasterData admin page (`Note_NewEdit_MxAdmin` + 3 flows) reading/writing through the slice's service.
6. The 33 native in-edges (NativeMobile, NativeMobileRelated, NativeMobileForm, NativeTechnician): co-locate in
   the Mobile app (next slice: NativeTechnician) or deep-link.
7. Retire NativeModelCheck; move the NativeNote cleanup in `General.TurnSoftDeleteToHard` to a scheduled event in the slice.
8. Drop the NativeNote lines from the NativePhone sync profile, then delete the module.

## Still unmeasured

The app was never started: no runtime test, no cross-app journey, no offline sync, security Off, seam
services do not exist yet, data migration of existing NativeNote rows not measured.

## Recommended done-criterion for a slice (three levels; every slice report names the level reached)

1. **Build-green** (reached here): 0 unresolved ledger rows, `mx check` 0, `BUILD SUCCEEDED`, moved documents describe-identical.
2. **Seam-live**: every behaviour-carrying stub replaced by a working REST call; security Production with roles mapped.
3. **Strangled**: monolith in-edges rewired, one journey per crossing edge passes, module deleted from the monolith.

Calling level 1 "done" would hide 26 stubs.
