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

### Create wall

```text
python scripts/opensu.py create-wall \
  --start 0 0 150 --end 8000 0 150 \
  --height 3000 --thickness 200 --name Wall_South_001
```

Creates one isolated straight wall Group. Start and end must have the same Z in Phase 1.
Thickness is centered on the supplied centerline.

### Create opening

By wall name:

```text
python scripts/opensu.py create-opening \
  --wall-name Wall_South_001 \
  --offset 1200 --width 900 --height 2100 --sill 0 \
  --type door --name Door_South_001
```

Or by entity id:

```text
python scripts/opensu.py create-opening \
  --wall-id 1234 \
  --offset 1800 --width 1800 --height 1500 --sill 900 \
  --type window --name Window_East_001
```

Phase 1 supports one rectangular opening per OpenSU wall. The opening must remain inside the wall endpoints and below the wall top.

### Validate

```text
python scripts/opensu.py validate [--max-entities 1000]
```

Checks OpenSU architectural structure and root loose geometry. Treat `valid: false` as incomplete work.

## Modeling rules

- Use stable semantic names.
- Keep architecture as Groups/Components, not loose root geometry.
- Preserve existing geometry unless the user asks to change it.
- Inspect before edits and after modeling batches.
- Validate before declaring completion.
- Never fall back to arbitrary Ruby execution.
- If a requested operation is not exposed by the current extension, report the limitation instead of fabricating success.
