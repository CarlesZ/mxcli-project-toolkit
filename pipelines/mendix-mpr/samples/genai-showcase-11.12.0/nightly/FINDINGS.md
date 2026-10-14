# Rehost of the GenAI Showcase App (Mendix 11.12.0) on the mxcli nightly, compared with run 4 (v0.26.0)

Run on 2026-10-13 with mxcli `nightly-80-gbd45c47e` and the extractor at commit 6cd0c6a (the E1–E3 fix). The source,
the 36 modules and the post-install target snapshot are the same as for the baseline (`../FINDINGS.md`, run 4).
Describes were fresh from the nightly. `CAPTURE.txt` describes the setup. Written from the worker's handback
(commits 6cd0c6a, 5ef32b4, 2c3a19d). Credit: mendix/genai-showcase-app; mendixlabs/mxcli nightly.

**One-line result:** all 36 of 36 modules landed. 2395 of 2776 catalog documents landed (1537 identical, 858 drifted),
against 850 in the baseline. 482 failed, against 1993. As the run left it, the target does not load in `mx check`,
because of one snippet that mxcli wrote with an association path as a raw attribute name (N-2). With that one parameter
replaced, `mx check` gives 42 × CE1613 in 5 named classes, and mxbuild gives `BUILD FAILED`. Journeys NOT RUN: the
showcase needs live LLM provider credentials.

## 1. Baseline vs nightly

| measure | baseline (run 4, v0.26.0) | nightly (run 2) | main cause of the change |
|---|---:|---:|---|
| emitted-identical | 579 | 1537 | E1/E2 (the 7 dropped modules now land: 851 identical) + cascade |
| emitted-drift | 271 | 858 | E1/E2 (512 in the 7 modules); 632 of the 858 are microflows (#923 layout) |
| failed-exec | 1993 | 482 | E1/E2 (1520 → 159 in the 7 modules); 150 rows of the 29 others now land |
| not-emitted | 43 | 4 | splitter fix: compare-mdl no longer fuses a json structure with the next statement; the 4 left are building blocks (N-7) |
| not-expressible | 4 | 9 | the 7 modules are now compared: 4 more #923 decisions (U18) and 1 more FileManager |
| target-extra | 2 | 2 | — |
| modules landed | 29 / 36 | **36 / 36** | E1/E2 (quarantine maps the error; `exec-each.py` fallback for 2 modules) |
| deferred statements at the end | 1564 distinct, logged ~7× more (E3) | 758, logged exactly | E3 fix; 541 of the 758 are same-module closure, 217 are root errors |
| model loads in `mx check` | no: 3 microflows with a null `import from mapping` entity (M1) | no: 1 snippet with an association path stored as an attribute (N-2, new) | U22 FIXED removed M1; N-2 is a new defect |
| `mx check` after a minimal unblock | 14 × CE1613 | 42 × CE1613 (after replacing 1 snippet parameter) | more modules land, so more hand-off errors become visible |
| mxbuild `--target=deploy` | BUILD FAILED (exit 3, 14 errors) | BUILD FAILED (exit 3, 42 errors); as left: cannot load the model | — |

`mx check` errors by class (all CE1613):

| class | baseline | nightly | attribution |
|---|---:|---:|---|
| Java action type parameter written as `.Entity` / `.ContextObject` | 7 | 14 | U7 STILL_BROKEN; doubled because AgentCommons and MxGenAIConnector now land |
| export mapping missing (message definition never emitted) | 4 | 5 | N-1 (new): `project-tree --json` omits message definitions, so the fill-in cannot emit them |
| sort on an inherited attribute | 2 | 0 | **U37 FIXED** |
| `ConversationalUI.ChatContext` missing (module dropped) | 1 | 0 | E2 fix |
| ExampleMicroflows mapping elements on a missing entity `Ticket` | 0 | 16 | E5 (extractor, fixed after the run) dropped `Ticket`; N-3 (new): check/exec accept a mapping on a missing entity |
| page `AgentCommons.Version_Overview` and its parameters missing | 0 | 4 | N-5 (new): describe omits the snippet call's `Params:` |
| Markdown viewer attribute resolved against the wrong data view | 0 | 3 | N-4 (new, likely) |
| **total** | **14** | **42** | |

Wall-clock time per phase:

| phase | baseline | nightly |
|---|---:|---:|
| inventory captures | (in "rest") | 129 s |
| source describes + topo | 30 min fresh (run 1); reused in run 4; topo 37 s | 28.1 min fresh; 57 s reused (run 2) |
| first check/exec pass | 847 s (14 min) | 2993 s (50 min): every module executes now; ConversationalUI 829 s, AgentCommons 550 s |
| deferred retry passes + settings/userroles | ~19 min, with the ledger | 5297 s (88 min); about 60 min of it was passes 3–6 retrying the same 758 statements (E6, fixed after the run) |
| target describes + ledger | 102 s (describes) | 864 s |
| **end to end** | 36 min reused / ~66 min fresh | 2 h 36 min reused / ~3 h 04 min fresh |
| `mx check` / mxbuild | 6–8 s / 13 s | 18 s / 21–23 s |

## 2. Attribution

- **Toolkit E1–E3 fix (commit 6cd0c6a), most of the gain.** The 7 formerly dropped modules account for 1363 of the 1545
  newly landed rows and for 1361 of the 1511 fewer failures. On the run-4 v0.26.0 captures, the fixed
  `quarantine-mdl.py` maps 1–11 statements in each of those 7 modules instead of 0. That isolates the fix from the
  nightly, so no separate v0.26.0 rerun was needed. On the nightly, quarantine mapped everything except two exec errors
  that name no statement (N-6). For those, `lib/exec-each.py` landed 22 statements of MCPClient_ConnectToServer and 320
  of ConversationalUI instead of dropping them. not-emitted 43 → 4 comes from the splitter fix, which compare-mdl also uses.
- **Cascade from those modules existing:** 150 rows in the other 29 modules went from failed to landed. In the baseline,
  167 of those rows referenced a dropped module.
- **Nightly fixes that moved numbers:** U37 (−2 build errors); U22 (no null `import from mapping` entity, so the
  model-load blocker M1 is gone); U16 (GenAICommons describe had 24 misplaced Java-action commas on 0.26.0 and has 0 on
  the nightly, so `fix-describe-output.py` is now a no-op); U24 (ComputerUse_AmazonBedrock lands); U31 (the truncation
  is now announced; the stdout cap at 10 001 lines remains and the extractor's defence still fires).
- **Nightly fixes that did not reach Rehost:** U5 (rules can be described) does not help yet, because
  `project-tree --json` lists no rules (N-1), so the extractor never emits them. 1 flow still fails `which is not a rule
  in this project`.
- **What the nightly made worse:** nothing measured. N-2 is new on this run, but the snippet never landed in the
  baseline (AgentCommons was dropped), so this run cannot show whether 0.26.0 had the same defect.

## 3. Remaining failure classes (verbatim, one example each)

The 217 root errors among the 758 deferred statements, by frequency (the other 541 are same-module closure):

- **A callee that is itself deferred, including the mutual-recursion cycle, ~80:** `statement 3: microflow
  'MxGenAIConnector.ConfigurationTest_ExecuteTest' has reference errors: - microflow not found:
  GenAICommons.ChatCompletions_WithoutHistory (referenced by call microflow)` and `microflow
  GenAICommons.Response_CallRecursively references microflow GenAICommons.ChatCompletions_WithHistory before it is created`.
- **A page or snippet reference to a deferred document, ~30:** `page 'Q' has reference errors: - snippet not found: Q`.
- **describe emits MDL that check refuses (U6/U10/U11), ~15:** `✗ page …: show page …: argument ShowcaseKnowledgeBase:
  $… cannot be stored — widget actionButton… is not inside a data view`; `CaptionParams parameter {1} is written as
  "$…/SearchTerm"`; `✗ merge shared1: nothing joins it. [MDL-FLOW02]`.
- **Snippet call without `Params:` (N-5):** `snippet AgentCommons.Snippet_Agent_SelectVersion requires parameter $Agent`.
- **Rules not emitted (N-1):** `if condition calls 'AgentCommons.Rule_PromptToUse_ContainsVariable(...)', which is not a
  rule in this project`.
- **Message definitions not emitted (N-1):** `export mapping …EM_FunctionCalling_Ticket: message definition "….Ticket"
  not found — this project has no message definitions`.
- **Same-name microflow and Java action (U23):** `failed to create microflow: refusing to write unit …: attribute
  reference not qualified`.
- **Entity ↔ event-handler cycle:** `ExampleMicroflows.Ticket` has `on before commit call ExampleMicroflows.BCo_Ticket`,
  and BCo_Ticket takes a `$Ticket` parameter: `Error: microflow not found: ExampleMicroflows.BCo_Ticket — hint: … is
  defined later in this script`. A hand-off either way, because exec cannot create either side first.

Toolkit defects found on this run, fixed after it (commit 5ef32b4, proven on the captured case plus Banking, not
re-run in full):

- **E5. `exec-resume.py` deferred the document the error NAMED, not the statement that FAILED.** On a forward reference
  it deferred X's definition and resumed after it, silently skipping every statement in between. This run lost 5
  documents (ExampleMicroflows.Ticket, BDe_Ticket, Ticket_GetNumberOfTicketsInStatus; MCPClient_ConnectToServer
  ACT_SuggestedUserPrompt_Use, SuggestedUserPrompt_UsePrompt). Fix: defer the first statement that references X, and
  resume from the earliest statement that names anything in the error.
- **E6. Retry passes counted "exec returned 0" as progress,** so passes 3–6 retried the same 758 statements (~60 min).
  Fix: progress means fewer deferred statements.
- **Ledger evidence is thin:** `failed-exec` rows say `absent from target describe`. The reason is in
  `mdl/<M>.deferred.mdl` (one `-- deferred:` line per statement), but compare-mdl does not copy it into the row.
  Follow-up, not done.

## 4. Done criterion: build-green with hand-offs

**Not reached.** The blockers, in order:

1. **The model does not load as the run left it** (N-2, mxcli): one snippet, `AgentCommons.Snippet_Output_List`, has a
   ContentParams association path stored as a raw attribute name. Found by a BSON scan for `AttributeRef.Attribute`
   values that contain `/` (1 hit). With that one parameter replaced the model loads.
2. **42 × CE1613, all in 5 named classes:** Java action type parameters 14 (U7), message-definition export mappings 5
   (N-1), ExampleMicroflows.Ticket cycle 16 (+ N-3), snippet call parameters 4 (N-5), Markdown viewer context 3 (N-4).
   Every one traces to a named document; fixing them in Studio Pro is a bounded hand-off list (about 40 documents).
3. **482 failed-exec rows are not yet named hand-offs.** 217 root errors and 541 closure statements sit in
   `<M>.deferred.mdl` with verbatim errors. Most are cascades of the mutual-recursion cycle and of the check-rejected
   describe output, so they would land once those few roots are fixed by hand.

So build-green with hand-offs is now **within a bounded hand-off list**, which it was not on 0.26.0 plus the old
extractor (7 modules unaccounted for). It still needs mxcli fixes for N-1 and N-2, or a manual pass over about 40
documents plus the cycle roots. **Journeys NOT RUN**: the showcase's flows call live LLM providers (OpenAI, Bedrock,
Mistral, Gemini, Mendix Cloud GenAI), and this headless run has no credentials.

## 5. Skill feedback (`skills/rehost-app.md`; not edited, for the skill owner)

- **Step 2 budget is out of date.** A full GenAI run on the nightly takes 2 h 36 min with reused describes (about 3 h
  fresh), not 36 min. Check/exec is now 50 min because every module executes. With E6 fixed the retries should drop by
  about 60 min.
- **Step 3 "Still open (E1–E3)"** can move to fixed (commit 6cd0c6a). `never executed` now counts statements exactly.
  An unplaceable exec error falls back to one statement per process, which is slow: about 2 s per statement, 320
  statements on ConversationalUI.
- **Step 1 / Step 5 hand-off tables:** rules and message definitions are missing from `project-tree --json` even on the
  nightly, so the "[fixed after 0.26.0]" note on rules does not yet help a tree-driven extractor, and "the extractor must
  emit the collection" has no source to emit from. Add building blocks (they describe as comments only; 4 on GenAI) and
  entity ↔ event-handler cycles.
- **Step 5 model-load failure:** add the second shape (ContentParams association path, N-2) and how to find it: a BSON
  scan for `AttributeRef.Attribute` containing `/`, next to the null-entity scan.
- **Step 4:** the `failed-exec` reason lives in `mdl/<M>.deferred.mdl` until compare-mdl copies it into the evidence column.
