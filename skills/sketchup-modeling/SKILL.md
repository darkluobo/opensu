---
name: sketchup-modeling
description: >-
  Control a local SketchUp model from Codex through the installed OpenSU/SketchUp MCP
  extension. Use whenever the user asks Codex to create, modify, inspect, organize,
  repair, materialize, or validate architectural SketchUp geometry from natural language,
  including levels, rectangular or polygon floors/ceilings, slab and roof openings,
  walls, columns, beams, straight/L/U stairs with landings, flat roofs, door/window
  assemblies, glass curtain walls/storefronts, materials, Tags, transforms, duplication,
  visibility, dimensions, and model QA.
---

# SketchUp Modeling

Use the bundled scripts as deterministic bridges to the installed SketchUp extension:

- `scripts/opensu.py` for the stable core toolset.
- `scripts/opensu_advanced.py` for L/U stairs, slab/roof openings, and polygon slabs/ceilings.
- `scripts/opensu_edit.py` for safe non-destructive editing and repair.

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
14. repair with the edit bridge when needed
15. inspect and validate again

Use stable semantic names such as `Level_01`, `Floor_Level01_001`, `Ceiling_Level01_001`,
`Column_A01_001`, `Beam_A01_B01_001`, `Wall_South_001`, `Door_South_001`,
`Window_East_001`, `Stair_L_L01_L02_001`, `CurtainWall_Showroom_001`, and `Roof_Main_001`.

## Edit and repair workflow

Prefer targeted edits over rebuilding the entire model when geometry is basically correct.
Use `opensu_edit.py` for:

- `rename`: fix unstable or ambiguous root names.
- `set-tag`: organize complete Groups/Components on SketchUp Tags; never tag raw edges/faces.
- `set-visible`: temporarily hide/show complete root entities.
- `transform`: move and/or rotate one OpenSU Group while synchronizing stored semantic coordinates.
- `duplicate`: copy one OpenSU Group with a new unique name and optional offset/rotation.

Important transform rules:

- Transform only when the whole semantic object should move/rotate as one unit.
- The extension transforms geometry inside the OpenSU Group instead of adding a root
  transformation, then updates stored point metadata (`origin/start/end/center/polygon points`).
- For a wall, this keeps later opening operations aligned with the moved/rotated wall.
- After every transform or duplicate, immediately run `inspect` and `validate`.
- Prefer cardinal/explicit angles. Do not repeatedly rotate an object by tiny corrective
  angles unless the user explicitly requests that precision.
- Do not use edit tools on loose faces/edges; they intentionally target root Groups/Components.
- Destructive deletion is not exposed in the current Codex Skill. Preserve user work;
  hide an unwanted object and report it when removal is requested but not yet safely exposed.

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

## Stairs and circulation

Choose the stair tool matching the requested circulation:

- `opensu.py create-stair`: one straight flight.
- `opensu_advanced.py create-l-stair`: two flights with one 90-degree landing.
- `opensu_advanced.py create-u-stair`: two return flights with one 180-degree landing.

Use a floor opening when a stair passes through an upper slab. Reject stair results with
impractical tread depth or validation errors.

## Roofs

- `create-flat-roof` creates a rectangular roof slab and optional four-sided parapets.
- Use `create-slab-opening` against the flat-roof group for rectangular skylight/roof access openings.
- Pitched roofs remain outside the current toolset.

## Commands

Core bridge:

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

Advanced bridge:

```text
python scripts/opensu_advanced.py create-l-stair ...
python scripts/opensu_advanced.py create-u-stair ...
python scripts/opensu_advanced.py create-slab-opening ...
python scripts/opensu_advanced.py create-polygon-slab ...
python scripts/opensu_advanced.py create-polygon-ceiling ...
```

Edit/repair bridge:

```text
python scripts/opensu_edit.py rename ...
python scripts/opensu_edit.py set-tag ...
python scripts/opensu_edit.py set-visible ...
python scripts/opensu_edit.py transform ...
python scripts/opensu_edit.py duplicate ...
```

Read `references/tool-contract.md` for core commands and `references/advanced-geometry.md`
for advanced geometry details.

## Building reasoning rules

- Keep column centers on explicit grid/intersection coordinates when a structural grid exists.
- Beam start/end coordinates represent the bottom centerline; their Z values must match.
- Wall thickness is centered on the supplied wall centerline.
- Door/window assemblies read opening metadata from the wall; do not guess rotation.
- Use transparent materials for glazing, not structural/opaque elements.
- Assign Tags to Groups/Components only, never raw edges/faces.
- Re-inspect after structural, opening, facade, circulation, roof, and edit batches.

## Safety and current limits

- Never use arbitrary Ruby execution or invent unsupported SketchUp capabilities.
- Keep architecture in named Groups/Components rather than loose root geometry.
- Editing intentionally targets root Groups/Components; semantic transform/duplicate is
  restricted to OpenSU Groups.
- Destructive delete is not exposed yet.
- Walls and beams are straight in plan; curved walls are not yet exposed.
- Multiple rectangular wall and slab openings are supported where documented.
- Straight, L-shaped, and U-shaped two-flight stairs are supported; spiral/multi-landing stairs are not.
- Polygon floors/ceilings may be concave but may not self-intersect.
- Pitched roofs are not yet exposed.
- If a request exceeds the current tool surface, explain the missing capability instead of pretending it was modeled.
