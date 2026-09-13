---
name: sketchup-modeling
description: >-
  Control a local SketchUp model from Codex through the installed OpenSU/SketchUp MCP
  extension. Use whenever the user asks Codex to create, modify, inspect, materialize,
  or validate architectural SketchUp geometry from natural language, including floors,
  walls, columns, beams, door/window openings, actual door/window assemblies, materials,
  dimensions, and model QA. This skill talks directly to the local SketchUp extension
  and does not require a project checkout or separate MCP configuration.
---

# SketchUp Modeling

Use the bundled `scripts/opensu.py` as the deterministic bridge to the installed
SketchUp extension. Resolve the script relative to this Skill directory; do not copy
it into the user's project. The Skill is intentionally self-contained: the user only
needs the SketchUp extension installed and this Skill installed in Codex.

## Start every SketchUp task

1. Run `python scripts/opensu.py status` from this Skill directory.
2. If it cannot connect, ask the user to open SketchUp and choose
   `Extensions > MCP Server > Start Server`, then retry.
3. Run `python scripts/opensu.py inspect` before changing the model.
4. Treat all architectural dimensions as millimetres.
5. Preserve existing user geometry unless the request explicitly changes it.

## Modeling workflow

Translate the user's natural-language request into explicit geometry, then execute in
this order when applicable:

1. floor/slab
2. primary columns
3. primary beams
4. exterior walls
5. interior walls
6. door/window openings
7. actual door/window assemblies
8. materials
9. inspect
10. validate

Use clear stable names such as `Floor_Level01_001`, `Column_A01_001`,
`Beam_A01_B01_001`, `Wall_South_001`, `Door_South_001`, and `Window_East_001`.

For a door or window, first create the opening, then create the corresponding assembly
in that opening. Prefer targeting walls and entities by stable name rather than copying
raw entity ids into long plans.

After every meaningful batch, run `inspect` and then `validate`. Do not report the job
as complete when validation reports errors or the returned geometry disagrees with the
requested dimensions.

## Commands

Use the bundled script rather than writing ad-hoc socket code:

```text
python scripts/opensu.py status
python scripts/opensu.py inspect
python scripts/opensu.py create-floor ...
python scripts/opensu.py create-column ...
python scripts/opensu.py create-beam ...
python scripts/opensu.py create-wall ...
python scripts/opensu.py create-opening ...
python scripts/opensu.py create-door ...
python scripts/opensu.py create-window ...
python scripts/opensu.py apply-material ...
python scripts/opensu.py validate
```

Read `references/tool-contract.md` when exact command arguments or current geometry
constraints are needed.

## Building reasoning rules

- Use floor top elevation as the normal wall/column base unless the user specifies otherwise.
- Keep column centers on explicit grid/intersection coordinates when a structural grid exists.
- Beam start/end coordinates represent the bottom centerline; keep their Z equal in the current implementation.
- Wall thickness is centered on the supplied wall centerline.
- Create openings before door/window assemblies.
- Door/window assemblies read the opening metadata from the wall, so do not manually guess rotation.
- Use materials after geometry is stable; transparent materials are appropriate for glass only.
- Re-inspect after structural and opening batches before moving on.

## Safety and current limits

- Never use arbitrary Ruby execution or invent unsupported SketchUp capabilities.
- Keep architectural geometry in named Groups/Components rather than loose root geometry.
- Walls and beams are straight and horizontal in plan in the current implementation.
- The current opening system supports one rectangular opening per OpenSU wall.
- Door/window assemblies can only target openings created by this OpenSU architecture workflow.
- Columns are rectangular vertical prisms; beams are rectangular straight prisms.
- Complex stairs, roofs, curved walls, multi-opening storefronts, and curtain-wall grids are not yet exposed.
- If the request exceeds the current tool surface, explain the missing capability instead of pretending it was modeled.
