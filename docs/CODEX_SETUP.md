# OpenSU + Codex setup

OpenSU supports two workflows. **Normal users should use the SketchUp RBZ extension plus the bundled `$sketchup-modeling` Skill.** The repository-scoped MCP configuration remains available for development and debugging.

## Recommended end-user setup

1. Build or download `opensu-v1.13.0.rbz`.
2. Install it with SketchUp Extension Manager.
3. Restart SketchUp.
4. Start `Extensions > MCP Server > Start Server`.
5. Install the Skill from `skills/sketchup-modeling/` into Codex.
6. Restart Codex after installing or updating the Skill.

The Skill talks directly to the local OpenSU extension at `127.0.0.1:9876`; no repository checkout or separate MCP configuration is required for normal use.

Typical invocation:

```text
$sketchup-modeling
检查当前 SketchUp，然后根据我的建筑要求建模，完成后 inspect、validate、diagnose。
```

## Development MCP setup

For contributors working from this repository:

```powershell
python -m pip install -e .
```

The optional project-scoped MCP configuration is in `.codex/config.toml`. It launches the Python MCP compatibility layer while keeping SketchUp itself as the source of truth.

## Connection checks

The SketchUp extension must be running locally. The Ruby Console should report that the server is listening on:

```text
127.0.0.1:9876
```

If Codex cannot connect:

1. Confirm OpenSU is enabled in SketchUp Extension Manager.
2. Restart SketchUp after replacing the RBZ.
3. Start `MCP Server > Start Server`.
4. Confirm port `9876` is not occupied by another process.
5. Restart Codex after changing or reinstalling the Skill.

Do not publish new modeling capabilities until they pass automated CI and a real SketchUp geometry/semantic acceptance test.
