# Phase 1 — Architecture Modeling MVP

## Goal

Enable an AI agent to create and verify a simple architectural room in SketchUp through bounded MCP tools.

## Acceptance model

- Room footprint: 8000 x 6000 mm
- Wall height: 3000 mm
- Wall thickness: 200 mm
- South wall: 900 x 2100 mm door opening
- East wall: 1800 x 1500 mm window opening
- Window sill: 900 mm

## Required tools

1. `sketchup_inspect_model`
2. `sketchup_create_floor`
3. `sketchup_create_wall`
4. `sketchup_create_opening`
5. `sketchup_validate_model`

## Unit contract

All architecture-facing MCP tools use millimetres at the protocol boundary.
The Ruby extension converts millimetres to SketchUp Length values internally.
Raw primitive tools remain legacy-compatible until explicitly migrated.

## Modeling rules

- Architectural elements must be isolated in Groups or Components.
- No loose geometry in the active model root for architecture tools.
- Every created architectural entity must have a stable name.
- Mutating operations must use `model.start_operation` and `model.commit_operation` so a user can undo them cleanly.
- Tool responses must return entity id, name, type, dimensions, and bounds when applicable.
- Validation must be read-only.

## Phase 1 sequence

1. Inspect current model.
2. Create floor.
3. Create four walls.
4. Cut door and window openings.
5. Inspect model again.
6. Validate expected dimensions, hierarchy, and geometry.
7. Fix issues until validation passes.

## Non-goals

- Rendering
- Furniture placement
- Full BIM semantics
- Arbitrary Ruby execution
- Automatic interpretation of plans/images
