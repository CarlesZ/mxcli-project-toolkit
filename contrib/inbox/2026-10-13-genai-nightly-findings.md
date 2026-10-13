# mxcli nightly defects found regenerating the GenAI Showcase App (Rehost, nightly re-run)

**From:** mendix/genai-showcase-app (Rehost increment 2, nightly re-run) — MendixMau
**Date:** 2026-10-13
**Kind:** bug
**Field evidence:** `pipelines/mendix-mpr/samples/genai-showcase-11.12.0/nightly/` (run-log.txt, fidelity-ledger.tsv, mx-check-target.txt, mxbuild-target.txt, FINDINGS.md). mxcli `nightly-80-gbd45c47e`, Mendix 11.12.0, 36 modules regenerated into `mxcli new --version 11.12.0` with 5 marketplace modules installed.
**Proposed target:** `bug-logs/mxcli-bugs.md` (one BUG-n each), upstream mxcli issues. None of these is in the 2026-10-13 nightly retest table (U1–U53), except where a U-id is named as related.

---

Format: defect — verbatim message — one-line repro — what works around it (or "nothing").

- **N-1. `project-tree --json` omits rules and message definition collections.** Both are describable
  on the nightly (`describe rule` works, U5 FIXED), but neither appears in the tree, so a
  tree-driven extractor never emits them and they are missing from its denominator.
  Repro: `mxcli -p "GenAI Showcase App.mpr" -c "show rules"` lists 9 `Rule_` documents;
  `mxcli -p … project-tree --json | grep -c Rule_` prints 0. No `message` type in the tree either.
  Effect on GenAI: 5 × CE1613 for export mappings built on message definitions
  (`Error: export mapping GenAICommons.EM_Reference: message definition "GenAICommons.MD_Reference.Reference" not found — this project has no message definitions`),
  and flows that call rules fail exec validation (`if condition calls 'AgentCommons.Rule_PromptToUse_ContainsVariable(...)', which is not a rule in this project`).
  Workaround: none in the toolkit yet; an extractor could add `show rules <M>` and the message
  definition listing to its fill-in.
- **N-2. exec writes a ContentParams association path into `AttributeRef.Attribute` as a raw
  string, and the model then cannot load.** check passes; exec reports `Created snippet
  AgentCommons.Snippet_Output_List`. Then `mx check` and mxbuild stop with
  `System.ArgumentNullException: Value cannot be null. (Parameter 'value')` — "An error occurred when
  trying to set the 'Attribute' property of a Attribute in a Snippet with ID 7215e844-…". The
  stored value is `AgentCommons.Value.Value_Variable/AgentCommons.Variable/Key` (BSON scan of
  `mprcontents`). The describe line is
  `ContentParams: ({1} = $currentObject/AgentCommons.Value_Variable/AgentCommons.Variable/Key)`;
  removing `$currentObject/` stores `AgentCommons.Value_Variable/AgentCommons.Variable/Key`, which is
  just as unloadable. The source stores this parameter with `AttributeRef` null. Related to U10
  (STILL_BROKEN, the `$currentObject/<Attr>` form, which check refuses), but this is the
  association-path form, which check lets through. Workaround: replace the parameter by hand (hand-off).
- **N-3. check and exec accept an import or export mapping whose entity does not exist.**
  `Created import mapping ExampleMicroflows.IM_Ticket` / `Created export mapping
  ExampleMicroflows.EM_Ticket` while `ExampleMicroflows.Ticket` was absent (`describe entity` →
  `Error: entity not found`). `mx check` then reports 16 errors of the form `[CE1613] "The selected attribute
  'ExampleMicroflows.Ticket.Identifier' no longer exists." at Value mapping element 'Identifier'`.
  Expected: check refuses the mapping like it refuses a microflow parameter of a missing entity
  (`entity ExampleMicroflows.Ticket does not exist`).
- **N-4. (likely) A pluggable widget attribute bound to an outer data context loses that context
  in describe.** `markdown markdownViewer3 (stringAttribute: SystemPrompt, …)` sits inside
  `dataview dataView7 (DataSource: microflow ConversationalUI.DS_CopyHelper_Create)`. exec binds it to
  the innermost entity, and `mx check` reports `[CE1613] "The selected attribute
  'ConversationalUI.CopyHelper.SystemPrompt' no longer exists." at Markdown viewer 'markdownViewer3'`
  (3 errors). `CopyHelper` has only `IsCopied`. The source binding has not been read from BSON yet,
  so confirm that first.
- **N-5. describe emits a snippet call without the `Params:` its snippet requires.** exec:
  `Error: failed to build page: failed to build widget: snippet AgentCommons.Snippet_Agent_SelectVersion
  requires parameter $Agent — add Params: (Agent = $<variable>) to the SNIPPETCALL, or place the call
  inside a data context`. So `AgentCommons.Version_Overview` never lands, which gives 4 × CE1613 at its callers. The same
  happens to `MCPClient_ConnectToServer.Snippet_Prompt_Arguments` (`requires parameter $Prompt`). Maybe
  the same family as U6.
- **N-6. exec errors that do not name the failing statement.** `Error: failed to build snippet:
  failed to build widget: template for AgentCommons.MCP in list view listView1: AgentCommons.MCP is
  not a specialization of AgentCommons.Tool, so the template can never match an object the list view
  shows`. That names two entities but not the snippet being built, and exec prints no statement
  number. A resume loop cannot place it, so the toolkit falls back to one statement per process
  (`lib/exec-each.py`; 320 statements of ConversationalUI ran that way). Expected: prefix the failure with
  `statement N:` as `--continue-on-error` already does.
- **N-7. Building blocks describe as comments only.** `describe buildingblock
  ConversationalUI.ConversationStarter` prints `-- Building Block: …` lines with no `create`
  statement. These are the 4 `not-emitted` ledger rows. Hand-off.

Still open from the retest (re-seen on this run, no new information): U7 (Java action type parameter → `.Entity`, now 14 build
errors because more modules land), U18 (#923 decisions, 3 `not-expressible` rows), U23 (`refusing to write
unit …: attribute reference not qualified`), U31 (stdout of `-c describe module … with all` still ends at
10 001 lines; the toolkit's truncation defence still fires on AgentCommons and ConversationalUI).
