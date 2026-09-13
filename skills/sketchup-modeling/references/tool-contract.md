# OpenSU command contract

The Skill bridge talks directly to the local SketchUp extension on `127.0.0.1:9876`.
All architecture dimensions are millimetres.

## Core commands

### Status / inspect / validate

```text
python scripts/opensu.py status
python scripts/opensu.py inspect [--max-entities 200]
python scripts/opensu.py validate [--max-entities 1000]
```

Always inspect before edits and validate before completion.

### Floor

```text
python scripts/opensu.py create-floor \
  --width 8000 --depth 6000 --thickness 150 \
  --origin 0 0 0 --name Floor_Level01_001
```

### Column

```text
python scripts/opensu.py create-column \
  --center 1000 1000 150 --width 400 --depth 400 --height 3000 \
  --name Column_A01_001
```

### Beam

```text
python scripts/opensu.py create-beam \
  --start 1000 1000 3150 --end 7000 1000 3150 \
  --width 300 --height 500 --name Beam_A01_B01_001
```

Start/end define the beam bottom centerline and must use the same Z.

### Wall

```text
python scripts/opensu.py create-wall \
  --start 0 0 150 --end 8000 0 150 \
  --height 3000 --thickness 200 --name Wall_South_001
```

Wall thickness is centered on the supplied centerline.

## Multiple openings on one wall

Call `create-opening` repeatedly against the same wall. The extension stores all opening
metadata and regenerates a closed wall shell from the complete opening set.

```text
python scripts/opensu.py create-opening \
  --wall-name Wall_Showroom_001 \
  --offset 800 --width 1000 --height 2200 --sill 0 \
  --type door --name DoorOpening_001

python scripts/opensu.py create-opening \
  --wall-name Wall_Showroom_001 \
  --offset 2600 --width 1800 --height 1800 --sill 700 \
  --type window --name WindowOpening_001

python scripts/opensu.py create-opening \
  --wall-name Wall_Showroom_001 \
  --offset 5000 --width 1800 --height 1800 --sill 700 \
  --type window --name WindowOpening_002
```

Rules:
- openings must stay inside the wall endpoints and height;
- openings may not overlap in both horizontal and vertical extents;
- stable opening names must be unique on the wall;
- when a wall has multiple openings, pass `--opening-name` when creating a door/window assembly.

### Door assembly

```text
python scripts/opensu.py create-door \
  --wall-name Wall_Showroom_001 --opening-name DoorOpening_001 \
  --frame-width 60 --leaf-depth 40 --gap 5 --name Door_001
```

### Window assembly

```text
python scripts/opensu.py create-window \
  --wall-name Wall_Showroom_001 --opening-name WindowOpening_001 \
  --frame-width 60 --glass-thickness 8 --gap 5 --name Window_001
```

## Glass curtain wall / storefront

```text
python scripts/opensu.py create-curtain-wall \
  --start 0 0 150 --end 12000 0 150 \
  --height 4200 --panel-width 1500 --row-height 2100 \
  --mullion-width 60 --mullion-depth 120 \
  --glass-thickness 10 --gap 8 \
  --frame-color "#363A3D" --glass-color "#9CC9E8" --glass-opacity 0.35 \
  --name CurtainWall_Showroom_001
```

The requested panel width and row height are target grid sizes. The extension chooses an
even number of bays/rows across the exact overall width and height, then creates framed
transparent glass panels. Curtain walls are independent assemblies rather than holes in
an opaque wall.

Use curtain walls for showroom facades, dealership storefronts, and large glazed grids.
Use ordinary wall openings + window assemblies for punched windows in opaque walls.

## Materials

```text
python scripts/opensu.py apply-material \
  --name Column_A01_001 --material-name Concrete \
  --color "#B8B8B8" --opacity 1.0
```

`--opacity` ranges from `0` to `1`. Material application is recursive by default; use
`--no-recursive` to paint only the selected group/instance.

## Validation expectations

`validate` checks, among other things:
- root loose geometry;
- duplicate architecture names;
- manifold solids for floors, walls, columns, and beams;
- validity/non-overlap of all wall opening metadata;
- door/window wall linkage;
- curtain-wall size/grid metadata and presence of glass panels.

Treat `valid: false` as incomplete work.

## Current limitations

- Straight horizontal-plan walls, beams, and curtain walls only.
- Rectangular vertical columns only.
- Rectangular wall openings only.
- Door/window assemblies require OpenSU opening metadata.
- No curved curtain walls, stairs, roofs, arbitrary slab polygons, or curved walls yet.
- Never fall back to arbitrary Ruby execution.
