# Phase 1 — Architecture Modeling MVP

## Goal

Enable an AI agent to create and verify a simple architectural room in SketchUp through bounded MCP tools.

## Implementation status

Implemented on `phase1-architecture-mvp`:

- `sketchup_inspect_model`
- `sketchup_create_floor`
- `sketchup_create_wall`
- `sketchup_create_opening`
- `sketchup_validate_model`

The Python MCP layer and Ruby files pass syntax-level checks. A live SketchUp integration test is still required before Phase 1 is considered production-ready.

## Acceptance model

- Room footprint: 8000 x 6000 mm
- Wall height: 3000 mm
- Wall thickness: 200 mm
- South wall: 900 x 2100 mm door opening
- East wall: 1800 x 1500 mm window opening
- Window sill: 900 mm

## Unit contract

All architecture-facing MCP tools use millimetres at the protocol boundary.
The Ruby extension converts millimetres to SketchUp Length values internally.
Raw primitive tools remain legacy-compatible until explicitly migrated.

## Modeling rules

- Architectural elements are isolated in root-level Groups.
- No loose architectural geometry is intentionally created at model root.
- Every created architectural entity receives a stable name and `OpenSU` metadata.
- Mutating operations use `model.start_operation` / `commit_operation` so each tool call can be undone cleanly.
- Tool responses return entity id, name, type, dimensions, and bounds when applicable.
- Validation is read-only.

## Phase 1 tool behavior

### `sketchup_inspect_model`

Returns root group/component metadata, edit context, tags, loose geometry counts, and world-space bounds in millimetres.

### `sketchup_create_floor`

Creates one rectangular floor Group from width, depth, thickness, origin, and optional name.

### `sketchup_create_wall`

Creates one straight wall Group from a centerline. Start and end must share the same Z elevation in Phase 1. Wall thickness is centered on the supplied centerline.

### `sketchup_create_opening`

Creates one rectangular opening in an OpenSU wall. Phase 1 currently supports one opening per wall and requires the opening to remain away from wall endpoints. `sill_height_mm=0` represents a door-like opening.

### `sketchup_validate_model`

Checks root loose geometry, duplicate architecture names, required OpenSU metadata, and basic floor/wall invariants. It returns `valid`, `errors`, `warnings`, and a summary.

## Acceptance sequence

1. `sketchup_status`
2. `sketchup_inspect_model`
3. Create an 8000 x 6000 x 150 mm floor.
4. Create four 3000 mm-high, 200 mm-thick walls.
5. Create a 900 x 2100 mm door opening in the south wall.
6. Create an 1800 x 1500 mm window opening in the east wall with a 900 mm sill.
7. `sketchup_inspect_model`
8. `sketchup_validate_model`
9. Fix any validation errors and repeat inspection/validation.

## Known Phase 1 limitations

- Straight walls only.
- One opening per wall.
- Openings are supported only on walls created by the OpenSU architecture tool.
- No automatic floor/wall hierarchy containers yet; elements are named root Groups.
- No rendering, furniture placement, full BIM semantics, arbitrary Ruby execution, or automatic interpretation of plans/images.
