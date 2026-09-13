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
3. Treat architecture-tool dimensions as millimetres.
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

## Verification loop

After a meaningful modeling batch:

1. inspect the model
2. compare created geometry against requested dimensions and placement
3. call validation when available
4. repair discrepancies
5. validate again

Do not tell the user the model is complete until the relevant checks pass.

## Phase 1 architecture tools

The initial architecture surface is expected to provide:

- `sketchup_inspect_model`
- `sketchup_create_floor`
- `sketchup_create_wall`
- `sketchup_create_opening`
- `sketchup_validate_model`

If a required tool is not implemented yet, state the limitation instead of fabricating success.
