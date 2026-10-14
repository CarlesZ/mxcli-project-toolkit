# Manual Studio Pro steps — <change or round name>

<!-- Copy to docs/manual-steps.md in the project. Template: templates/manual-steps.md in the toolkit;
     the rules are in skills/existing-app-change.md → "Edits mxcli cannot make".

     bin/status.sh counts this file: every line that starts "- [ ] Done" is a PENDING step, every
     "- [x] Done" a done one. One such line per step, nothing else in the file starts that way.
     Fenced blocks (```) are not counted, which is why the worked example below is fenced. -->

**Order matters.** Steps are listed in the order they must be done. A step that needs something an
MDL script creates (a new attribute, a new microflow) names that script under *Depends on*, and that
script is applied first.

**A step done by patch is still an exec.** If a step is done by a Python/BSON patch instead of by
hand, it runs as `./bin/exec.sh --patch <script>` — the snapshot, the mxbuild gate and the BUILD-LOG
row are the evidence, and a patch run any other way has none. Record the BUILD-LOG date on the Done line.

---

## Steps

<!-- One section per step, copied from the example. Delete this comment and the example block
     once the first real step is written. -->

```markdown
### MS-01 — Add the "second approver" branch to ACT_Order_Approve

- **Document:** `Orders` › `Microflows` › `Approval` › `ACT_Order_Approve`
- **Why mxcli cannot do it:** the decision's branches rejoin before the end event; DESCRIBE → exec
  of this microflow re-orders the flow (upstream mxcli #923), so it is edited in place instead.
- **Depends on:** `mdlsource/031-orders-approver-attrs.mdl` (adds `Order.SecondApproverRequired`) — applied first.
- **Exact clicks:**
  1. Open the microflow. Find the activity captioned `Retrieve approval policy` (the anchor).
  2. After it, insert a Decision with caption `Above 250?` and expression `$Order/Amount > 250`.
  3. `true` → Change object `$Order`, set `SecondApproverRequired` = `true`, no commit. `false` → straight on.
  4. Join both branches into the existing merge before `Commit order`.
- **Check (a person can run this in the app):** as `Buyer`, submit an order of 300 → the order shows
  "Waiting for second approver". Submit one of 200 → it does not.
- [ ] Done — by hand (commit `<sha>`) / by patch (`./bin/exec.sh --patch <script>`, BUILD-LOG row `<date>`)
```
