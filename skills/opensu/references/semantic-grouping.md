# OpenSU semantic grouping

Semantic entity groups are persistent logical relationships between existing OpenSU root entities.

They are deliberately different from native SketchUp nested Groups:

- no member is reparented;
- each member keeps its existing OpenSU type and metadata;
- membership is stored by SketchUp persistent id, not by display name;
- renaming a member does not break membership;
- validation reports stale member references instead of silently dropping them.

## Data model

A stored group is model-level OpenSU metadata:

```json
{
  "name": "Showroom_Structure",
  "member_persistent_ids": [12345, 12346, 12347],
  "description": "Main showroom structural set",
  "source_ref": "A-101 / user confirmed"
}
```

Runtime inspection resolves those ids back to live root entities and returns their current names, entity ids, OpenSU types, Tags, visibility, and bounds.

## Safe lifecycle

Create a group only from existing OpenSU semantic root Groups/ComponentInstances.

A group can be:

- inspected/listed;
- renamed;
- have members added or removed;
- prune stale references after a member was deleted elsewhere;
- shown/hidden as a set;
- assigned one Tag as a set;
- transformed around one shared pivot;
- duplicated into a new group;
- dissolved without deleting geometry.

Removing the final member is rejected; dissolve the group instead.

## Transform semantics

Group transform is an assembly transform:

1. determine one shared pivot, defaulting to the combined member bounds center;
2. apply the same translation/Z rotation to each member;
3. update known OpenSU semantic point metadata;
4. preserve group membership because persistent ids do not change.

Do not rotate each member around its individual center.

## Deletion semantics

`dissolve` means delete the semantic relationship only.

It must not:

- erase SketchUp entities;
- delete loose geometry;
- cascade to member groups;
- infer destructive intent.

Member deletion remains a separate controlled-delete workflow.

If validation reports a deleted/missing member, `prune-missing` may remove only that stale persistent-id reference. If every member is missing, dissolve the group instead.

## Membership reasoning

Membership may come from:

1. explicit user instruction;
2. explicit drawing/semantic evidence;
3. an already persisted OpenSU group.

Do not group objects merely because they are spatially close.

An entity may intentionally belong to multiple logical groups, for example both `Level01_Columns` and `Showroom_Structure`.

## Current limits

- no physical/native nested SketchUp parent Group is created;
- group transform/duplicate requires OpenSU Group members;
- no recursive group-of-groups hierarchy yet;
- no automatic membership inference from proximity.
