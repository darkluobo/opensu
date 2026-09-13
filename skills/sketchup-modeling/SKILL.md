---
name: sketchup-modeling
description: >-
  Control a local SketchUp model from Codex through the installed OpenSU/SketchUp MCP
  extension. Use whenever the user asks Codex to create, modify, inspect, organize,
  repair, materialize, or validate architectural SketchUp geometry from natural language,
  including levels, rectangular or polygon floors/ceilings, slab and roof openings,
  walls, columns, beams, straight/L/U stairs with landings, flat roofs, door/window
  assemblies, glass curtain walls/storefronts, materials, Tags, transforms, duplication,
  safe batch operations, controlled deletion, dimensions, and model QA.
---

# SketchUp Modeling

Use the bundled scripts as deterministic bridges to the installed SketchUp extension:

- `scripts/opensu.py` for the stable core toolset.
- `scripts/opensu_advanced.py` for L/U stairs, slab/roof openings, and polygon slabs/ceilings.
- `scripts/opensu_edit.py` for single-entity non-destructive edits.
- `scripts/opensu_repair.py` for search, diagnosis, batch repair, and controlled deletion.

Resolve scripts relative to this Skill directory. Do not copy them into the user's project
and do not write ad-hoc socket/Ruby code when an exposed command already exists.

## Start every SketchUp task

1. Run `python scripts/opensu.py status`.
2. If it cannot connect, ask the user to open SketchUp and choose
   `Extensions > MCP Server > Start Server`, then retry.
3. Run `python scripts/opensu.py inspect` before changing the model.
4. Treat all architectural dimensions as millimetres.
5. Preserve existing user geometry unless the request explicitly changes it.
6. For multi-storey work, inspect existing levels first and define missing levels.

## Modeling workflow

Normally execute in this order:

1. define levels/storey elevations
2. floor/slab, including polygon slabs where needed
3. slab circulation/shaft openings
4. primary columns and beams
5. opaque exterior/interior walls
6. door/window openings and assemblies
7. curtain-wall/storefront assemblies
8. ceilings
9. stairs/circulation
10. flat roof/parapets and roof openings
11. materials and Tags
12. inspect
13. validate
14. if validation fails, diagnose the exact entities
15. apply the smallest targeted repair
16. inspect and validate again

Use stable semantic names such as `Level_01`, `Floor_Level01_001`, `Ceiling_Level01_001`,
`Column_A01_001`, `Beam_A01_B01_001`, `Wall_South_001`, `Door_South_001`,
`Window_East_001`, `Stair_L_L01_L02_001`, `CurtainWall_Showroom_001`, and `Roof_Main_001`.

## Repair workflow

When an existing model is wrong, do not immediately rebuild it. Use this sequence:

1. `opensu_repair.py diagnose`
2. inspect the returned issue, matched entity id/name, and repair hint
3. use `opensu_repair.py find` when a broader type/name/tag query is needed
4. apply a single edit or a batch edit
5. inspect
6. validate
7. repeat only for remaining errors

Use batch commands when several known entities need the same operation. A batch is one
SketchUp undoable operation, so the user can undo it from SketchUp if needed.

## Single-entity editing

Use `opensu_edit.py` for:

- `rename`: rename one root Group/Component.
- `set-tag`: assign a SketchUp Tag to one root Group/Component.
- `set-visible`: show/hide one root entity.
- `transform`: move/rotate one OpenSU Group while synchronizing semantic coordinates.
- `duplicate`: copy one OpenSU Group with a unique name and optional offset/rotation.

After any transform or duplicate, run `inspect` and `validate` immediately.

## Batch repair

Use `opensu_repair.py` for:

- `find`: filter root Groups/Components by name fragment, OpenSU type, Tag, or visibility.
- `diagnose`: run validation and map messages back to named root entities when possible.
- `batch-tag`: assign one Tag to multiple known root entities.
- `batch-visible`: show/hide multiple known root entities.
- `batch-transform`: apply one translation/Z rotation to multiple OpenSU Groups while
  synchronizing semantic coordinates for each object.

Do not batch-transform mixed non-OpenSU content. Resolve the exact target ids first.

## Controlled deletion

Deletion is exposed only through `opensu_repair.py delete-confirmed` and is intentionally
hard to trigger. Use it only when the user explicitly asks to delete/remove an object or
when the user has explicitly authorized removal as part of a repair.

Before deleting:

1. inspect or find the target
2. capture its `entity_id` and exact current name
3. confirm the target is an OpenSU semantic root entity
4. call delete with all three: entity id, exact confirm name, and the explicit confirmation flag
5. inspect and validate immediately afterward

Never infer a delete target from a partial name. Never delete loose faces/edges or arbitrary
non-OpenSU user geometry. If intent is ambiguous, hide the object or ask the user instead.

## Levels and multi-storey reasoning

- Use `define-level` for named storey datums such as `Level_01=0`, `Level_02=4500`, and `Roof=9000`.
- Level metadata is model-level data, not fake geometry. `inspect` returns the level list.
- Treat a level elevation as the floor datum unless the user states another convention.
- When `level_name` is supplied, it must match an existing level exactly.
- Use floor top elevation as the normal wall/column base unless specified otherwise.

## Floors, ceilings, and slab openings

- Use rectangular `create-floor` / `create-ceiling` when a rectangle is sufficient.
- Use `opensu_advanced.py create-polygon-slab` or `create-polygon-ceiling` for a simple
  horizontal non-self-intersecting polygon, including concave footprints.
- Polygon vertices must all use the same Z and be supplied in boundary order.
- `create-slab-opening` targets rectangular OpenSU floor, ceiling, or flat-roof geometry.
  It may be called repeatedly for multiple non-overlapping openings.
- Keep every slab opening strictly inside the slab boundary.

## Openings and storefront logic

- A single OpenSU wall may contain multiple rectangular openings. Add them sequentially.
- Openings may not overlap.
- Create every required opening before its door/window assembly.
- When a wall has multiple openings, always pass `--opening-name` to the assembly command.
- For large glazed showroom/dealership fronts, prefer `create-curtain-wall`.

## Stairs and roofs

- `opensu.py create-stair`: one straight flight.
- `opensu_advanced.py create-l-stair`: two flights with one 90-degree landing.
- `opensu_advanced.py create-u-stair`: two return flights with one 180-degree landing.
- Use a floor opening when a stair passes through an upper slab.
- `create-flat-roof` creates a rectangular roof slab and optional four-sided parapets.
- Use `create-slab-opening` against the flat-roof group for rectangular skylight/roof access openings.

## Commands

Core:

```text
python scripts/opensu.py status
python scripts/opensu.py inspect
python scripts/opensu.py define-level ...
python scripts/opensu.py create-floor ...
python scripts/opensu.py create-ceiling ...
python scripts/opensu.py create-column ...
python scripts/opensu.py create-beam ...
python scripts/opensu.py create-wall ...
python scripts/opensu.py create-opening ...
python scripts/opensu.py create-door ...
python scripts/opensu.py create-window ...
python scripts/opensu.py create-curtain-wall ...
python scripts/opensu.py create-stair ...
python scripts/opensu.py create-flat-roof ...
python scripts/opensu.py apply-material ...
python scripts/opensu.py validate
```

Advanced geometry:

```text
python scripts/opensu_advanced.py create-l-stair ...
python scripts/opensu_advanced.py create-u-stair ...
python scripts/opensu_advanced.py create-slab-opening ...
python scripts/opensu_advanced.py create-polygon-slab ...
python scripts/opensu_advanced.py create-polygon-ceiling ...
```

Single edit:

```text
python scripts/opensu_edit.py rename ...
python scripts/opensu_edit.py set-tag ...
python scripts/opensu_edit.py set-visible ...
python scripts/opensu_edit.py transform ...
python scripts/opensu_edit.py duplicate ...
```

Repair/batch:

```text
python scripts/opensu_repair.py find ...
python scripts/opensu_repair.py diagnose ...
python scripts/opensu_repair.py batch-tag ...
python scripts/opensu_repair.py batch-visible ...
python scripts/opensu_repair.py batch-transform ...
python scripts/opensu_repair.py delete-confirmed ...
```

Read `references/tool-contract.md` for core commands and `references/advanced-geometry.md`
for advanced geometry details.

## Safety and current limits

- Never use arbitrary Ruby execution or invent unsupported SketchUp capabilities.
- Keep architecture in named Groups/Components rather than loose root geometry.
- Tags belong on Groups/Components, never raw edges/faces.
- Semantic transforms and batch transforms are restricted to OpenSU Groups.
- Controlled deletion is restricted to exact-id + exact-name confirmed OpenSU root entities.
- Straight, L-shaped, and U-shaped stairs are supported; spiral/multi-landing stairs are not.
- Polygon floors/ceilings may be concave but may not self-intersect.
- Pitched roofs and curved walls are not yet exposed.
- If a request exceeds the current tool surface, explain the missing capability instead of pretending it was modeled.
