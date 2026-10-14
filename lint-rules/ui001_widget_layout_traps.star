# mxtk-lint-rule: ui001_widget_layout_traps
# Shipped by mxcli-project-toolkit. Needs no per-project configuration; sync-project.sh
# refreshes it while it is unedited and reports (never overwrites) a locally edited copy.
# See lint-rules/README.md.
# --- end mxtk-lint-rule header ---
# UI001: Widget layout traps that pass check and mxbuild and then render wrong
#
# Two traps from a 2026-10-12 UX-fix run over three apps, each of which cost one or more fix
# rounds because nothing before a screenshot could see them (issue #282, "known widget
# traps, keyed by widget"):
#
#   a. A list view inside a Data grid 2 column. The list view keeps its own paging and empty
#      state, so every grid cell can show its own "Load more" and "No items found".
#      Seen: a list view with a Data grid 2 ancestor (any depth, same page or snippet).
#   b. An inline `width` on an Atlas input (text box, text area, date picker, drop-down,
#      combo box, reference selector). Atlas lays inputs out as flex items, so the width is
#      ignored — even with !important — unless the same style sets `flex` (flex: 0 0 auto).
#      Seen: an input widget whose Style declares `width` (not min-/max-width, not 100% or
#      auto, which are no-ops here) and declares no `flex` / `flex-basis`.
#
# One finding per offending widget, naming the page or snippet and the widget.
#
# Deliberately NOT here: an inline Style on a dynamic text (it crashes MxBuild) is already an
# error at script time — `mxcli check` rule MDL-WIDGET03. Data grid 2 row styling
# (display: contents rows paint no outline) and column alignment are CSS / column-property
# traps the widgets() projection cannot see; they live in skills.
#
# Vocabulary (mxcli 0.26 widgets(): widget_type, parent_widget_id, style,
# container_qualified_name, container_type), probed 2026-10-13 on a 21-module Mendix 11.12
# model (catalog FULL): Data grid 2 is `com.mendix.widget.web.datagrid.Datagrid`, its column
# content widgets carry it as parent_widget_id; the list view is `Forms$ListView`; inputs
# seen there are `Forms$TextBox`, `Forms$TextArea`, `Forms$DatePicker` and
# `com.mendix.widget.web.combobox.Combobox` (`Forms$DropDown` / `Forms$ReferenceSelector` are
# the metamodel names for the older selectors, not seen in that model); container_type is
# uppercase (`PAGE`, `SNIPPET`). Probe before trusting:
#   sqlite3 .mxcli/catalog.db "SELECT DISTINCT WidgetType, COUNT(*) FROM widgets GROUP BY 1 ORDER BY 2 DESC;"
# If widgets exist and NO type matches either trap's vocabulary, or no widget has a parent,
# the rule says so with a `_rule` finding instead of reporting a clean pass.

RULE_ID = "UI001"
RULE_NAME = "WidgetLayoutTraps"
DESCRIPTION = "A list view inside a Data grid 2 column, or an inline width on an Atlas input without flex"
CATEGORY = "design"
SEVERITY = "warning"

REQUIRES = ["full"]

SKIP_MODULES = ("System", "Administration")

DATAGRID_TYPES = ("com.mendix.widget.web.datagrid.Datagrid",)
LISTVIEW_TYPES = ("Forms$ListView",)
INPUT_TYPES = ("Forms$TextBox", "Forms$TextArea", "Forms$DatePicker", "Forms$DropDown",
               "Forms$ReferenceSelector", "com.mendix.widget.web.combobox.Combobox")
# A width value that is a no-op on a flex item that already stretches.
HARMLESS_WIDTHS = ("100%", "auto", "inherit", "initial", "unset")
WALK_LIMIT = 100
# Below this many widgets, "no type matched" is a plausible tiny model.
VOCAB_MIN_WIDGETS = 10


def _decls(style):
    """Parse an inline style into {property: value}, lowercased and trimmed."""
    out = {}
    for part in style.split(";"):
        if ":" not in part:
            continue
        i = part.index(":")
        k = part[:i].strip().lower()
        v = part[i + 1:].strip().lower().replace("!important", "").strip()
        if k:
            out[k] = v
    return out


def _doc_type(w):
    t = w.container_type.lower()
    if t == "snippet":
        return "Snippet"
    return "Page"


def check():
    violations = []
    ws = widgets()
    api_missing = False
    by_id = {}
    for w in ws:
        for f in ("parent_widget_id", "widget_type", "style"):
            if getattr(w, f, None) == None:
                api_missing = True
        if api_missing:
            break
        by_id[w.id] = w

    widgets_seen = 0
    vocab_hits = 0
    with_parent = 0
    grids = 0
    if not api_missing:
        for w in ws:
            if w.module_name in SKIP_MODULES:
                continue
            widgets_seen += 1
            if w.parent_widget_id:
                with_parent += 1
            t = w.widget_type
            if t in DATAGRID_TYPES:
                grids += 1
            if t in DATAGRID_TYPES or t in LISTVIEW_TYPES or t in INPUT_TYPES:
                vocab_hits += 1

            # Trap a: list view with a Data grid 2 ancestor.
            if t in LISTVIEW_TYPES:
                cur = w.parent_widget_id
                seen = [w.id]
                grid = None
                for _ in range(WALK_LIMIT):
                    if not cur or cur in seen:
                        break
                    seen.append(cur)
                    p = by_id.get(cur)
                    if p == None:
                        break
                    if p.widget_type in DATAGRID_TYPES:
                        grid = p
                        break
                    cur = p.parent_widget_id
                if grid != None:
                    violations.append(violation(
                        message="{}: list view '{}' sits inside Data grid 2 '{}'; every cell keeps the list view's own paging and empty state (\"Load more\", \"No items found\").".format(
                            w.container_qualified_name, w.name, grid.name),
                        location=location(module=w.module_name, document_type=_doc_type(w), document_name=w.container_qualified_name),
                        suggestion="Show the related values as one text (an association path or a calculated string) in the column, or move the list to a detail view of the selected row.",
                    ))

            # Trap b: inline width on an Atlas input without flex.
            if t in INPUT_TYPES and w.style:
                d = _decls(w.style)
                width = d.get("width")
                if width != None and width not in HARMLESS_WIDTHS and d.get("flex") == None and d.get("flex-basis") == None:
                    violations.append(violation(
                        message="{}: input '{}' ({}) sets an inline width ({}) without flex; Atlas lays inputs out as flex items and ignores the width.".format(
                            w.container_qualified_name, w.name, t, width),
                        location=location(module=w.module_name, document_type=_doc_type(w), document_name=w.container_qualified_name),
                        suggestion="Add `flex: 0 0 auto;` next to the width (or size the input through a design-system class that does), then check the screenshot.",
                    ))

    # SELF-CHECKS. A rule that cannot see must say so, never report a clean pass.
    if api_missing:
        violations.append(violation(
            message="UI001 cannot run on this mxcli: widgets have no parent_widget_id / widget_type / style field. This rule inspected NOTHING.",
            location=location(module="_rule", document_type="Page", document_name="UI001"),
            suggestion="Upgrade mxcli, or have the user turn it off (`enabled: false` in .claude/lint-config.yaml, recorded in PROJECT.md) rather than leaving it inert.",
        ))
    elif widgets_seen >= VOCAB_MIN_WIDGETS and vocab_hits == 0:
        violations.append(violation(
            message="UI001 saw {} widgets and not one widget_type matches its Data grid 2, list view or input vocabulary. The vocabulary needs probing; this rule inspected NOTHING.".format(widgets_seen),
            location=location(module="_rule", document_type="Page", document_name="UI001"),
            suggestion="Probe: sqlite3 .mxcli/catalog.db \"SELECT DISTINCT WidgetType FROM widgets ORDER BY 1;\" and add the spellings to DATAGRID_TYPES / LISTVIEW_TYPES / INPUT_TYPES at the top of this rule.",
        ))
    elif grids > 0 and with_parent == 0:
        violations.append(violation(
            message="UI001 saw {} Data grid 2 widgets and no widget has a parent_widget_id, so nothing inside a grid could be seen. The catalog does not populate widget parents; trap a inspected NOTHING.".format(grids),
            location=location(module="_rule", document_type="Page", document_name="UI001"),
            suggestion="Run `REFRESH CATALOG FULL` on a current mxcli so the widgets table carries ParentWidgetID, then lint again.",
        ))

    return violations
