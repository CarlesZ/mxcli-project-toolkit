# mxtk-lint-rule: txt001_build_words_in_user_text
# Shipped by mxcli-project-toolkit. Needs no per-project configuration; sync-project.sh
# refreshes it while it is unedited and reports (never overwrites) a locally edited copy.
# See lint-rules/README.md.
# --- end mxtk-lint-rule header ---
# TXT001: Build-process words in text the user reads
#
# The words a build runs on — "Stage 3", "BR-10", "F004", "TODO", a version tag, "(local,
# not from X)" — leak into page titles, subtitles, captions and messages, and stay there,
# because the person who wrote them reads past them. A 2026-10-12 UX-fix run over three apps
# built from this toolkit found leaked words in 3 of 3: "Stage N." in page subtitles of five
# scripts, sibling-app code names and a version tag in captions, rule ids and a "(local, not
# from X)" suffix in live titles. Each app had a glossary task with a one-off grep; the grep
# missed the same lines in 2 of 3 apps (issue #280). A rule reads every string, every run.
#
# What it reads: strings() — every translatable text in the app's own modules (page titles,
# dynamic-text and caption templates, labels, tooltips, tab captions, confirmation texts,
# validation messages, enumeration captions, menu items, microflow message templates,
# workflow task names). Skipped: SKIP_CONTEXTS (documentation, log node names, URLs, REST
# names — nobody reads those on screen) and SKIP_OBJECT_TYPES (page templates and building
# blocks are never rendered as such). One finding per text element and pattern, all
# languages folded into one.
#
# Deliberately NOT read: string literals inside expressions (a caption built by a microflow
# expression, a value written by a CHANGE). The catalog does not index expression literals;
# that half stays with the journey `textAbsent` check and the final LOOK pass.
#
# Configure: LEAK_PATTERNS (Go RE2, via matches()) and PROJECT_WORDS — the sibling-app code
# names, internal project names and anything else this project must never show a user.
# "Stage [0-9]" is a real domain word in some apps (a sales pipeline): if the field run shows
# it as such, drop that pattern deliberately rather than living with the noise.
#
# REQUIRES mxcli >= 0.25.0 (the strings() builtin) and a FULL catalog (strings are only
# indexed by `REFRESH CATALOG FULL`). On an older binary this file does not load at all —
# mxcli prints "rule file skipped" on stderr and no `_rule` finding is possible, so pin the
# binary. Vocabulary probed 2026-10-13 with mxcli 0.26.0 on a 21-module Mendix 11.12
# model: struct fields qualified_name / object_type / value / context / language /
# element_id / module_name; object_type is uppercase (PAGE, SNIPPET,
# MICROFLOW, ENUMERATION, ...); context is the Mendix property path
# ("Forms$Page.Title", "Forms$ClientTemplate.Template", "Microflows$TextTemplate.Text", ...)
# or a lowercase tag for non-translatable strings ("documentation", "log_node", "page_url").
# Probe on your model:
#   sqlite3 .mxcli/catalog.db "SELECT ObjectType, StringContext, COUNT(*) FROM strings GROUP BY 1,2 ORDER BY 3 DESC;"
# When pages exist and strings() returns nothing, or nothing it returns is user-visible, the
# rule says so with a `_rule` finding instead of reporting a clean pass.

RULE_ID = "TXT001"
RULE_NAME = "BuildWordsInUserText"
DESCRIPTION = "User-visible text contains build-process words (stage numbers, rule ids, TODO, version tags, project code names)"
CATEGORY = "quality"
SEVERITY = "warning"

REQUIRES = ["full"]

SKIP_MODULES = ("System", "Administration")
SKIP_OBJECT_TYPES = ("PAGE_TEMPLATE", "BUILDING_BLOCK", "PUBLISHED_REST_SERVICE")
SKIP_CONTEXTS = ("documentation", "log_node", "page_url", "resource_name", "rest_path",
                 "service_name", "version", "workflow_description")

# (label, Go RE2 pattern). Unanchored: a match anywhere in the text counts.
LEAK_PATTERNS = (
    ("stage number", "(?i)\\bstage [0-9]+\\b"),
    ("rule or requirement id", "\\b(BR|FR|NFR|UC|US|REQ)-[0-9]+\\b"),
    ("BRD feature id", "\\bF[0-9]{3}\\b"),
    ("work marker", "\\b(TODO|FIXME|TBD|XXX)\\b"),
    ("placeholder text", "(?i)\\blorem ipsum\\b"),
    ("version tag", "\\bv[0-9]+\\.[0-9]+(\\.[0-9]+)?\\b"),
    ("data-source note", "(?i)\\((local|mock|stub|dummy|seed)[,) ]"),
)
# Project-specific words, matched case-insensitively as whole words: sibling-app code names,
# internal project names. Empty by default.
PROJECT_WORDS = ()

# Below this many pages, "strings() returned nothing" is a plausible tiny model.
MIN_PAGES_FOR_BLINDNESS = 1


def _user_visible(s):
    if s.module_name in SKIP_MODULES:
        return False
    if s.object_type in SKIP_OBJECT_TYPES:
        return False
    if s.context in SKIP_CONTEXTS or s.context.lower().endswith("documentation"):
        return False
    return True


def _patterns():
    out = list(LEAK_PATTERNS)
    for w in PROJECT_WORDS:
        out.append(("project word '{}'".format(w), "(?i)\\b" + w + "\\b"))
    return out


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

    pats = _patterns()
    visible = 0
    seen = {}
    if not api_missing:
        for s in ss:
            if not _user_visible(s):
                continue
            visible += 1
            for label, pat in pats:
                if not matches(s.value, pat):
                    continue
                key = s.qualified_name + "|" + s.element_id + "|" + label
                if key in seen:
                    continue
                seen[key] = True
                violations.append(violation(
                    message="{} ({}, {}): user-visible text contains a {}: \"{}\"".format(
                        s.qualified_name, s.object_type.lower(), s.context, label, _short(s.value)),
                    location=location(module=s.module_name, document_type=s.object_type.capitalize(), document_name=s.qualified_name),
                    suggestion="Rewrite the text in the user's words. Stage numbers, rule ids, feature ids, version tags and project code names belong in documentation, not on screen.",
                ))

    # SELF-CHECKS. A rule that cannot see must say so, never report a clean pass.
    if api_missing:
        violations.append(violation(
            message="TXT001 cannot run on this mxcli: strings() rows lack value / context / object_type. This rule inspected NOTHING.",
            location=location(module="_rule", document_type="Text", document_name="TXT001"),
            suggestion="Upgrade mxcli (strings() fields as of 0.26.0), or remove this rule deliberately rather than leaving it inert.",
        ))
    elif len(ss) == 0 and len(pages()) >= MIN_PAGES_FOR_BLINDNESS:
        violations.append(violation(
            message="TXT001 saw {} pages and strings() returned no text at all: the catalog is not FULL or does not index strings. This rule inspected NOTHING.".format(len(pages())),
            location=location(module="_rule", document_type="Text", document_name="TXT001"),
            suggestion="Run `REFRESH CATALOG FULL` (strings are only indexed in full mode), then lint again.",
        ))
    elif len(ss) > 0 and visible == 0:
        violations.append(violation(
            message="TXT001 saw {} strings and not one counts as user-visible under SKIP_CONTEXTS / SKIP_OBJECT_TYPES. The context vocabulary needs probing; this rule inspected NOTHING.".format(len(ss)),
            location=location(module="_rule", document_type="Text", document_name="TXT001"),
            suggestion="Probe: sqlite3 .mxcli/catalog.db \"SELECT DISTINCT ObjectType, StringContext FROM strings;\" and narrow SKIP_CONTEXTS / SKIP_OBJECT_TYPES at the top of this rule.",
        ))

    return violations
