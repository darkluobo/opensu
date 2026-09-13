---
name: sketchup-modeling
description: >-
  Control a local SketchUp model from Codex through the installed OpenSU/SketchUp MCP
  extension. Use whenever the user asks Codex to create, modify, inspect, materialize,
  or validate architectural SketchUp geometry from natural language, including levels,
  rectangular or polygon floors/ceilings, slab and roof openings, walls, columns, beams,
  straight/L/U stairs with landings, flat roofs, multiple door/window openings per wall,
  actual door/window assemblies, glass curtain walls/storefronts, materials, dimensions,
  and model QA. This skill talks directly to the local SketchUp extension and does not
  require a project checkout or separate MCP configuration.
---

# SketchUp Modeling

Use the bundled scripts as deterministic bridges to the installed SketchUp extension:

- `scripts/opensu.py` for the stable core toolset.
- `scripts/opensu_advanced.py` for L/U stairs, slab/roof openings, and polygon slabs/ceilings.

Resolve both scripts relative to this Skill directory. Do not copy them into the user's
project and do not write ad-hoc socket/Ruby code when an exposed command already exists.
The user only needs the SketchUp extension installed and this Skill installed in Codex.

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
2. floor/slab, including polygon slabs where the footprint is not rectangular
3. slab circulation/shaft openings when needed
4. primary columns
5. primary beams
6. opaque exterior/interior walls
7. all door/window openings for each wall
8. actual door/window assemblies
9. curtain-wall/storefront assemblies
10. ceilings, using polygon ceilings for irregular rooms
11. stairs/circulation
12. flat roof/parapets and roof openings
13. materials
14. inspect
15. validate

Use stable semantic names such as `Level_01`, `Floor_Level01_001`, `SlabOpening_Stair_001`,
`Ceiling_Level01_001`, `Column_A01_001`, `Beam_A01_B01_001`, `Wall_South_001`,
`Door_South_001`, `Window_East_001`, `Stair_L_L01_L02_001`, `Stair_U_L01_L02_001`,
`CurtainWall_Showroom_001`, and `Roof_Main_001`.

## Levels and multi-storey reasoning

- Use `define-level` for named storey datums such as `Level_01=0`, `Level_02=4500`,
  and `Roof=9000`.
- Level metadata is model-level data, not fake geometry. `inspect` returns the level list.
- Treat a level elevation as the floor datum unless the user states another convention.
- When `level_name` is supplied, it must match an existing level exactly.
- Use floor top elevation as the normal wall/column base unless specified otherwise.
- For a second floor, explicitly compute Z from the requested level elevation instead of
  stacking dimensions approximately.

## Floors, ceilings, and slab openings

- Use rectangular `create-floor` / `create-ceiling` when a rectangle is sufficient.
- Use `opensu_advanced.py create-polygon-slab` or `create-polygon-ceiling` for a simple
  horizontal non-self-intersecting polygon, including concave footprints.
- Polygon vertices must all use the same Z and must be supplied in boundary order.
- `create-slab-opening` currently targets rectangular OpenSU `floor`, `ceiling`, or
  `flat_roof` geometry. It may be called repeatedly on the same target for multiple
  non-overlapping stair, elevator, equipment, or skylight openings.
- Keep every slab opening strictly inside the slab boundary. The extension regenerates
  the complete closed horizontal shell instead of relying on destructive boolean tools.
- Do not claim arbitrary-polygon slab openings are supported yet; openings currently
  target rectangular floors/ceilings/flat roofs only.

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

## Stairs and circulation

Choose the stair tool that matches the requested circulation:

- `opensu.py create-stair`: one straight flight.
- `opensu_advanced.py create-l-stair`: two flights with one 90-degree landing.
- `opensu_advanced.py create-u-stair`: two return flights with one 180-degree landing.

For L/U stairs:

- Define origin, initial cardinal direction (`x+`, `x-`, `y+`, `y-`), left/right turn,
  flight run lengths, width, and final elevation.
- The extension calculates a practical total riser count from target riser height unless
  an explicit riser count is supplied, then splits the risers between both flights.
- The landing is a separate closed solid and each tread mass is an isolated closed solid.
- Reject results with tread depth under the extension minimum or validation errors.
- Use a floor opening sized around the stair when the stair passes through an upper slab.

## Roofs

- `create-flat-roof` creates a rectangular roof slab and optional four-sided parapets.
- Use `create-slab-opening` against the flat-roof group for rectangular skylight/roof
  access openings; parapets remain intact while the `Roof_Slab` shell is regenerated.
- Pitched roofs and arbitrary-polygon roof openings are still outside the current toolset.

After every meaningful batch, run `inspect` and then `validate`. Do not report the job
as complete when validation reports errors or dimensions disagree with the request.

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

Read `references/tool-contract.md` for the core command contract and
`references/advanced-geometry.md` for the advanced commands.

## Building reasoning rules

- Keep column centers on explicit grid/intersection coordinates when a structural grid exists.
- Beam start/end coordinates represent the bottom centerline; their Z values must match.
- Wall thickness is centered on the supplied wall centerline.
- Door/window assemblies read their opening metadata from the wall; do not guess rotation.
- Use transparent materials for glazing, not for structural/opaque elements.
- Re-inspect after structural, opening, facade, circulation, and roof batches.
- When adding a stair through an upper floor, model the floor opening explicitly rather
  than allowing the stair and slab to occupy the same volume.

## Safety and current limits

- Never use arbitrary Ruby execution or invent unsupported SketchUp capabilities.
- Keep architecture in named Groups/Components rather than loose root geometry.
- Walls and beams are straight and horizontal in plan in the current implementation.
- Multiple non-overlapping rectangular openings are supported on one OpenSU wall.
- Multiple non-overlapping rectangular openings are supported on rectangular floors,
  ceilings, and flat-roof slabs.
- Door/window assemblies can only target OpenSU opening metadata.
- Columns are rectangular vertical prisms; beams are rectangular straight prisms.
- Curtain walls are straight framed/glazed grids; curved curtain walls are not supported.
- Straight, L-shaped, and U-shaped two-flight stairs are supported; multi-landing/spiral
  stairs are not yet exposed.
- Polygon floors/ceilings may be concave but may not self-intersect.
- Slab openings do not yet target polygon slabs/ceilings.
- Pitched roofs and curved walls are not yet exposed.
- If a request exceeds the current tool surface, explain the missing capability instead
  of pretending it was modeled.
