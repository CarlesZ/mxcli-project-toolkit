# mxtk-lint-rule: perf004_npe_system_user_assoc
# Shipped by mxcli-project-toolkit. Needs no per-project configuration; sync-project.sh
# refreshes it while it is unedited and reports (never overwrites) a locally edited copy.
# See lint-rules/README.md.
# --- end mxtk-lint-rule header ---
# PERF004: Non-persistable entity associated with System.User / System.Session
#
# A non-persistable entity lives in the session's memory. Associate it with System.User or
# System.Session (or any entity that specializes them) and every access walks from a
# long-lived, heavily shared object to per-session objects the runtime must keep reachable:
# the association pins them for the life of the session and the User/Session side is read
# by every request. The common fix is to hold the user context as an attribute or a
# microflow parameter instead, or to make the helper entity persistable and clean it up.
#
# An association is flagged when one end is a non-persistable entity and the other end is
# System.User, System.Session, or an entity whose generalization chain reaches either.
# Deliberately NOT flagged: associations in System/Administration; ends that cannot be
# resolved to an entity of the model (the rule never guesses about a non-persistable end it
# cannot see). One finding per association.
#
# Vocabulary (mxcli 0.26 mdl/linter/starlark.go entities().entity_type, .generalization;
# associations().from_entity / to_entity). entity_type spellings probed 2026-10-12 on a
# 21-module Mendix 11.12 model: the catalog holds "PERSISTENT", "NON_PERSISTENT" and "VIEW";
# older accessors returned "Persistent" (see data_change_microflows.star). The rule therefore
# matches NON_PERSISTABLE_CANDIDATES as case-insensitive substrings of the type after
# dropping "_", "-" and spaces, so both spellings pass; VIEW entities are never flagged and
# do not trip the vocabulary check (one type mentioning persistence is enough). Probe:
#   sqlite3 .mxcli/catalog.db "SELECT DISTINCT EntityType FROM entities ORDER BY 1;"
#   sqlite3 .mxcli/catalog.db "SELECT DISTINCT Generalization FROM entities WHERE Generalization LIKE 'System.%';"
# If entities exist and NONE of them has a type containing "persist", the rule says so with a
# `_rule` finding rather than reporting a clean pass.

RULE_ID = "PERF004"
RULE_NAME = "NonPersistableToSystemUser"
DESCRIPTION = "Association between a non-persistable entity and System.User / System.Session"
CATEGORY = "performance"
SEVERITY = "warning"

REQUIRES = ["full"]

SKIP_MODULES = ("System", "Administration")

NON_PERSISTABLE_CANDIDATES = ("nonpersist",)
# Substring that every entity_type spelling (persistable or not) must contain.
ANY_PERSIST_MARK = "persist"
# Ends that trigger the rule, by qualified name (compared case-insensitively).
SYSTEM_TARGETS = ("System.User", "System.Session")
WALK_LIMIT = 50
# Below this many entities, "no entity_type mentions persist" is not conclusive.
VOCAB_MIN_ENTITIES = 10


def _norm(t):
    for ch in ("_", "-", " "):
        t = t.replace(ch, "")
    return t.lower()


def _is_npe(ent):
    t = _norm(ent.entity_type)
    for c in NON_PERSISTABLE_CANDIDATES:
        if c in t:
            return True
    return False


def _reaches_system(qname, by_name):
    """True when qname is, or generalizes (transitively) from, a SYSTEM_TARGETS entity."""
    targets = [t.lower() for t in SYSTEM_TARGETS]
    cur = qname.lower()
    seen = []
    for _ in range(WALK_LIMIT):
        if not cur or cur in seen:
            return False
        if cur in targets:
            return True
        seen.append(cur)
        e = by_name.get(cur)
        if e == None:
            return False
        cur = e.generalization.lower()
    return False


def check():
    violations = []
    ents = entities()
    api_missing = False
    by_name = {}
    for e in ents:
        if getattr(e, "entity_type", None) == None or getattr(e, "generalization", None) == None:
            api_missing = True
            break
        by_name[e.qualified_name.lower()] = e

    persist_mark = 0
    if not api_missing:
        for e in ents:
            if ANY_PERSIST_MARK in _norm(e.entity_type):
                persist_mark += 1
        for a in associations():
            if a.module_name in SKIP_MODULES:
                continue
            for npe_name, other_name in ((a.from_entity, a.to_entity), (a.to_entity, a.from_entity)):
                npe = by_name.get(npe_name.lower())
                if npe == None or not _is_npe(npe):
                    continue
                if not _reaches_system(other_name, by_name):
                    continue
                violations.append(violation(
                    message="Association {} links non-persistable {} to {}, which is (or specializes) System.User / System.Session: the non-persistable object is pinned to the session and every request walks the shared side.".format(
                        a.qualified_name, npe.qualified_name, other_name),
                    location=location(module=a.module_name, document_type="Association", document_name=a.qualified_name),
                    suggestion="Pass the user (or $currentUser) into the flows that need it instead of storing the association, or keep only the user's key as an attribute. If the link must exist, make the helper entity persistable and delete it when its work is done.",
                ))
                break

    # SELF-CHECKS. A rule that cannot see must say so, never report a clean pass.
    if api_missing:
        violations.append(violation(
            message="PERF004 cannot run on this mxcli: entities have no entity_type / generalization field. This rule inspected NOTHING.",
            location=location(module="_rule", document_type="Association", document_name="PERF004"),
            suggestion="Upgrade mxcli, or have the user turn it off (`enabled: false` in .claude/lint-config.yaml, recorded in PROJECT.md) rather than leaving it inert.",
        ))
    elif len(ents) >= VOCAB_MIN_ENTITIES and persist_mark == 0:
        violations.append(violation(
            message="PERF004 saw {} entities and not one entity_type mentions persistence, so persistable and non-persistable could not be told apart. The vocabulary needs probing; this rule inspected NOTHING.".format(len(ents)),
            location=location(module="_rule", document_type="Association", document_name="PERF004"),
            suggestion="Probe: sqlite3 .mxcli/catalog.db \"SELECT DISTINCT EntityType FROM entities ORDER BY 1;\" and adjust NON_PERSISTABLE_CANDIDATES / ANY_PERSIST_MARK at the top of this rule.",
        ))

    return violations
