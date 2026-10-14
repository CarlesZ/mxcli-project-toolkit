# Build fix for the GenAI Showcase rehost target: `mx check` 42 -> 0, mxbuild FAILED -> BUILD SUCCEEDED

Run on 2026-10-14 with mxcli `nightly-80-gbd45c47e`, starting from the post-run target of `FINDINGS.md` with the N-2
snippet already replaced (the "unblocked" restore point). Work was done on a copy; the restore point and the source app
were not changed. The fix script is `build-fix.mdl` (this directory). Credit: mendix/genai-showcase-app; mendixlabs/mxcli nightly; MendixMau.

**Result.** Replayed from scratch (a fresh copy of the restore point, `build-fix.mdl`, then the steps below): `mx check` **0 errors** (was 42). mxbuild `--target=deploy`: **BUILD SUCCEEDED**, but only after three
steps that are not MDL (section 4). Without them the target stays at `mx check` 0 and mxbuild fails in `javac`.
The build is green with **11 stubbed microflows, 8 dropped mapping documents, 36 icon widgets removed and about 450 of the
482 failed-exec documents still absent** (nothing the build compiles refers to them). Section 5 is the hand-off list.

## 1. The 42 was a floor, not the total

`mx check` stops at the first error phase. With the 42 x CE1613 present it never reached the next phases, so fixing
them made the count go **up**, then down:

| step | `mx check` errors |
|---|---:|
| restore point, as measured again today | 42 (all CE1613) |
| Java action type parameters declared (14 actions) + markdown/Ticket/message-definition work | 115 |
| snippet/microflow/mapping fixes, in order | 78, 52, 44, 34, 33 |
| icon widgets removed, accordion + design-property resync (`mxcli fix`) | 2, then 0 |

The 115 were the CE1613 fixes plus everything behind them: 32 `No icon selected`, about 40 CE0115/CE0127 on callers (Java actions with a
declared type parameter, and `Request_Create`/`SpanTreeView_Create` with an omitted optional parameter), 17 CE0284, 6 CE0402, 4 CE0244, 3 CE0290,
3 CE5015, 3 CE0720, 3 CE7247 (my first markdown attempt), and single CE0224/CE0463/CE6087/CE8812 hits.
**A rehost "mx check = 14 / 42" figure is therefore a
lower bound** (`skills/rehost-app.md` Step 5 says "report the count"; this run says do not read it as the size of the job).

## 2. The five known classes

| class (errors) | MDL used | result |
|---|---|---|
| Java action type parameters (14, U7) | `create or modify java action M.A(ContextObjectType: ENTITY <ContextObject> not null, ...)` declares the type parameter (the only MDL form; it also adds a real parameter). Every caller then needs `ContextObjectType = <Entity>` (20 microflows; the entity is the type of the argument variable, `System.User` where the argument is `empty`) | fixed. Without the caller edit each of the 25 call sites gets CE0115 |
| export mappings on message definitions (5, N-1) | `create message definition collection` from `describe message definition collection` on the **source** (read-only), then the three export mappings | fixed, with two deviations: (a) `createdDate` is dropped from the definition and the mapping (a system attribute: check refuses `createdDate` and the writer cannot expose `CreatedDate`); (b) `ChatCompletions_FunctionCalling.MD_Ticket` is created as **`MD_FunctionCalling_Ticket`**, because a mapping resolves `MD_Ticket.Ticket` by the collection's bare name, so two collections named `MD_Ticket` in different modules cannot both be used (the second mapping is refused with "exposes <other module>.Ticket") |
| `ExampleMicroflows.Ticket` cycle (16) | order: `drop` the two mappings that exec accepted on the missing entity (N-3), create the entity **without** event handlers + its access rule, create `BDe_Ticket`, `BCo_Ticket`, the three other Ticket flows and both mappings, then `alter entity ... add event handler` x2 | fixed. All 6 flows and both mappings land |
| snippet call params (4, N-5) | `create or modify page AgentCommons.Version_Overview` from the source text with `Params: (Agent = $Agent, Version_InUse_Current = $Version_InUse_Current)` added to the snippet call; `'Align content'` written as `'Align content (deprecated)'` (CE6087) | fixed |
| Markdown viewer context (3, N-4) | no MDL form binds the widget's attribute to an ancestor data view (the source stores a `SourceVariable` naming the widget or snippet parameter; describe prints a bare attribute). `stringAttribute: GenAICommons.Trace.SystemPrompt` is accepted by the parser and then refused by check (CE7247). Fix: in `ConversationalUI.Trace_Agent_SlideIn` the three `markdown` widgets are **moved out of the CopyHelper data view into the Trace data view**, where the bare attribute resolves. In `Snippet_Message_Content` the markdown is wrapped in `dataview dvMessageContent (DataSource: $Message)` | fixed; layout change on the trace page: the markdown no longer sits inside the `text-container-clickable` wrapper with its copy button |
| the N-2 snippet | already replaced in the restore point | - |

## 3. Classes that were behind the 42 (found by fixing it)

| class | errors | MDL used | status |
|---|---:|---|---|
| optional microflow parameters (`IsRequired=false`, default stored) are described as `$ID: String`; callers omit them or pass the blank `= nothing` | 30 CE0115, 5 CE0127, 1 CE0117 | callers rewritten with the source default: `ID = empty` (`Request_Create`), `TraceID = empty` (`SpanTreeView_Create`), `IsOffset = false` (`SpanTreeView_CreateFromSpanForChartWithOffset`); 9 microflows, 6 of them dropped and recreated because exec refuses to splice a changed annotation or split | fixed. Defaults read from the source with `mxcli bson dump` |
| `image (ImageType: icon)` widgets: `imageIcon` is "recognized but not yet persisted" (MDL-WIDGET06) and the stored value is the wrong shape | 36 "No icon selected" | `alter snippet|page ... drop <image>`; the two snippets whose images sit in a list-view template are recreated without them | **hand-off**: 36 widgets in 20 documents lost their icon (source icon names are in the source, for example `Atlas_Core.Atlas.calendar-1`) |
| text template parameters `<unbound>` (snippet text outside a data context) | 6 CE0402 | `Snippet_TraceTokens` body wrapped in `dataview dvTrace (DataSource: $Trace)` | fixed |
| template parameters lost on `show page ... with title = '{1}'` and on a text box `Label: '{1}'` | 3 CE0720 | title parameter dropped (page's own title shows) in 2 `ACT_Reference_ShowSource`; label set to the literal `Argument value` in `Snippet_Prompt_Arguments` | **hand-off**: dynamic title/label lost |
| combo box bound to `Agent_Version_InUse` under a Version data view (source binds it to the enclosing Agent view) | 1 CE8812 | `alter page AgentCommons.Version_NewEdit { drop dataView2; insert into dataView3 {combobox ...} }` | fixed (wrapper data view removed) |
| widget definitions and design properties out of date after writing pages | 2 CE0463, 1 CE6087 | not MDL: `mxcli fix widgets`, `mxcli fix design-properties` (mxcli's own wrappers over `mx update-widgets`, MPR v2 preserved; run again after every page/snippet write) | fixed |
| mapping documents mxcli writes invalid: obtain-by-microflow arguments (`by M(P: parent)`), mapping parameters, converter value transforms | 17 CE0284, 2 CE0224, 4 CE0244, 3 CE0290, 3 CE5015 | no MDL form repairs them (`parent(1)` writes the same unit). 8 mappings dropped; the 11 call sites replaced (table below) | **hand-off** |
| `Agent_CallDocument_*` `Agent` parameter is a document reference; describe omits it | 2 CE0115 | `Agent = 'DEV_Development.Agent_ProductDescription'` / `'ChatCompletions_ProductDescription.Agent_ProductDescriptionGenerator'` (qualified name as string; an unquoted document name is CE0117) | fixed for the build; runtime unproven |

Stubbed call sites (each is the one statement replaced; the rest of the flow is intact):

| microflow | statement replaced by | lost |
|---|---|---|
| AmazonBedrockConnector.ImageOptions_InvokeModel_TitanImage | `declare $RequestBody String = ''` | Titan image request JSON |
| MxGenAIConnector.ChatCompletions_Execute_WithHistory | `declare $RequestBodyJSON String = ''` | **Converse request body: Mendix Cloud chat does not work** |
| OpenAIConnector.Request_ExportToJson | `declare $Request_Json String = ''` | **OpenAI request body: OpenAI chat does not work** |
| ChatCompletions_JsonModeDemoData.Car_GenerateRecords_GetUserPrompt | `declare $Json_ExistingCarData String = ''` | demo prompt data |
| Embeddings_Clustering.Cluster_GenerateUserPrompt | `declare $ClusterJSON String = ''` | clustering prompt data |
| MxGenAIConnector.ChunkCollection_PopulateCollection | `declare $RequestBody String = ''` | knowledge-base populate body |
| MxGenAIConnector.KnowledgeBaseChunkList_GetNearestNeighbors_ByVector | empty `list of GenAICommons.KnowledgeBaseChunk` | nearest-neighbour results |
| MxGenAIConnector.ChunkCollection_GetCohereEmbedResponse | `create GenAICommons.EmbeddingsResponse` | Cohere embeddings parse |
| AmazonBedrockConnector.ChunkCollection_GetCohereEmbedResponse | `create AmazonBedrockConnector.CohereEmbedResponse` | Bedrock Cohere embeddings parse |
| OpenAIConnector.EmbeddingsResponse_ApplyImportMapping | `create GenAICommons.EmbeddingsResponse` | OpenAI embeddings parse |
| ChatCompletions_ConversationalUI.Message_AddReferences_FromJSON | a `log warning` | message references import |

Dropped: `AgentCommons.EM_Agent`, `ChatCompletions_JsonModeDemoData.EM_Car` and `IM_Car`, `Embeddings_Clustering.EM_ClusterDetails`,
`AmazonBedrockConnector.EXM_InvokeModel_TitanImageGeneratorG1_Request`, `MxGenAIConnector.EM_ConverseRequest`,
`OpenAIConnector.EM_OpenAIRequest`, `MxGenAIConnector.IM_Collection_RetrieveNearestNeighbors`. (EM_Agent and IM_Car had no live caller:
their microflows are among the documents that never landed.)

## 4. Why `mxbuild` needed more than the model

After `mx check` 0, `mxbuild` fails in `javac`: 976 errors. Three causes, none a model error:

1. **Managed JAR dependencies not declared** (14 of 50, in MCPClient, MCPServer, GenAICommons, AmazonBedrockConnector, MxGenAIConnector,
   OpenAIConnector). MDL: `alter module M add jar dependency (...)`, generated from `describe jar dependency` on the source. Done in `build-fix.mdl`.
2. **Jars not resolved.** `mxcli sync-java-deps` failed here ("Failed to find some hosts": no Maven access from the sandbox), so the resolved jars were
   copied from the source's `vendorlib/` and the two `userlib/` jars (`simple_kmeans`, `tsne`) with `cp --update=none`. 976 -> 703 errors (the `userlib` jars are the last 15). Not MDL.
3. **Java sources.** A Java action created from MDL carries only the body between the markers: no `import` lines and no helper classes
   (`impl` packages). `javasource/` of the source was copied over the target's. 703 -> 11 errors. Not MDL (`rehost-app.md` Step 1, "Java actions").
4. The last 11 `javac` errors were calls to microflows that never landed (`Microflows.promptToUse_ApplyVariable`,
   `chatCompletions_WithHistory`, three PgVector flows, three AgentEditorCommons `*_CreateUpdate_List` flows). They are in the 482 failed-exec rows.
   Landed here (19 microflows besides the 6 Ticket flows, all named in `build-fix.mdl`): 11 **rules** first (N-1: `describe rule` works on the source, so the 11 missing of its 13 were created
   by hand from it), then `land` by dependency. Three needed a fix: `ChatCompletions_WithHistory` and `Response_CallRecursively` call each other (callee created as
   a stub, caller created, callee replaced by `drop` + `create`); `MxCloudDeployedModel_CreateUpdateFromModel` writes inherited attributes
   (`ModelDocumentID`) bare and exec refuses the unit, so they are written as `GenAICommons.DeployedModel.ModelDocumentID`;
   `AgentFromModel_Validate` is described with merge/join statements that check refuses (MDL003), so the tail was rewritten as nested `if`s with the same logic.

Order that works: MDL script -> `mxcli fix widgets` -> `mxcli fix design-properties` -> jars into `vendorlib/` -> `javasource/` from the source -> mxbuild.
exec also auto-creates a module role `AgentEditorCommons.User` for the first microflow it writes there (the source module has none); the script drops it.

## 5. Before and after, and what is still open

| gate | before | after |
|---|---|---|
| `mx check` | 42 x CE1613 (hiding about 70 more) | 0 errors |
| mxbuild `--target=deploy` | BUILD FAILED (exit 3, 42 app errors) | BUILD SUCCEEDED (exit 0) with the non-MDL steps of section 4; without them: `javac` 976 errors |
| failed-exec documents landed | 0 of 482 | 30 of 482 (26 microflows/snippets/pages, the Ticket entity, 3 export mappings); about 450 still absent |

Remaining hand-offs, none a build blocker:

- **Stubbed behaviour** (table above): OpenAI and Mendix Cloud chat request bodies, the three embeddings parsers, nearest-neighbour search, the Titan image request, the knowledge-base populate body. These are the product, so "build-green" here is not "works".
- **8 dropped mapping documents** and the mapping classes behind them (obtain-by-microflow arguments, mapping parameters, converter transforms): rebuild in Studio Pro.
- **36 icon widgets** in 20 documents; the `Agent` document references on 2 `Agent_CallDocument_*` calls (string, runtime unproven); the 2 page titles and 1 text box label.
- **About 450 documents never landed** (`<M>.deferred.mdl` of the run: 289 microflows, 9 nanoflows, 123 pages, 26 snippets). Build-green only means nothing compiled refers to them.
- Journeys NOT RUN (needs live LLM credentials).

## 6. Which fixes disappear if mxcli fixes the defect

The numbers U75-U81 are not defined in this repository, so this table uses the defect, not a number. Where the defect already carries one (U7, N-1..N-5) that is named.

| defect | fixes in `build-fix.mdl` that become unnecessary |
|---|---|
| U7: describe/exec drop the Java action type parameter | the 14 `ENTITY <T>` declarations and all 20 caller edits (`ContextObjectType = ...`, `EntityType = ...`) |
| N-1: message definitions, rules, mapping documents not emitted by `project-tree` | the 3 collections, 3 mappings and 11 rules created from the source describe; the extractor would emit them |
| N-3: exec accepts a mapping on a missing entity | the drop/recreate ordering of `EM_Ticket`/`IM_Ticket` |
| N-4: widget attribute context not carried by describe | the Trace page restructure and the `dvMessageContent` wrapper |
| N-5: snippet call `Params:` not described | the `Version_Overview` edit |
| optional microflow parameters not described | the 9 caller rewrites (`ID = empty`, `TraceID = empty`, `IsOffset = false`) |
| icon on an `image` widget not persisted | the 36 dropped widgets |
| template parameters on show-page title, text box label, snippet text outside a data context not carried | the title/label literals, the `dvTrace` wrapper |
| mapping parameters, obtain-by-microflow arguments, converter transforms not written correctly | the 8 dropped mappings and 11 stubs |
| inherited attributes bare in `change`/`where` | the one qualified microflow |
| merge/join described but refused (MDL003) | the `AgentFromModel_Validate` rewrite |
| module JAR dependencies not extracted; Java action imports/helpers not carried | the 14 `add jar dependency` statements; the `vendorlib/` and `javasource/` copies |
| widget definition / design property resync after a write | `mxcli fix widgets`, `mxcli fix design-properties` (unchanged: Mendix's own tool does that work) |

## 7. Skill feedback (`skills/rehost-app.md`; not edited)

- Step 5 should say the first `mx check` count is a floor: phases hide each other (42 -> 115 -> 0 here).
- Add the classes of section 3 to the Step 5 hand-off table, and "rules" and "module JAR dependencies" to Step 1: both are one `describe` away on the source.
- The mxbuild gate needs `vendorlib/` resolved and `javasource/` copied before it can say anything about the model; a run on a bare target fails in `javac` and looks like a model failure.
- Never re-describe a document you wrote by hand and re-exec it: `describe` does not round-trip inherited attribute names, markdown attribute context or document references (the first replay of this script failed on exactly that).
