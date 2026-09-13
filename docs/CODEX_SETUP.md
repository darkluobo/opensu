# Codex setup

This project is configured for Codex only. The project-scoped MCP configuration is in `.codex/config.toml`, and modeling behavior is defined in `AGENTS.md`.

## One-time setup

From the repository root on Windows:

```powershell
python -m pip install -e .
```

Then open SketchUp, ensure the OpenSU/SketchUp MCP RBZ is installed, and start the local server:

`Extensions > MCP Server > Start Server`

The Ruby Console should show that the server is listening on `127.0.0.1:9876`.

## Start Codex

Open a terminal in this repository and run Codex from the repository root. When Codex asks whether to trust this project, trust it so project-scoped `.codex/config.toml` is loaded.

Codex should discover the MCP server named `opensu` and expose only these Phase 1 tools:

- `sketchup_status`
- `sketchup_inspect_model`
- `sketchup_create_floor`
- `sketchup_create_wall`
- `sketchup_create_opening`
- `sketchup_validate_model`

The MCP process is launched by Codex with:

```text
python -m sketchup_mcp.phase1_server
```

with `PYTHONPATH=src` and the SketchUp bridge at `127.0.0.1:9876`.

## First Codex test

Ask Codex:

```text
Check the SketchUp connection, inspect the current model, and tell me whether it is ready for architectural modeling. Do not modify the model.
```

Then try:

```text
Build an 8 m × 6 m room. Use a 150 mm floor slab, 3 m high walls, and 200 mm wall thickness. Put a 900 × 2100 mm door on the south wall and an 1800 × 1500 mm window with a 900 mm sill on the east wall. Inspect and validate the model before you say it is finished.
```

## Troubleshooting

If Codex cannot initialize the `opensu` MCP server:

1. Run `python -m pip install -e .` again from the repo root.
2. Confirm `python` is available in the same terminal environment where Codex runs.
3. Confirm SketchUp is open and `MCP Server > Start Server` has been clicked.
4. Confirm port `9876` is not occupied by another process.
5. Restart Codex after changing `.codex/config.toml`.

Do not merge or publish new modeling capabilities until they pass both automated CI and a real SketchUp geometry test.
