# mxtk-lint-rule: perf002_nested_data_widgets
# Shipped by mxcli-project-toolkit. Needs no per-project configuration; sync-project.sh
# refreshes it while it is unedited and reports (never overwrites) a locally edited copy.
# See lint-rules/README.md.
# --- end mxtk-lint-rule header ---
# PERF002: Nested data widgets
#
# A data view inside a list view inside a data grid retrieves per row, per level: the page
# issues one query for the outer list, one per outer row for the middle, one per middle row
# for the inner. Two levels is common and usually fine; three data containers deep is where
# pages go from instant to seconds. This rule flags a data widget (data view, list view,
# data grid, gallery, template grid) that has MAX_NESTING or more other data widgets above
# it on the same page, i.e. the third data container down.
#
# Deliberately NOT flagged: widgets in System/Administration, and nesting that stops at
# MAX_NESTING - 1 ancestors. One finding per offending widget, naming the page and widget.
#
# Vocabulary (mxcli 0.26 mdl/linter/starlark.go widgets(): `widget_type` and
# `parent_widget_id`). widget_type strings probed 2026-10-12 on a 21-module Mendix 11.12
# model (catalog FULL): core widgets are `Forms$DataView`, `Forms$ListView`,
# `Forms$ListViewTemplate` (the row template inside a list view — NOT a container of its
# own, hence excluded); pluggable grids are `com.mendix.widget.web.datagrid.Datagrid` and
# `com.mendix.widget.web.gallery.Gallery`; grid filters are
# `com.mendix.widget.web.datagrid<kind>filter.Datagrid<Kind>Filter` (excluded). The rule
# matches DATA_WIDGET_CANDIDATES as case-insensitive substrings after dropping "$", "_",
# "-", "." and spaces from the type, and skips anything containing an EXCLUDE entry. A
# different Mendix version may spell these differently — probe before trusting:
#   sqlite3 .mxcli/catalog.db "SELECT DISTINCT WidgetType, COUNT(*) FROM widgets GROUP BY 1 ORDER BY 2 DESC;"
# If widgets exist and NO type matches a candidate, the rule says so with a `_rule` finding
# instead of reporting a clean pass: extend the constant to the spellings the probe shows.

RULE_ID = "PERF002"
RULE_NAME = "NestedDataWidgets"
DESCRIPTION = "A data widget sits inside MAX_NESTING or more other data widgets on the same page"
CATEGORY = "performance"
SEVERITY = "warning"

REQUIRES = ["full"]

SKIP_MODULES = ("System", "Administration")

# Number of data-widget ANCESTORS that triggers a finding (2 ancestors = third level down).
MAX_NESTING = 2
# Substrings of the normalized widget_type that make a widget a data container.
DATA_WIDGET_CANDIDATES = ("dataview", "listview", "datagrid", "gallery", "templategrid")
# Substrings that disqualify a match (parts of a grid, not containers of their own).
EXCLUDE = ("column", "filter", "search", "header", "footer", "controlbar", "pagination", "sort", "listviewtemplate")
WALK_LIMIT = 100
# Below this many widgets, "no data widget matched" is a plausible tiny model.
VOCAB_MIN_WIDGETS = 10


def _norm(t):
    for ch in ("$", "_", "-", ".", " "):
        t = t.replace(ch, "")
    return t.lower()


def _is_data(w):
    t = _norm(w.widget_type)
    if not t:
        return False
    for x in EXCLUDE:
        if x in t:
            return False
    for c in DATA_WIDGET_CANDIDATES:
        if c in t:
            return True
    return False


def check():
    violations = []
    ws = widgets()
    api_missing = False
    by_id = {}
    for w in ws:
        if getattr(w, "parent_widget_id", None) == None or getattr(w, "widget_type", None) == None:
            api_missing = True
            break
        by_id[w.id] = w

    widgets_seen = 0
    data_seen = 0
    with_parent = 0
    if not api_missing:
        for w in ws:
            if w.module_name in SKIP_MODULES:
                continue
            widgets_seen += 1
            if w.parent_widget_id:
                with_parent += 1
            if not _is_data(w):
                continue
            data_seen += 1
            ancestors = 0
            cur = w.parent_widget_id
            seen = [w.id]
            for _ in range(WALK_LIMIT):
                if not cur or cur in seen:
                    break
                seen.append(cur)
                p = by_id.get(cur)
                if p == None:
                    break
                if _is_data(p):
                    ancestors += 1
                cur = p.parent_widget_id
            if ancestors < MAX_NESTING:
                continue
            violations.append(violation(
                message="{}: data widget '{}' ({}) is nested inside {} other data widgets; each level re-queries per row of the level above.".format(
                    w.container_qualified_name, w.name, w.widget_type, ancestors),
                location=location(module=w.module_name, document_type="Page", document_name=w.container_qualified_name),
                suggestion="Flatten the page: load the inner data in a microflow that returns one prepared list, use an association path on the outer entity, or move the inner level to a detail page or snippet loaded on demand.",
            ))

    # SELF-CHECKS. A rule that cannot see must say so, never report a clean pass.
    if api_missing:
        violations.append(violation(
            message="PERF002 cannot run on this mxcli: widgets have no parent_widget_id / widget_type field. This rule inspected NOTHING.",
            location=location(module="_rule", document_type="Page", document_name="PERF002"),
            suggestion="Upgrade mxcli, or have the user turn it off (`enabled: false` in .claude/lint-config.yaml, recorded in PROJECT.md) rather than leaving it inert.",
        ))
    elif widgets_seen >= VOCAB_MIN_WIDGETS and data_seen == 0:
        violations.append(violation(
            message="PERF002 saw {} widgets and not one widget_type matches a data-widget candidate ({}). The vocabulary needs probing; this rule inspected NOTHING.".format(widgets_seen, ", ".join(DATA_WIDGET_CANDIDATES)),
            location=location(module="_rule", document_type="Page", document_name="PERF002"),
            suggestion="Probe: sqlite3 .mxcli/catalog.db \"SELECT DISTINCT WidgetType FROM widgets ORDER BY 1;\" and add the data-container spellings to DATA_WIDGET_CANDIDATES at the top of this rule.",
        ))
    elif data_seen >= 3 and with_parent == 0:
        violations.append(violation(
            message="PERF002 saw {} data widgets and none has a parent_widget_id, so no nesting could be measured. The catalog does not populate widget parents; this rule inspected NOTHING.".format(data_seen),
            location=location(module="_rule", document_type="Page", document_name="PERF002"),
            suggestion="Run `REFRESH CATALOG FULL` on a current mxcli so the widgets table carries ParentWidgetID, then lint again.",
        ))

    return violations
