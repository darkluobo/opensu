# OpenSU

**OpenSU** is an open-source AI modeling agent for SketchUp. It connects Codex to a local SketchUp extension so natural-language instructions, architectural drawings, semantic building data, and validation workflows can become structured `.skp` geometry.

> Current development checkpoint: **v1.13.0 / Phase 5.3**

## What OpenSU can do

- Natural-language architectural modeling in millimetres
- Floors, walls, columns, beams, doors, windows, curtain walls, ceilings, stairs, roofs, and openings
- Multi-opening walls and semantic door/window assemblies
- Safe model editing, Tags, transforms, duplication, diagnostics, batch repair, and controlled deletion
- Drawing reconstruction through auditable Plan Specs
- Multi-sheet plan/elevation/section evidence reconciliation
- Persistent Levels, Grids, and functional Spaces inside the SketchUp model
- Grid-driven structure such as `3/B` column placement and beam spans
- Space-driven partition generation when the drawing explicitly supports those walls
- Geometry and semantic validation before completion

## Architecture

```text
User
  ↓
Codex + $opensu Skill
  ↓
OpenSU deterministic Skill bridges
  ↓
127.0.0.1:9876 JSON-RPC
  ↓
OpenSU SketchUp extension
  ↓
SketchUp Ruby API
  ↓
.skp model
```

The normal end-user path requires only the **OpenSU RBZ extension** and the bundled Codex Skill. Repository checkout and project-level MCP configuration are optional development workflows.

## Safety model

OpenSU keeps the hardened localhost-only design inherited from the NeoNexAI SketchUp MCP project:

- listens on `127.0.0.1` only
- no arbitrary Ruby execution
- bounded modeling/editing tools
- named Groups/Components rather than loose architectural geometry
- SketchUp undo operations around mutations
- explicit validation and uncertainty handling

## Build the SketchUp extension

```bash
python scripts/build_rbz.py
```

The current build creates:

```text
dist/opensu-v1.13.0.rbz
```

Install the RBZ through SketchUp Extension Manager, restart SketchUp, then start:

```text
Extensions > MCP Server > Start Server
```

## Codex Skill

The Skill lives at:

```text
skills/opensu/
```

Invoke it with:

```text
$opensu
```

A typical request can be as simple as:

```text
$opensu
根据项目目录里的整套4S店图纸建立当前 SketchUp 模型。
先索引图纸、轴网和功能区，校核平面/立面/剖面尺寸，
确认后自动建模，最后 inspect、validate、diagnose。
```

## Project status

Phase 5.3 includes drawing-set understanding, persistent architectural semantics, and grid/Space-driven modeling. The next planned work is broader batch structural generation and higher-level dealership layout automation.

## Provenance and license

OpenSU is based on the MIT-licensed `NeoNexAI/sketchup-mcp` project and retains the MIT license. See `THIRD_PARTY_NOTICES.md` for attribution and third-party notices.
