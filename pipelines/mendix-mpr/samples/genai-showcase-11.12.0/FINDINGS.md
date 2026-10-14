# Rehost increment 2 — GenAI Showcase App (Mendix 11.12.0) — findings

Run 4 of `pipelines/mendix-mpr/rehost-extract.sh` (commit a1b59bc), 2026-10-12 07:16–07:52 UTC, mxcli
v0.26.0, Linux cloud container, no Studio Pro. Source: github.com/mendix/genai-showcase-app,
`GenAI Showcase App.mpr`. Target: `mxcli new GenAITarget --version 11.12.0` plus 5 marketplace modules
and 8 widget MPKs installed beforehand (see `CAPTURE.txt`). 36 modules regenerated: the 32 own modules,
plus 4 marketplace modules that cannot be installed into 11 (OpenAIConnector, PgVectorKnowledgeBase and
AmazonBedrockConnector are Mendix 9-built MPKs; ConversationalUI 1.5.1 is no longer on the Marketplace).

**One-line result:** 850 of 2776 catalog documents landed (579 identical on the target's describe,
271 drifted), 1993 failed, 43 not emitted. 7 of the 36 modules are missing from the target entirely
because of an extractor defect (E1/E2 below). The model would not load until 3 microflows were
re-executed; after that, `mx check` gives 14 errors (all CE1613), and mxbuild gives `BUILD FAILED`.

## 1. Ledger totals (`fidelity-ledger.tsv`)

Denominator: 2776 describable documents in the source catalog for the 36 modules (2733 covered by
rows, 43 listed as not-emitted). There are 2892 rows, because app-level and module-role rows come on top.

| verdict | all 36 modules | 29 modules that landed | 7 modules dropped (E2) |
|---|---:|---:|---:|
| emitted-identical | 579 | 579 | 0 |
| emitted-drift | 271 | 271 | 0 |
| failed-exec | 1993 | 473 | 1520 |
| not-emitted | 43 | 15 | 28 |
| not-expressible | 4 | 4 | 0 |
| target-extra | 2 | 2 | 0 |

The 7 dropped modules are AgentCommons, AmazonBedrockConnector, ComputerUse_AmazonBedrock,
ConversationalUI, MCPClient_ConnectToServer, MxGenAIConnector and OpenAIConnector. In the 29 modules
that did land, 850 of 1344 rows landed (63 %) and 579 are identical (43 %).

**Statements.** The 36 source scripts hold 3659 `create/grant/revoke/alter` statements. 1564 distinct
statements were deferred and never executed (`mdl/<M>.deferred.mdl`). A further 1040 were dropped
without a trace: they are the unexecuted remainder of the 7 modules (E2). Per module, distinct
statements deferred are:
AgentCommons 445, ConversationalUI 146, OpenAIConnector 78, AmazonBedrockConnector 75,
MultiAgentPatterns 69, RAG_Knowledgebase_AmazonBedrock 66, Embeddings_SemanticSearchMultiColumn 62,
MxGenAIConnector 53, General 52, Mistral/GoogleGemini 48 each, ExampleMicroflows 41, Embeddings_RAG 41,
MCPClient_ConnectToServer 38, Embeddings_Clustering 33, ChatCompletions_FunctionCalling 31,
Embeddings_SemanticSearch 27, ChatCompletions_ProductDescription 26, ChatCompletions_ConversationalUI 26,
PgVectorKnowledgeBase 24, AgentEditorCommons 24, EchoConnector 21, ChatCompletions_DocumentChat 16,
MCPServer_ExposeToolsPrompts 13, 8 or fewer in each of the other 10 modules, and 0 in MCPServer and AgentEditor.
**The `N statement(s) never executed` lines in `run-log.txt` overstate these counts by 7×** (E3).

## 2. Gates

- **`mx check` on the target as run 4 left it: the model does not load.**
  `System.ArgumentNullException: Value cannot be null. (Parameter 'value') at
  Mendix.Modeler.DataTypes.EntityType.set_EntityId` — "An error occurred when trying to set the 'Entity'
  property of a Object type in a Microflow". mxcli wrote 3 microflows whose `import from mapping` result
  type had a null entity: Embeddings_SemanticSearch.Book_CreateDatasetIfNeeded,
  AgentEditorCommons.ConsumedMCPService_CreateUpdate and
  Embeddings_SemanticSearchMultiColumn.TicketList_GetCreateDataset. They were found by a BSON scan of
  every `mprcontents/*.mxunit` for an `ObjectType` without an `Entity`.
  - Repair: re-executing the 3 statements with `create or modify` was refused (`MDL-V1-REBUILD`: "the
    If … changes where its paths end or meet"). `drop microflow X;` followed by the source
    `create or modify microflow X` in one script went through, and the scan then found 0 null entities.
- **`mx check` after the repair: 14 errors, all `CE1613`** (`mx-check-target.txt` §2):
  - 7 come from a Java action type parameter written as entity `.Entity` / `.ContextObject` (M3).
  - 4 are export mappings that do not exist (EM_MCPServer_Ticket, EM_FunctionCalling_Ticket). Message
    definitions cannot be expressed (N1).
  - 2 are `sort … by Similarity` on an inherited attribute, written against the specialization (M4).
  - 1 is ConversationalUI.ChatContext, missing because ConversationalUI was dropped (E2).
- **mxbuild `--target=deploy`: `BUILD FAILED`**, exit 3, with the same 14 errors (`mxbuild-target.txt`).
- Structural diff (`mxcli diff --format struct`): not run. The ledger already shows where the target
  differs.

## 3. Failure classes

### Extractor (toolkit) defects. These cause most of the loss.
- **E1. `lib/quarantine-mdl.py` cannot map two of `check`'s error forms.** In both cases it moves 0
  statements and `check_exec` gives up on the module:
  - (a) lint errors that name the document only on the next line:
    `✗ merge shared1: nothing joins it. [MDL-FLOW02]` / `at OpenAIConnector.EmbeddingsRequestMapping_POST`.
  - (b) `statement N:` numbers that the toolkit's split does not reproduce. `lib/mdlsplit.py` finds
    fewer statements than mxcli: AgentCommons 48 vs `Syntax OK (49 statements)`, AmazonBedrockConnector
    357 vs 360, MxGenAIConnector 135 vs 144, ComputerUse_AmazonBedrock 13 vs 14. A number past the end
    maps to nothing. A number in the middle can quarantine the **wrong** statement.
- **E2. When nothing can be quarantined, the rest of the module is silently dropped.** `check_exec`
  returns 1 and leaves the remainder in `<M>.ordered.mdl`. It is never moved to `<M>.deferred.mdl` and
  never retried. Because `check` is all-or-nothing, nothing of the module ran at all, not even
  `create module`. This hit 7 modules, 1040 statements and 1520 ledger rows. The ledger only says
  `absent from target describe`. The quarantine docstring promises "never a silent drop", and that is
  not what happens.
- **E3. Deferred bookkeeping compounds on every pass.** Each retry wraps the previous `-- deferred:`
  comment in a new one: `-- deferred: check rejected this statement (-- deferred: check rejected …`. The
  per-statement reason is garbled, and the `never executed` count (which counts comment lines) is 7× the
  number of distinct statements (GenAICommons: 35 logged, 5 real).
- **E4. Topo order let 3 flows run before the import mapping they use.** mxcli then wrote a unit that
  cannot be loaded (M1), instead of refusing it.

### mxcli emitter/exec defects (verbatim, one example each)
- **M1.** exec writes a microflow whose `import from mapping` result has a null entity. `mx check` and
  mxbuild then cannot open the `.mpr` at all (see §2). 3 units.
- **M2. `describe java action` puts the parameter comma after the `--` comment.**
  `Name: String not null  -- This sets the Name of the tool...,` → `mismatched input 'Name' expecting ')'`.
  It affected every module with Java actions. `lib/fix-describe-output.py` works around it.
- **M3. A Java action type parameter is described as `MxObject: "Entity"`, with no type-parameter
  declaration.** exec writes entity `.Entity`, and mx check reports `CE1613 "The selected entity
  '.Entity' no longer exists." at Java action parameter 'MxObject'`. 7 build errors. The same defect
  was seen for JS actions in increment 3.
- **M4. A sort on an inherited attribute is qualified with the specialization:**
  `CE1613 "The selected attribute 'Embeddings_SemanticSearch.BookChunk.Similarity' no longer exists." at
  List operation activity 'Sort'`. The ledger rates the flow `emitted-identical`, because the describe
  round trip is identical. 2 build errors.
- **M5. Rules can be neither described nor created** (`describe rule` → `Unknown type: rule`). There are
  12 rules in the regenerated modules, and they are not in the ledger denominator either. 8 microflows
  in the landed modules failed exec on `if condition calls 'PgVectorKnowledgeBase.Rule_DatabaseConfiguration_IsConfigured(...)',
  which is not a rule in this project`.
- **M6. describe emits MDL that mxcli's own `check` rejects.** Distinct (document, code) pairs:
  MDL-PAGEARG01 11 (`argument Task: $Task cannot be stored — widget actionButton17 is not inside a data
  view`), MDL-WIDGET24 10 (`ContentParams parameter {1} is written as "$ChatContext/Topic"`),
  MDL-WIDGET37 4 (switch `onClick:` with no slot), MDL-FLOW02 3 (`merge shared1: nothing joins it`),
  MDL-WIDGET22 2, and 1 each of MDL081 (`layout 'ConversationalUI.Layout_MasterBase' declares no
  placeholders at all`), MDL084 (`raise error;` outside an ON ERROR handler), MDL-WIDGET18/42
  (`DecimalPrecision must be a non-negative integer, got &{-1}`), MDL003, MDL-WIDGET43 and MDL-WIDGET03.
  In total, 30 documents.
- **M7. One flow fails validation after describe:** `microflow 'GenAICommons.Span_CalculateSumDurationUntilExecution'
  has validation errors: - variable 'SumDuration' is not declared`.
- **M8. Same-name microflow and Java action:** when the flow is created first, exec fails with
  `could not look up Java action … refusing to write unit …: attribute reference not qualified`. Topo
  works around it.
- **M9. A grant that names an association member before the association exists:**
  `entity EchoConnector.Credentials has no member(s) Credentials_Configuration; grant only names
  members of the entity`. Topo works around it.
- **M10. exec refuses forward references even inside one script**, so mutual recursion cannot be
  created: `references microflow X before it is created`. In GenAICommons,
  Response_CallRecursively ↔ ChatCompletions_WithHistory stay deferred, and so does every caller of
  ChatCompletions_WithHistory (EchoConnector, the provider connectors, the showcase modules).
- **M11. `-c describe module … with all` silently truncates at 10 000 lines, and `with all` omits
  nanoflows, snippets, JS actions, JSON structures, mappings, task queues, image collections and some
  pages.** The extractor fills these in.

### Not expressible in MDL (mxcli 0.26.0)
- **N1. Message definitions** — **CORRECTED 2026-10-12: not a defect.** `create message definition collection` and `describe message definition collection` work on 0.26.0 and an export mapping on one checks and executes (blank 11.13.0 app, staged issue U8 withdrawn). The run failed because the collection was never emitted before the mapping; the extractor's tree fill-in must include it. Original note: `export mapping GenAICommons.EM_Reference:
  message definition "GenAICommons.MD_Reference.Reference" not found — this project has no message
  definitions`. Every export mapping built on one fails (EM_Reference, EM_MCPServer_Ticket,
  EM_FunctionCalling_Ticket), and so does every flow that exports with it (4 build errors).
- **N2. Widgets marked `NOT re-executable`:** `Forms$FileManager` on ChatCompletions_DocumentChat.Document_Upload.
- **N3. App-level hand-offs:** demo users (`Password: '***'`), project security (a report, not MDL)
  and the theme. These are the 3 `(app)` not-expressible rows.
- **N4. Merges and decisions (#923)** show up as layout drift: of 271 drift rows, about 190 are microflow
  bodies. Typical diffs are `'@curve(from: (15, 0), to: (-30, 0))' -> "@caption 'empty'"` and
  `'@curve(...)' -> '@anchor(true: (to: top))'`. Java action drift is `-- return NAME: 'X'` → `'ReturnValueName'`
  and `export level api`. The rest is documentation whitespace and grant counts.
- **N5. Rules** (M5).

### Ordering / cascade, in the 473 failed-exec rows of the 29 landed modules
Each document was attributed to the first error that names it:
- 167 reference a document of one of the 7 dropped modules (`microflow not found:
  OpenAIConnector.ApiKey_GetCreate_Configuration`).
- 154 are the same-module closure of a deferred statement, so no error names them directly.
- 122 reference another deferred document. This includes the M10 cycle.
- 10 failed exec validation (M5 ×8, M7, 1 missing callee).
- 15 hit an M6 lint, 3 hit N1, and 3 are the M10 cycle named directly.

### Marketplace gaps (before the run, `CAPTURE.txt`)
- 3 Mendix 9-built MPKs refuse to install into 11: `mx module-import failed: exit status 117 … created
  with version 9.24.2 … open it in any version in the range from 10.21.0 to 10.24.99 first`.
- ConversationalUI 1.5.1: `version "1.5.1" not found` (the oldest version listed is 3.0.0).
- The blank template's 7 modules have the wrong versions (Administration 4.3.2 vs 4.5.0, Atlas_Core
  4.1.3 vs 3.19.0, …). Installing a module that is already present is "NOT done automatically", so these
  are hand-off rows.

## 4. Timings (`timings.tsv`, run 4)
- Wall time was 36 min (07:16–07:52). The source describes were reused from run 1 (`REHOST_REUSE_MDL=1`);
  they cost 865 s (14.4 min) for the 36 modules in the probe, and 30 min with fill-in in run 1.
- The first check/exec pass took 847 s summed over modules. The slowest were AgentCommons 103 s,
  OpenAIConnector 98 s, MxGenAIConnector 89 s, AmazonBedrockConnector 67 s, GenAICommons 56 s and
  ConversationalUI 51 s.
- The target describes took 102 s and topo took 37 s. The remaining ~19 min went to the pre-step captures, the 6 deferred-retry passes and the ledger (not timed separately).
- After the run: `mx check` 6–8 s, mxbuild 13 s (fails fast on errors).

## 5. Done-criterion verdict for Rehost at this size
- **"Builds clean" was not reached, and it is not reachable with mxcli 0.26.0 plus the toolkit alone.**
  - Even in the 29 modules that landed, 7 of the 14 build errors come from a Java action type parameter
    that mxcli cannot express (M3), and 4 come from message definitions (N1).
  - The 7 dropped modules (E2) will add more of the same once E1/E2 are fixed: ConversationalUI and
    AgentCommons carry most of the pages and widgets.
  - It becomes reachable only as **build-green with hand-offs**: fix E1–E4 in the extractor, then
    record every M3/N1/M5 document as a ledger hand-off row that is fixed by hand in Studio Pro (Java
    action type parameters, message definitions, 12 rules).
  - Even then, a describe-identical document can still fail the build (M4). So the build gate, not the
    ledger, decides.
- **Regression parity headlessly: confirmed NOT reachable.** The previous worker's conclusion holds.
  - Message definitions, rules, the FileManager widget, demo-user passwords and project security
    cannot be regenerated.
  - Mutual recursion cannot be created (M10).
  - The showcase's behaviour needs live LLM provider credentials that a headless run does not have.
- **Recommendation (ASSUMED, for the user to confirm):** for Rehost of a whole app, "done" is
  build-green: `mx check` 0 and `BUILD SUCCEEDED`, every ledger row either landed or a named hand-off,
  and the hand-off count is the measure. Regression parity is a separate, human-run level, not a
  Rehost gate.

## 6. Still unmeasured
- The 7 dropped modules. Their real failure mix is unknown until E1/E2 are fixed and the run is
  repeated.
- The structural diff (`mxcli diff --format struct`) per module.
- Runtime behaviour. The app was never started, and no journey was run.
- The time to repair the 14 build errors by hand in Studio Pro.
- Whether the remaining 1564 deferred statements land once the 7 modules exist (cascade vs. root cause).
