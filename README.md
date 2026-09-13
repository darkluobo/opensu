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

See `docs/PHASE1_ACCEPTANCE.md` for the manual merge-gate checklist.

## Build an installable RBZ

```bash
python scripts/build_rbz.py
```

This creates `dist/opensu-sketchup-mcp-phase1.rbz` for installation through SketchUp Extension Manager.

## Unit contract

All Phase 1 architecture tools use millimetres at the MCP boundary. The Ruby layer converts with SketchUp's `Numeric#mm` API.

## Provenance and license

This project is forked from `NeoNexAI/sketchup-mcp` and retains its MIT license. See `THIRD_PARTY_NOTICES.md`.
