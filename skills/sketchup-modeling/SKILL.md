---
name: sketchup-modeling
description: >-
  Control a local SketchUp model from Codex through the installed OpenSU/SketchUp MCP
  extension. Use whenever the user asks Codex to create, modify, inspect, materialize,
  or validate architectural SketchUp geometry from natural language, including levels,
  floors, ceilings, walls, columns, beams, stairs, flat roofs, multiple door/window
  openings per wall, actual door/window assemblies, glass curtain walls/storefronts,
  materials, dimensions, and model QA. This skill talks directly to the local SketchUp
  extension and does not require a project checkout or separate MCP configuration.
---

# SketchUp Modeling

Use the bundled `scripts/opensu.py` as the deterministic bridge to the installed
SketchUp extension. Resolve the script relative to this Skill directory; do not copy
it into the user's project. The user only needs the SketchUp extension installed and
this Skill installed in Codex.

## Start every SketchUp task

1. Run `python scripts/opensu.py status` from this Skill directory.
2. If it cannot connect, ask the user to open SketchUp and choose
   `Extensions > MCP Server > Start Server`, then retry.
3. Run `python scripts/opensu.py inspect` before changing the model.
4. Treat all architectural dimensions as millimetres.
5. Preserve existing user geometry unless the request explicitly changes it.
6. For multi-storey work, inspect existing `levels` first. Define missing levels before
   creating level-dependent geometry.

## Modeling workflow

Translate the user's request into explicit geometry and normally execute in this order:

1. define levels/storey elevations
2. floor/slab
3. primary columns
4. primary beams
5. opaque exterior/interior walls
6. all door/window openings for each wall
7. actual door/window assemblies
8. curtain-wall/storefront assemblies
9. ceilings
10. stairs/circulation
11. flat roof/parapets
12. materials
13. inspect
14. validate

Use stable semantic names such as `Level_01`, `Floor_Level01_001`, `Ceiling_Level01_001`,
`Column_A01_001`, `Beam_A01_B01_001`, `Wall_South_001`, `Door_South_001`,
`Window_East_001`, `Stair_L01_L02_001`, `CurtainWall_Showroom_001`, and `Roof_Main_001`.

## Levels and multi-storey reasoning

- Use `define-level` for named storey datums such as `Level_01=0`, `Level_02=4500`,
  and `Roof=9000`.
- Level metadata is model-level data, not fake geometry. `inspect` returns the level list.
- Treat a level elevation as the floor datum unless the user states another convention.
- When `level_name` is supplied to ceilings, stairs, or roofs, it must match an existing
  level exactly; do not invent an undeclared level name.
- Use floor top elevation as the normal wall/column base unless specified otherwise.
- For a second floor, explicitly compute Z from the requested level elevation instead of
  stacking dimensions approximately.

## Openings and storefront logic

- A single OpenSU wall may contain multiple rectangular openings. Add them sequentially
  with `create-opening`; the extension regenerates the complete closed wall shell.
- Openings may not overlap. Keep reasonable solid wall strips between separate openings
  unless the design explicitly calls for touching edges.
- Create every required opening before creating its door/window assembly.
- When a wall has multiple openings, always pass `--opening-name` to `create-door` or
  `create-window` so the intended opening is unambiguous.
- For large glazed showroom facades, dealership fronts, or storefront grids, prefer
  `create-curtain-wall` instead of approximating the facade with many ordinary windows.

## Stairs, ceilings, and roofs

- `create-stair` currently creates a straight run between two 3D centerline endpoints.
  The end Z must be above the start Z. The extension calculates riser count from the
  target riser height unless an explicit riser count is requested.
- Do not accept a stair result whose calculated tread depth is impractically small or
  whose validation reports non-manifold step solids.
- `create-ceiling` creates a rectangular solid ceiling slab; its origin is the lower face.
- `create-flat-roof` creates a rectangular roof slab and, when parapet height is greater
  than zero, four closed parapet solids around the perimeter.
- For roofs or stairs beyond these simple forms, report the current limitation rather
  than pretending a complex result was produced.

After every meaningful batch, run `inspect` and then `validate`. Do not report the job
as complete when validation reports errors or dimensions disagree with the request.

## Commands

Use the bundled script rather than writing ad-hoc socket code:

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

Read `references/tool-contract.md` when exact arguments or current geometry constraints
are needed.

## Building reasoning rules

- Keep column centers on explicit grid/intersection coordinates when a structural grid exists.
- Beam start/end coordinates represent the bottom centerline; their Z values must match.
- Wall thickness is centered on the supplied wall centerline.
- Door/window assemblies read their opening metadata from the wall; do not guess rotation.
- Use transparent materials for glazing, not for structural/opaque elements.
- Re-inspect after structural, opening, facade, circulation, and roof batches.

## Safety and current limits

- Never use arbitrary Ruby execution or invent unsupported SketchUp capabilities.
- Keep architecture in named Groups/Components rather than loose root geometry.
- Walls and beams are straight and horizontal in plan in the current implementation.
- Multiple non-overlapping rectangular openings are supported on one OpenSU wall.
- Door/window assemblies can only target OpenSU opening metadata.
- Columns are rectangular vertical prisms; beams are rectangular straight prisms.
- Curtain walls are straight framed/glazed grids; curved curtain walls are not supported.
- Stairs are straight runs only; U-shaped/L-shaped stairs and landings are not yet exposed.
- Ceilings and flat roofs are rectangular; arbitrary polygons and pitched roofs are not yet exposed.
- Curved walls are not yet exposed.
- If a request exceeds the current tool surface, explain the missing capability instead
  of pretending it was modeled.
