# mxtk-lint-rule: txt002_non_iso_date_in_user_text
# Shipped by mxcli-project-toolkit. Needs no per-project configuration; sync-project.sh
# refreshes it while it is unedited and reports (never overwrites) a locally edited copy.
# See lint-rules/README.md.
# --- end mxtk-lint-rule header ---
# TXT002: A date in user-visible text that is not ISO (yyyy-MM-dd)
#
# A date written "10/12/2026" means two different days to two readers; "12 Oct" drops the
# year; a format pattern "dd MMM HH:mm" typed into a caption or message template renders
# every row that way. A 2026-10-12 UX-fix run over three apps found non-ISO dates in 2 of 3:
# one app had trail dates in `dd MMM HH:mm` plus a raw `M/d/yyyy`, another `dd MMM` in five
# places. Both apps had a glossary task whose grep listed two patterns and reported "33 of
# 33 already ISO"; two later tasks rewrote the same lines without fixing them. Both misses
# were found only by a read-only final review (issue #280).
#
# What it flags, in every user-visible string strings() returns (same scope as TXT001):
#   - a literal date not in ISO order: 10/12/2026, 1-2-2026, 12.10.2026, 12 Oct 2026,
#     Oct 12, 2026
#   - a date FORMAT pattern with day and month adjacent in non-ISO order: dd MMM, MM/dd,
#     d/M/yy, dd-MM-yyyy. The ISO forms yyyy-MM-dd and yyyy-MM are removed before matching,
#     so "yyyy-MM-dd HH:mm" passes.
# One finding per text element and pattern kind, all languages folded into one.
#
# Deliberately NOT read — say this out loud, it is the larger half of the incident: format
# strings inside EXPRESSIONS (formatDateTime($d, 'dd MMM HH:mm') in a microflow, a CHANGE
# that writes a date into an audit text). The catalog does not index expression literals, so
# this rule cannot see them; see process/lint-backlog.md for the blocked row. Nor does it see
# a DateTime attribute rendered with the locale's default format — that is a widget format
# setting, not a string.
#
# ISO dates are a toolkit opinion, not a Mendix rule. If this project's display standard is
# deliberately not ISO, turn the rule off in .claude/lint-config.yaml
# (`rules: TXT002: enabled: false`) and record the decision in PROJECT.md. Do not delete or
# loosen this file: sync re-installs a deleted rule and reports an edited one on every run.
#
# REQUIRES mxcli >= 0.25.0 (the strings() builtin) and a FULL catalog. On an older binary
# this file does not load at all — mxcli prints "rule file skipped" on stderr and no `_rule`
# finding is possible, so pin the binary. Vocabulary probed 2026-10-13, mxcli 0.26.0 — see the TXT001 header; same fields, same contexts. When pages
# exist and strings() returns nothing, or nothing it returns is user-visible, the rule says
# so with a `_rule` finding instead of reporting a clean pass.

RULE_ID = "TXT002"
RULE_NAME = "NonIsoDateInUserText"
DESCRIPTION = "User-visible text contains a date or date-format pattern that is not ISO yyyy-MM-dd"
CATEGORY = "quality"
SEVERITY = "warning"

REQUIRES = ["full"]

SKIP_MODULES = ("System", "Administration")
SKIP_OBJECT_TYPES = ("PAGE_TEMPLATE", "BUILDING_BLOCK", "PUBLISHED_REST_SERVICE")
SKIP_CONTEXTS = ("documentation", "log_node", "page_url", "resource_name", "rest_path",
                 "service_name", "version", "workflow_description")

_MON = "(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)[a-z]*\\.?"

# (label, Go RE2 pattern), matched after the ISO forms in ISO_FORMS are removed.
DATE_PATTERNS = (
    ("slash date", "\\b[0-9]{1,2}/[0-9]{1,2}/[0-9]{2,4}\\b"),
    ("dashed day-month-year date", "\\b[0-9]{1,2}-[0-9]{1,2}-[0-9]{4}\\b"),
    ("dotted date", "\\b[0-9]{1,2}\\.[0-9]{1,2}\\.[0-9]{4}\\b"),
    ("day month-name year date", "\\b[0-9]{1,2} " + _MON + " [0-9]{4}\\b"),
    ("month-name day, year date", "\\b" + _MON + " [0-9]{1,2}, [0-9]{4}\\b"),
    ("day-month format pattern", "\\bd{1,2}[ /.-]M{1,4}\\b"),
    ("month-day format pattern", "\\bM{1,4}[ /.-]d{1,2}\\b"),
)
# Removed (plain substring) before matching, so the ISO pattern itself never matches.
ISO_FORMS = ("yyyy-MM-dd", "yyyy-MM")

MIN_PAGES_FOR_BLINDNESS = 1


def _user_visible(s):
    if s.module_name in SKIP_MODULES:
        return False
    if s.object_type in SKIP_OBJECT_TYPES:
        return False
    if s.context in SKIP_CONTEXTS or s.context.lower().endswith("documentation"):
        return False
    return True


def _short(v):
    v = v.replace("\n", " ").strip()
    if len(v) > 80:
        return v[:77] + "..."
    return v


def check():
    violations = []
    ss = strings()
    api_missing = False
    for s in ss:
        for f in ("value", "context", "object_type", "qualified_name", "element_id", "module_name"):
            if getattr(s, f, None) == None:
                api_missing = True
        break

    visible = 0
    seen = {}
    if not api_missing:
        for s in ss:
            if not _user_visible(s):
                continue
            visible += 1
            text = s.value
            for iso in ISO_FORMS:
                text = text.replace(iso, "")
            for label, pat in DATE_PATTERNS:
                if not matches(text, pat):
                    continue
                key = s.qualified_name + "|" + s.element_id + "|" + label
                if key in seen:
                    continue
                seen[key] = True
                violations.append(violation(
                    message="{} ({}, {}): user-visible text holds a non-ISO {}: \"{}\"".format(
                        s.qualified_name, s.object_type.lower(), s.context, label, _short(s.value)),
                    location=location(module=s.module_name, document_type=s.object_type.capitalize(), document_name=s.qualified_name),
                    suggestion="Write dates as yyyy-MM-dd (and times as HH:mm). In a template, format the parameter with 'yyyy-MM-dd'; never type a literal date into a caption.",
                ))

    # SELF-CHECKS. A rule that cannot see must say so, never report a clean pass.
    if api_missing:
        violations.append(violation(
            message="TXT002 cannot run on this mxcli: strings() rows lack value / context / object_type. This rule inspected NOTHING.",
            location=location(module="_rule", document_type="Text", document_name="TXT002"),
            suggestion="Upgrade mxcli (strings() fields as of 0.26.0), or remove this rule deliberately rather than leaving it inert.",
        ))
    elif len(ss) == 0 and len(pages()) >= MIN_PAGES_FOR_BLINDNESS:
        violations.append(violation(
            message="TXT002 saw {} pages and strings() returned no text at all: the catalog is not FULL or does not index strings. This rule inspected NOTHING.".format(len(pages())),
            location=location(module="_rule", document_type="Text", document_name="TXT002"),
            suggestion="Run `REFRESH CATALOG FULL` (strings are only indexed in full mode), then lint again.",
        ))
    elif len(ss) > 0 and visible == 0:
        violations.append(violation(
            message="TXT002 saw {} strings and not one counts as user-visible under SKIP_CONTEXTS / SKIP_OBJECT_TYPES. The context vocabulary needs probing; this rule inspected NOTHING.".format(len(ss)),
            location=location(module="_rule", document_type="Text", document_name="TXT002"),
            suggestion="Probe: sqlite3 .mxcli/catalog.db \"SELECT DISTINCT ObjectType, StringContext FROM strings;\" and narrow SKIP_CONTEXTS / SKIP_OBJECT_TYPES at the top of this rule.",
        ))

    return violations
