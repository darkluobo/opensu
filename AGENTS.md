# OpenSU / SketchUp Agent Instructions

This repository exposes a bounded SketchUp MCP toolset for Codex. Treat SketchUp as the source of truth for model state.

## Required workflow

1. Call `sketchup_status` first. If it is not connected, stop and tell the user to open SketchUp and run `Extensions > MCP Server > Start Server`.
2. Call `sketchup_inspect_model` before making architectural edits.
3. Build with the dedicated architecture tools only:
   - `sketchup_create_floor`
   - `sketchup_create_wall`
   - `sketchup_create_opening`
4. Call `sketchup_inspect_model` after a modeling batch.
5. Call `sketchup_validate_model` before claiming completion.
6. If validation fails, report the exact validation errors and repair only what can be safely repaired with the exposed tools. Never claim success while `valid` is false.

## Modeling conventions

- Architecture tool dimensions and coordinates are always millimetres.
- Keep all generated architectural geometry inside named SketchUp Groups. Do not intentionally create loose root faces or edges.
- Use stable semantic names such as `Floor_001`, `Wall_South`, `Wall_East`, `Door_South_001`, and `Window_East_001`.
- For a floor slab, default thickness is 150 mm only when the user does not specify one.
- For walls, default height is 3000 mm and thickness is 200 mm only when the user does not specify them.
- Walls sit on top of the slab unless the user explicitly requests another elevation. Example: a 150 mm slab at z=0 means wall base z=150 mm.
- Wall start/end points define the wall centerline.
- Phase 1 supports straight walls whose endpoints share one base elevation.
- Phase 1 supports one rectangular opening per wall.
- A door normally uses `sill_height_mm=0`; a window uses the requested sill height.
- Do not invent dimensions that materially affect the design. Ask the user when a missing dimension is important and no sensible project default is defined here.

## Safety and scope

- Do not expose or execute arbitrary Ruby in SketchUp.
- Do not bypass the curated MCP tools with ad-hoc socket code unless the user is explicitly debugging the MCP bridge itself.
- Do not use legacy component/boolean/woodworking tools for architectural work unless the user explicitly asks for those capabilities.
- Inspection and validation are read-only and should never be skipped just to save time.

## Natural-language room example

For a request such as "build an 8 m × 6 m room, 3 m walls, 200 mm thick, door on south, window on east":

1. status
2. inspect
3. create an 8000 × 6000 floor
4. create four named walls at the slab-top elevation
5. inspect to retrieve wall entity ids
6. create the requested openings using those wall ids
7. inspect again
8. validate
9. summarize exactly what was created and any Phase 1 limitations
