---
name: sketchup-modeling
description: >-
  Control a local SketchUp model from Codex through the installed OpenSU/SketchUp MCP
  extension. Use whenever the user asks Codex to create, modify, inspect, or validate
  SketchUp architecture from natural language, including rooms, floors, walls, doors,
  windows, dimensions, and model QA. This skill talks directly to the local SketchUp
  extension and does not require a project checkout or separate MCP configuration.
---

# SketchUp Modeling

Use the bundled `scripts/opensu.py` as the deterministic bridge to the installed
SketchUp extension. Resolve the script relative to this Skill directory; do not copy
it into the user's project.

## Start every SketchUp task

1. Run `python scripts/opensu.py status` from this Skill directory.
2. If it cannot connect, ask the user to open SketchUp and choose
   `Extensions > MCP Server > Start Server`, then retry.
3. Run `python scripts/opensu.py inspect` before changing the model.
4. Treat all architecture dimensions as millimetres.
5. Preserve existing user geometry unless the request explicitly changes it.

## Modeling workflow

Translate the user's natural-language request into explicit geometry, then execute in
this order when applicable:

1. floor/slab
2. exterior walls
3. interior walls
4. openings
5. inspect
6. validate

Use clear stable names such as `Floor_Level01_001`, `Wall_South_001`,
`Door_South_001`, and `Window_East_001`.

After every meaningful batch, run `inspect` and then `validate`. Do not report the job
as complete when validation reports errors or the returned geometry disagrees with the
requested dimensions.

## Commands

Use the bundled script rather than writing ad-hoc socket code:

```text
python scripts/opensu.py status
python scripts/opensu.py inspect
python scripts/opensu.py create-floor ...
python scripts/opensu.py create-wall ...
python scripts/opensu.py create-opening ...
python scripts/opensu.py validate
```

Read `references/tool-contract.md` when exact command arguments or current Phase 1
constraints are needed.

## Safety and limits

- Never use arbitrary Ruby execution or invent unsupported SketchUp capabilities.
- Keep architectural geometry in named Groups/Components rather than loose root geometry.
- Walls are straight in Phase 1 and their start/end Z values must match.
- Phase 1 supports one rectangular opening per OpenSU wall.
- Openings can only target walls created by this OpenSU architecture workflow.
- If the request exceeds the current tool surface, explain the missing capability instead
  of pretending it was modeled.
