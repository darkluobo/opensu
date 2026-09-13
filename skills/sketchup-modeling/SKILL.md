---
name: sketchup-modeling
description: >-
  Professional SketchUp modeling workflow for architecture-oriented tasks.
  Use this when the user asks to create, modify, inspect, or validate building
  geometry through the SketchUp MCP architecture tools.
---

# SketchUp Modeling Skill

## Core principle

Model deliberately, inspect frequently, and verify before declaring completion.
Do not assume a geometry operation succeeded just because a tool call returned.

## Session start

1. Call `sketchup_status`.
2. Call `sketchup_inspect_model` before creating or modifying architecture.
3. Treat all architecture-tool dimensions as millimetres.
4. Preserve existing user geometry unless the task explicitly requires changes.

## Architectural modeling order

For a new building or room, prefer this sequence:

1. floor / slab
2. primary exterior walls
3. interior walls
4. openings
5. columns and beams when required
6. components and materials
7. scenes / cameras
8. final model inspection and validation

## Geometry rules

- Never intentionally create loose architectural geometry at model root.
- Use named Groups or Components for architectural elements.
- Keep walls individually addressable unless a workflow explicitly requires aggregation.
- Use clear stable names such as `Wall_South_001`, `Floor_Level01_001`.
- Do not use arbitrary Ruby execution.
- Prefer bounded architecture tools over primitive workarounds.
- Do not silently convert architecture dimensions into legacy primitive units; architecture tools already accept mm.

## Phase 1 architecture tools

The following tools are available:

- `sketchup_inspect_model`
- `sketchup_create_floor`
- `sketchup_create_wall`
- `sketchup_create_opening`
- `sketchup_validate_model`

### Current constraints

- Walls are straight and horizontal in plan; start/end share the same base Z.
- Wall thickness is centered on the supplied centerline.
- Phase 1 supports one opening per wall.
- Openings must target walls created by `sketchup_create_wall`.
- Openings must remain away from wall endpoints.
- Use `sill_height_mm=0` for door-like openings.

If a task exceeds these constraints, explain the limitation rather than fabricating success or falling back to arbitrary Ruby.

## Verification loop

After a meaningful modeling batch:

1. call `sketchup_inspect_model`
2. compare created geometry against requested dimensions and placement
3. call `sketchup_validate_model`
4. repair discrepancies
5. inspect and validate again

Do not tell the user the model is complete until the relevant checks pass.

## Phase 1 room recipe

For the acceptance room:

1. Create an `8000 x 6000 mm` floor.
2. Create four `3000 mm` high, `200 mm` thick walls.
3. Add a `900 x 2100 mm` south-wall door opening with sill `0`.
4. Add an `1800 x 1500 mm` east-wall window opening with sill `900 mm`.
5. Inspect.
6. Validate.
7. Fix any reported errors before completion.
