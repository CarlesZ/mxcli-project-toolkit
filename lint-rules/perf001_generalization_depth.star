# mxtk-lint-rule: perf001_generalization_depth
# Shipped by mxcli-project-toolkit. Needs no per-project configuration; sync-project.sh
# refreshes it while it is unedited and reports (never overwrites) a locally edited copy.
# See lint-rules/README.md.
# --- end mxtk-lint-rule header ---
# PERF001: Deep generalization chain
#
# Every level of "Generalization" is another table the runtime joins on each retrieve of the
# specialized entity, and every level widens what the entity inherits (attributes, access
# rules, event handlers). Past two levels (A -> B -> C -> root) retrieves slow down and the
# model stops being readable. This rule walks `generalization` through entities() and flags
# an entity with MORE than MAX_DEPTH ancestors.
#
# How levels are counted:
#   - each ancestor that is an entity of this model counts 1
#   - a System.* ancestor (System.User, System.Image, System.FileDocument, ...) is not in
#     the walk's reach beyond itself, so it counts SYSTEM_ANCESTOR_LEVELS (default 1) and
#     the walk stops there
#   - an ancestor named but not found (other module not in the lint run, external) counts 0
#     and stops the walk: the rule never guesses at a chain it cannot see
#   - cycles stop the walk at the first repeat
#
# Deliberately NOT flagged: entities in System/Administration (not yours to change), and
# chains of exactly MAX_DEPTH. One finding per offending entity, with the chain.
#
# Vocabulary (mxcli 0.26 mdl/linter/starlark.go entities(): `generalization` is a string,
# the qualified name of the parent or "" when there is none). Probed 2026-10-12 on a
# 21-module Mendix 11.12 model: none is "", a System parent is "System.User" /
# "System.FileDocument" / "System.HttpMessage" / "System.Error", a model parent is
# "Module.Entity". On another version, probe before trusting:
#   sqlite3 .mxcli/catalog.db "SELECT DISTINCT Generalization FROM entities ORDER BY 1;"
# If the column is empty on a model you know has specializations, the rule says so with a
# `_rule` finding instead of reporting a clean pass.

RULE_ID = "PERF001"
RULE_NAME = "DeepGeneralization"
DESCRIPTION = "Entity generalization chain is deeper than MAX_DEPTH levels"
CATEGORY = "performance"
SEVERITY = "warning"

REQUIRES = ["full"]

SKIP_MODULES = ("System", "Administration")

# Ancestors allowed before a finding (A -> B -> C is 2 ancestors; A -> B -> C -> D is 3).
MAX_DEPTH = 2
# How many levels a System.* ancestor counts for.
SYSTEM_ANCESTOR_LEVELS = 1
SYSTEM_PREFIX = "System."
# Walk bound; a chain longer than this is reported as-is.
WALK_LIMIT = 50
# Below this many entities, "no generalization anywhere" is a plausible small model.
VOCAB_MIN_ENTITIES = 20


def _chain(ent, by_name):
    """Return (levels, names): levels counted per the header, names of the ancestors walked."""
    levels = 0
    names = []
    seen = [ent.qualified_name.lower()]
    cur = ent.generalization
    for _ in range(WALK_LIMIT):
        if not cur:
            break
        key = cur.lower()
        if key in seen:
            break
        seen.append(key)
        parent = by_name.get(key)
        if parent == None:
            if key.startswith(SYSTEM_PREFIX.lower()):
                levels += SYSTEM_ANCESTOR_LEVELS
                names.append(cur)
            break
        levels += 1
        names.append(cur)
        cur = parent.generalization
    return levels, names


def check():
    violations = []
    ents = entities()
    api_missing = False
    by_name = {}
    for e in ents:
        if getattr(e, "generalization", None) == None or getattr(e, "qualified_name", None) == None:
            api_missing = True
            break
        by_name[e.qualified_name.lower()] = e

    entities_seen = 0
    with_parent = 0
    resolvable = 0
    if not api_missing:
        for e in ents:
            if e.module_name in SKIP_MODULES:
                continue
            entities_seen += 1
            if e.generalization:
                with_parent += 1
                if e.generalization.lower() in by_name or e.generalization.lower().startswith(SYSTEM_PREFIX.lower()):
                    resolvable += 1
            levels, names = _chain(e, by_name)
            if levels <= MAX_DEPTH:
                continue
            violations.append(violation(
                message="{} sits {} levels down a generalization chain ({}); more than {} makes every retrieve join {} tables.".format(
                    e.qualified_name, levels, " -> ".join([e.qualified_name] + names), MAX_DEPTH, levels + 1),
                location=location(module=e.module_name, document_type="Entity", document_name=e.qualified_name),
                suggestion="Flatten the hierarchy: fold the middle entity's attributes into the specialization, or replace the inheritance with an association. Keep generalization for true is-a relations that need polymorphic retrieves.",
            ))

    # SELF-CHECKS. A rule that cannot see must say so, never report a clean pass.
    if api_missing:
        violations.append(violation(
            message="PERF001 cannot run on this mxcli: entities have no generalization / qualified_name field. This rule inspected NOTHING.",
            location=location(module="_rule", document_type="Entity", document_name="PERF001"),
            suggestion="Upgrade mxcli, or have the user turn it off (`enabled: false` in .claude/lint-config.yaml, recorded in PROJECT.md) rather than leaving it inert.",
        ))
    elif entities_seen >= VOCAB_MIN_ENTITIES and with_parent == 0:
        violations.append(violation(
            message="PERF001 saw {} entities and not one has a generalization. Either the model has no inheritance at all, or the column is empty and this rule inspected NOTHING.".format(entities_seen),
            location=location(module="_rule", document_type="Entity", document_name="PERF001"),
            suggestion="Probe: sqlite3 .mxcli/catalog.db \"SELECT DISTINCT Generalization FROM entities ORDER BY 1;\". If the column is empty on a model with specializations, run `REFRESH CATALOG FULL` and lint again.",
        ))
    elif with_parent > 0 and resolvable == 0:
        violations.append(violation(
            message="PERF001 saw {} entities with a generalization and could resolve none of them to an entity or a System.* name. The spelling of `generalization` is not what this rule expects; it inspected NOTHING.".format(with_parent),
            location=location(module="_rule", document_type="Entity", document_name="PERF001"),
            suggestion="Probe: sqlite3 .mxcli/catalog.db \"SELECT DISTINCT Generalization FROM entities ORDER BY 1;\" and adjust SYSTEM_PREFIX / the qualified-name matching at the top of this rule.",
        ))

    return violations
