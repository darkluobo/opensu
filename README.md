# SketchUp MCP — OpenSU architecture MVP

A hardened SketchUp MCP bridge extended with bounded architectural modeling tools.

This fork keeps the original security model: **no arbitrary Ruby execution** and the SketchUp socket listens only on `127.0.0.1`. Phase 1 adds a millimetre-based architecture layer for model inspection, floors, straight walls, rectangular openings, and model validation.

## Current Phase 1 status

Implemented on `phase1-architecture-mvp`:

- `sketchup_inspect_model`
- `sketchup_create_floor`
- `sketchup_create_wall`
- `sketchup_create_opening`
- `sketchup_validate_model`
- millimetres (`mm`) as the architecture protocol unit
- OpenSU metadata on generated architectural groups
- per-operation SketchUp undo support
- Python wrapper tests
- Ruby architecture code split from the original large `main.rb`
- manifold-solid validation for generated architecture groups
- reproducible `.rbz` packaging script

The original 13 curated SketchUp tools remain available as well.

> Phase 1 is still a development MVP. Before merging to `main`, the acceptance room must be verified inside a real SketchUp instance.

## Architecture

```text
MCP client (Codex / Claude / other MCP client)
        │
        │ MCP over stdio
        ▼
Python MCP server
        │
        │ local JSON-RPC/TCP · 127.0.0.1:9876
        ▼
SketchUp Ruby extension
        │
        ├─ original bounded modeling tools
        └─ OpenSU architecture layer
                │
                ▼
             SketchUp
```

## Requirements

- SketchUp 2021 or later
- Python 3.10+
- `uv`/`uvx` or a normal Python virtual environment

## Development installation

### 1. Install the SketchUp extension

Copy the repository's top-level `su_mcp.rb` **and** the `su_mcp/` folder into:

```text
%AppData%\SketchUp\SketchUp 20XX\SketchUp\Plugins\
```

Restart SketchUp, then use:

```text
Extensions → SketchUp MCP → Start Server
```

The server listens on `127.0.0.1:9876`.

### Build an installable RBZ

Instead of copying files manually, build a SketchUp Extension Manager package:

```bash
python scripts/build_rbz.py
```

This creates:

```text
dist/opensu-sketchup-mcp-phase1.rbz
```

Install that file through SketchUp `Window → Extension Manager → Install Extension`.

### 2. Run the Python MCP server from this fork

For development, clone this repository and install it editable:

```bash
python -m venv .venv
.venv\Scripts\activate
pip install -e . pytest
python -m sketchup_mcp
```

The Phase 1 Python entrypoint registers both the original tool surface and the architecture tools.

## Architecture tools

### `sketchup_inspect_model`

Read-only inspection of root-level groups/components, loose root geometry, tags, names, OpenSU type metadata, edit context, and bounds in millimetres.

Use this before architectural edits and again after a modeling batch.

### `sketchup_create_floor`

Creates an isolated rectangular floor `Group`.

Inputs are in millimetres:

- width
- depth
- thickness
- origin `[x, y, z]`
- optional stable name

### `sketchup_create_wall`

Creates an isolated straight wall `Group` from a centerline.

Inputs are in millimetres:

- start `[x, y, z]`
- end `[x, y, z]`
- height
- thickness
- optional stable name

Phase 1 requires start and end to use the same base elevation. Arbitrary horizontal wall angles are supported.

### `sketchup_create_opening`

Creates one rectangular opening in an OpenSU wall.

Inputs are in millimetres:

- target wall id
- offset from wall start
- width
- height
- sill height (`0` for a door)
- optional semantic type/name

Phase 1 currently supports **one opening per wall**. Multiple openings per wall are a later milestone.

### `sketchup_validate_model`

Read-only structural validation for the current OpenSU architectural model. It checks items such as:

- loose root-level faces/edges
- duplicate architecture names
- required floor/wall metadata
- missing geometry
- invalid positive dimensions
- malformed opening metadata
- floor/wall groups that are not closed manifold solids

## Unit contract

The new architecture tools always use **millimetres at the MCP boundary**, regardless of the SketchUp model display unit.

The Ruby layer converts millimetres with SketchUp's `Numeric#mm` API before creating geometry and converts inspected bounds back to millimetres before returning them.

The original 13 legacy tools still retain their existing unit behavior. Do not mix their numeric geometry contract with the new architecture tool contract without explicit conversion.

## Phase 1 acceptance model

The first real-SketchUp acceptance test is:

```text
Floor: 8000 × 6000 × 150 mm
Wall height: 3000 mm
Wall thickness: 200 mm

South wall: 900 × 2100 mm door
East wall: 1800 × 1500 mm window
Window sill: 900 mm
```

Expected workflow:

```text
sketchup_status
→ sketchup_inspect_model
→ sketchup_create_floor
→ sketchup_create_wall × 4
→ sketchup_create_opening × 2
→ sketchup_inspect_model
→ sketchup_validate_model
```

Walls should normally start at `z = 150 mm` in this acceptance model so they sit on the top face of the 150 mm floor slab.

See `docs/PHASE1_ACCEPTANCE.md` for the exact manual merge-gate checklist and suggested tool parameters.

## Original bounded tools

The original tool surface remains available for general geometry, transforms, materials, booleans, edge treatment, woodworking joints, selection, and export. Arbitrary `eval_ruby` remains intentionally unavailable.

## Development safety rules

- No arbitrary Ruby evaluation.
- Keep the socket bound to localhost.
- Architectural geometry must be grouped, named, inspectable, and solid where appropriate.
- New mutating tools should use `model.start_operation` / `commit_operation` and abort on errors.
- Prefer bounded semantic commands over passing raw Ruby code.
- Run validation after meaningful modeling batches.

## Testing

The repository CI runs Python compilation and pytest. Phase 1 also adds Ruby syntax checks so loader/architecture files can fail early before manual SketchUp testing.

Real SketchUp remains required for final geometry verification because CI does not embed SketchUp's Ruby runtime or modeling kernel.

## Provenance and license

This project is forked from `NeoNexAI/sketchup-mcp` and retains its MIT license. See `THIRD_PARTY_NOTICES.md` for attribution and the policy for incorporating additional upstream code.
