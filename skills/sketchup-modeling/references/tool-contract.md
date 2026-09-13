# OpenSU command contract

The Skill bridge talks directly to the local SketchUp extension on `127.0.0.1:9876`.
All architecture dimensions are millimetres.

## Commands

### Status

```text
python scripts/opensu.py status
```

Checks that the SketchUp extension server is reachable.

### Inspect

```text
python scripts/opensu.py inspect [--max-entities 200]
```

Returns top-level Groups/Components, OpenSU semantic types, names, tags, and bounds.
Use this before edits and after each meaningful modeling batch.

### Create floor

```text
python scripts/opensu.py create-floor \
  --width 8000 --depth 6000 --thickness 150 \
  --origin 0 0 0 --name Floor_Level01_001
```

Creates one isolated rectangular floor Group.

### Create column

```text
python scripts/opensu.py create-column \
  --center 1000 1000 150 \
  --width 400 --depth 400 --height 3000 \
  --name Column_A01_001
```

Creates one rectangular vertical solid column. `--center` is the center of the column base.

### Create beam

```text
python scripts/opensu.py create-beam \
  --start 1000 1000 3150 --end 7000 1000 3150 \
  --width 300 --height 500 --name Beam_A01_B01_001
```

Creates one straight rectangular solid beam. Start/end define the bottom centerline and must use the same Z in the current implementation.

### Create wall

```text
python scripts/opensu.py create-wall \
  --start 0 0 150 --end 8000 0 150 \
  --height 3000 --thickness 200 --name Wall_South_001
```

Creates one isolated straight wall Group. Start and end must have the same Z. Thickness is centered on the supplied centerline.

### Create opening

By wall name:

```text
python scripts/opensu.py create-opening \
  --wall-name Wall_South_001 \
  --offset 1200 --width 900 --height 2100 --sill 0 \
  --type door --name DoorOpening_South_001
```

Or by entity id:

```text
python scripts/opensu.py create-opening \
  --wall-id 1234 \
  --offset 1800 --width 1800 --height 1500 --sill 900 \
  --type window --name WindowOpening_East_001
```

The current opening system supports one rectangular opening per OpenSU wall. The opening must remain inside the wall endpoints and below the wall top.

### Create door assembly

```text
python scripts/opensu.py create-door \
  --wall-name Wall_South_001 \
  --opening-name DoorOpening_South_001 \
  --frame-width 60 --leaf-depth 40 --gap 5 \
  --name Door_South_001
```

Creates a simple framed door assembly aligned automatically to an existing door opening. The wall/opening geometry must already exist.

### Create window assembly

```text
python scripts/opensu.py create-window \
  --wall-name Wall_East_001 \
  --opening-name WindowOpening_East_001 \
  --frame-width 60 --glass-thickness 8 --gap 5 \
  --name Window_East_001
```

Creates a simple framed window with transparent glass, aligned automatically to an existing window opening.

### Apply material

By name:

```text
python scripts/opensu.py apply-material \
  --name Column_A01_001 \
  --material-name Concrete \
  --color "#B8B8B8" --opacity 1.0
```

Or by entity id:

```text
python scripts/opensu.py apply-material \
  --entity-id 1234 \
  --material-name GlassBlue \
  --color "#9CC9E8" --opacity 0.35
```

`--opacity` ranges from `0` to `1`. Material application is recursive by default; pass `--no-recursive` when only the selected group/instance should receive the material.

### Validate

```text
python scripts/opensu.py validate [--max-entities 1000]
```

Checks OpenSU architectural structure and root loose geometry. It also checks manifold solids for floors, walls, columns, and beams, plus wall linkage for door/window assemblies. Treat `valid: false` as incomplete work.

## Modeling rules

- Use stable semantic names.
- Keep architecture as Groups/Components, not loose root geometry.
- Preserve existing geometry unless the user asks to change it.
- Inspect before edits and after modeling batches.
- Create openings before door/window assemblies.
- Validate before declaring completion.
- Never fall back to arbitrary Ruby execution.
- If a requested operation is not exposed by the current extension, report the limitation instead of fabricating success.

## Current limitations

- Straight horizontal-plan walls and beams only.
- Rectangular vertical columns only.
- One opening per wall.
- Door/window assemblies require OpenSU opening metadata.
- No stairs, roofs, curved walls, repeated storefront openings, or curtain-wall grids yet.
