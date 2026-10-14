# Increment 4: the first seam call between the FSM monolith and the NativeNote slice (2026-10-12)

**Result: one record crossed.** A `Note.Note` created in the FSM monolith was pushed over REST and
landed as a `NativeNote.NativeNote` in the Mendix 11.13 slice's database. The monolith no longer
writes its own copy. **The call ran from the 10.24 copy of the monolith, not from 9.24.**

The 9.24.2 runtime does start headless, but mxcli 0.26 cannot write the consuming microflow into a
9.24 project (see "Why 10.24"). Both apps ran locally on HSQLDB. Captures are in `captures/`, the
scripts that ran are in `mdl/`, and `CAPTURE.txt` lists versions and files.
Credit: a public Marketplace template (FSM).

## The proof (verbatim, `captures/12-call.txt`, `captures/13-proof.txt`)

Monolith runtime log (Mendix 10.24.0):
```
2026-10-12 08:43:56.043 INFO - SeamProbe: slice answered: created seam-20261012084355
```
Slice database (Mendix 11.13.0), `mxcli oql --direct --port 8290`:
```
| Description                 | ShouldBeSynced | SystemID            | Title           | NrOfPictures |
|-----------------------------|----------------|---------------------|-----------------|--------------|
| created in the FSM monolith | true           | seam-20261012084355 | Seam probe note | 0            |
(1 rows)
```
The monolith holds the `Note.Note` with that SystemID, and `SELECT … FROM NativeNote.NativeNote`
returns `(0 rows)`. A second POST with the same SystemID answered `updated seam-20261012084355`,
and the slice still held `count = 1`, so the endpoint upserts.

## Why 10.24 and not 9.24 (each step verbatim in captures 01–05)

| Step on the 9.24.2 copy | Outcome |
|---|---|
| `mxcli run --local --db-type hsqldb` (JAVA_HOME = JDK 17) | FAILED after 77 s. mxcli launched mxbuild's Gradle 7.6 on JDK 21: `Unsupported class file major version 65`. A 9.24 model has no JavaVersion setting: `alter settings runtime ( JavaVersion: '17' )` answers `Unchanged model settings`. |
| `mxbuild --java-home=<jdk17> --target=deploy` (run directly) | `BUILD SUCCEEDED`, 90 s |
| Runtime on JDK 17 | `Incompatible java version: 17.0.20.1 … Java 11 is required.` |
| Runtime on JDK 11 (apt, 8 s), started by hand through M2EE | First attempt: `Could not find value for constant 'MendixSSO.TokenEncryptionKey'`. With all 47 constants passed: `Mendix Runtime successfully started` 10 s after `start`, including 2378 DDL commands on an empty HSQLDB. |
| `mxcli` create of any microflow (even an empty one) | `this Mendix 9.24.2 project cannot store Microflows$Microflow.StableId (Mendix 10.2.0+); Microflows$SequenceFlow.CaseValues (Mendix 10.15.0+)` |
| `mxcli` `alter microflow` (insert or replace an activity) | `cannot store Microflows$SequenceFlow.CaseValues (Mendix 10.15.0+)` |

**What this means for the user's question (can Mx 9 integrate with an Mx 11 app):**

- **At runtime: yes, as far as measured.** The 9.24 runtime boots headless, and the seam is plain
  HTTP with nothing tied to a Mendix version. The 10.24 → 11.13 call worked unchanged.
- **Authoring with mxcli 0.26: no.** It cannot add even one activity to a 9.24 microflow. Two ways
  to put the consuming call into a 9.24 monolith:
  - hand it to a developer in Studio Pro 9.24 (one activity, shown in `captures/11-consumer.mdl`);
  - upgrade the monolith to 10.24 first. Every later monolith-side rewiring also needs authoring.
- A 9.24 runtime calling the slice was **not** measured.

The mxcli refusal is correct. Writing those properties would produce a file Studio Pro 9.24
cannot open. The gap is that mxcli has no 9.x serialisation for new flows.

## Protocol: published REST, query parameters, no mappings

- **Slice:** `NativeNote.SeamNoteAPI`, `POST rest/seam/v1/notes`, `Authentication: none`, backed
  by `NativeNote.SeamAPI_UpsertNote(SystemID, Title, Description, NrOfPictures)`. It retrieves the
  note by SystemID (`first`), creates it if missing, sets the fields and commits.
  - REST publishing can be written headlessly (`create published rest service`), so OData was not
    needed.
  - Primitive parameters become query parameters. That avoids writing JSON structures and
    import/export mappings, which this probe did not try headlessly.
- **Monolith:** `alter microflow Synchronization.Note_ProcessUpdatingNativeNote` replaces
  `call microflow NativeNote.NativeNote_Save(...)` with `call rest service post '{1}/rest/seam/v1/notes?…'`
  plus a log line. The base URL is a new constant, `Synchronization.NoteSliceBaseUrl`.
  - Callers are unchanged: `Note.Note_Commit` → `Note_UpdateNativeNote` → `Note_ProcessUpdatingNativeNote`.
  - A `create or modify` of `Note_UpdateNativeNote` was refused (`MDL-V1-REBUILD`: its decision
    still uses `$NativeNote`), and ALTER cannot replace a decision. So the replacement sits one
    level down, at the actual write.
- **Trigger (probe only, not part of the seam):** an insert into `General.ASU_General` creates one
  Note at startup and commits it through `Note.Note_Commit`. A new microflow behind a published
  trigger would also have worked on 10.24. The startup hook was chosen because it was first
  tried on 9.24, where no new microflow can be created.

## Steps and timings (wall clock, 08:18 → 08:50 UTC, about 32 min)

| Step | s |
|---|---|
| copy 9.24 app | 3.7 |
| `mxcli run` 9.24 (failed) | 77 |
| mxbuild 9.24 direct | 90 |
| JDK 11 install | 8 |
| 9.24 runtime start (M2EE, incl. DDL) | 10 |
| copy slice | 18 |
| slice exec (2nd/3rd run) | 0.5 |
| slice `mx check` | 10 |
| slice `mxcli run --detach` | 86 |
| mono 10.24 exec (`mono-consume.mdl`) | 6.0 |
| mono 10.24 `mx check` | 26 |
| `marketplace update` ×2 | 41 + 52 |
| `mxcli run` 10.24 (3 tries: Java compile ×2, then up) | 79 + 58 + 74 |
| the call itself (startup → slice answer) | < 1 |

**Making the 10.24 copy buildable cost more than the seam itself.** Increment 3 only converted it.
The fixes below are one-time and none touches the seam:

- NanoflowCommons 3.0.0 → 5.2.1 and NativeMobileResources 4.0.1 → 10.1.17 (CE4271).
- `mx update-widgets`: the updates left 27 × CE0463.
- One XPath in `Scheduler.Snippet_Appointment_Scheduling`/grid2 replaced by a same-length byte
  patch (CE0161). mxcli cannot author that widget. The data grid lost its TechnicianGroup filter.
- `JavaVersion: '21'` (CE2513).
- Custom `theme/web/index.html` removed (CE6911).
- Three Java edits:
  - generated parameters are `final` in 10.x, which breaks the user code of
    `objecthandling.deepClone` and `communitycommons.DeepClone`;
  - `rollbackTransAction()` → `rollbackTransaction()` in 3 files.

## mxcli defects (filed in `contrib/inbox/2026-10-12-increment-4-seam-probe-findings.md`)

1. **`mxcli run` cannot run a Mendix 9 app.** It resolves JDK 21 even with JAVA_HOME pointing at
   17, and mxbuild 9.24's Gradle then fails: `Unsupported class file major version 65`. The 9.24
   runtime needs Java 11.
   Repro: `JAVA_HOME=<jdk17> mxcli run --local --db-type hsqldb -p <9.24 app>`.
2. **No microflow can be created in a 9.x project** (StableId 10.2+, CaseValues 10.15+).
   Repro: `mxcli -p <9.24.mpr> -c "create microflow M.X () begin return; end;"`.
3. **`alter microflow` that adds any activity in a 9.x project is refused** (SequenceFlow.CaseValues).
   Repro: `alter microflow M.X { insert before return true begin log info node 'a' 'b'; end; };` on 9.24.
4. **`mxcli check` passes what exec then refuses for a version reason, and exec is not atomic.**
   The drop + create that `MDL-V1-REBUILD` itself recommends ran its `drop` and then failed on the
   `create`. That deleted `Synchronization.Note_UpdateNativeNote` from the 9.24 copy and left
   `mx check` with 2 × CE1613 (callers of a missing flow).
   Repro: `drop microflow M.X; create microflow M.X (…) …;` on 9.24.
5. **`mxcli check` accepts list operations on a list.** Under `mdl 1`, `retrieve $E from M.Ent where […] limit 1`
   yields a list, as documented. But check accepts `change $E (…)` and `if $E = empty` on that
   list, and `mx check` then reports 4 × `CE1613 "The selected attribute 'List of M.Ent.Attr' no longer exists."`.
6. **A stale list type survives a splice.** After changing `limit 1` to `first`, `create or modify`
   reported `spliced: 1 replaced` and describe shows `first`, but `mx check` still found the same 4
   CE1613. Only drop + create cleared them.
7. **`alter settings runtime ( JavaVersion: … )` on a 9.x model** prints `Unchanged model settings`
   without saying the property does not exist in that version.
8. **`marketplace update` leaves widget errors behind.** It ends without running or mentioning
   `mx update-widgets`, and the project is left with 27 × CE0463. It also warns
   `skipping com.mendix.widget.web.PopupMenu.mpk: package.xml: zip: checksum error` on both updates.

## Hand-off rows (recorded, not resolved)

| Row | State in the probe |
|---|---|
| Security | The slice endpoint has `Authentication: none` and slice security is Off. The monolith (Production security) calls from the After Startup system context. Seam-live needs basic or custom auth, a module role for the API, and the credential in a constant. |
| Failure coupling | The REST call has no `on error` handler, so a slice outage rolls back the monolith's Note commit. It needs `on error continue` plus a retry queue or `ShouldBeSynced` flag. |
| Payload | Associations are not sent (NativeWorkOrder, NativeTechnician; the slice stubs are empty). Query string only, so long descriptions are bounded by URL length. A JSON body with mappings is the seam-live form. |
| Base URL | `Synchronization.NoteSliceBaseUrl` defaults to `http://127.0.0.1:8280`. It is a per-environment constant. |
| Probe trigger | Remove the `ASU_General` insert before any real use. |
| 10.24 build fixes | The XPath byte patch drops a filter: redo it properly in Studio Pro. The 3 Java edits are ordinary 9 → 10 upgrade work. |

## Still unmeasured

- A 9.24 runtime calling the slice (blocked on authoring, above).
- Production security on either side.
- The other 8 push flows from increment 3 step 2: images, initial list sync, `Rule_Note_HasChanged`.
- Deletes, the reverse direction (offline actions from the slice to the monolith), and offline
  sync on a device.
- Latency and behaviour under load or under slice failure.
- Migration of existing NativeNote rows.
- The browser UI of either app: only the runtimes and REST were exercised.

## How far the remaining 25 stubs are from seam-live

**What this call cost:**

- The seam itself: 2 MDL scripts, about 7 s of exec, 0 hand edits.
- Wall clock was about 32 min. Most of it went on one-time work: the 9.24 dead end and the 10.24
  build fixes.
- The pattern is now proven at **monolith ALTER → slice published REST → upsert microflow**.

**Where the next stubs get harder:**

- **Straight-line pushes with primitive fields** (the remaining Note/Image pushes and deletes):
  each should take minutes on 10.24. Images need a binary or file body (`Body: BINARY`), which
  was not tried.
- **Object graphs** (NativeWorkOrder, NativeTicket, NativeTechnician copies): these need JSON
  structures and import/export mappings, which were not tried headlessly. They also need a
  decision on sync ownership (REST-fed copies, per increment 3).
- **The reverse direction** (offline actions fed from the slice): the monolith must publish, so
  the same 9.24 authoring blocker applies there.
- **Security Production on both sides:** not started, and a gate for seam-live.

**Overall:** the plumbing risk is retired. The open risks are:

- mxcli cannot write to 9.x projects;
- mappings have not been tried headlessly;
- security.

This one call took 1 of 26 stubs to a working REST call. That is level 2 (seam-live) for this stub
only, without security, so the slice as a whole is still at level 1, build-green.
