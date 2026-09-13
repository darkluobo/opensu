# OpenSU command contract

The Skill bridge talks directly to the local SketchUp extension on `127.0.0.1:9876`.
All architectural dimensions are millimetres.

## Session / model QA

```text
python scripts/opensu.py status
python scripts/opensu.py inspect [--max-entities 200]
python scripts/opensu.py validate [--max-entities 1000]
```

`inspect` returns top-level OpenSU entities plus model-level `levels`. Always inspect
before edits and validate before completion.

## Levels

```text
python scripts/opensu.py define-level \
  --name Level_01 --elevation 0 --floor-to-floor 4500

python scripts/opensu.py define-level \
  --name Level_02 --elevation 4500 --floor-to-floor 4500
```

Level names and elevations must be unique. Levels are model metadata, not geometry.

## Floor / ceiling

```text
python scripts/opensu.py create-floor \
  --width 12000 --depth 8000 --thickness 150 \
  --origin 0 0 0 --name Floor_Level01_001

python scripts/opensu.py create-ceiling \
  --width 12000 --depth 8000 --thickness 100 \
  --origin 0 0 3900 --level-name Level_01 \
  --name Ceiling_Level01_001
```

The ceiling origin is its lower face.

## Column / beam / wall

```text
python scripts/opensu.py create-column \
  --center 1000 1000 150 --width 400 --depth 400 --height 4200 \
  --name Column_A01_001

python scripts/opensu.py create-beam \
  --start 1000 1000 3850 --end 7000 1000 3850 \
  --width 300 --height 500 --name Beam_A01_B01_001

python scripts/opensu.py create-wall \
  --start 0 0 150 --end 12000 0 150 \
  --height 4200 --thickness 200 --name Wall_Showroom_001
```

Beam start/end define its bottom centerline and must use the same Z. Wall thickness is
centered on the supplied wall centerline.

## Multiple openings on one wall

Call `create-opening` repeatedly against the same wall. The extension regenerates a
closed wall shell from the complete opening set.

```text
python scripts/opensu.py create-opening \
  --wall-name Wall_Showroom_001 \
  --offset 800 --width 1000 --height 2200 --sill 0 \
  --type door --name DoorOpening_001

python scripts/opensu.py create-opening \
  --wall-name Wall_Showroom_001 \
  --offset 2600 --width 1800 --height 1800 --sill 700 \
  --type window --name WindowOpening_001
```

Openings must remain inside the wall, may not overlap, and need unique names. For walls
with multiple openings, always pass `--opening-name` to door/window assembly creation.

## Door / window assemblies

```text
python scripts/opensu.py create-door \
  --wall-name Wall_Showroom_001 --opening-name DoorOpening_001 \
  --frame-width 60 --leaf-depth 40 --gap 5 --name Door_001

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

Use curtain walls for large glazed dealership/showroom facades. Use ordinary openings
for punched windows in opaque walls.

## Straight stair

```text
python scripts/opensu.py create-stair \
  --start 2000 2000 150 --end 6500 2000 4500 \
  --width 1400 --target-riser-height 165 \
  --level-name Level_01 --name Stair_L01_L02_001
```

The stair runs in a straight line from start to end. End Z must be above start Z. If
`--riser-count` is omitted, the extension calculates it from the requested target riser
height. The resulting actual riser height must be 80-220 mm and tread depth at least
150 mm.

## Flat roof + parapets

```text
python scripts/opensu.py create-flat-roof \
  --origin 0 0 9000 --width 12000 --depth 8000 \
  --slab-thickness 180 --parapet-height 900 --parapet-thickness 150 \
  --level-name Roof --name Roof_Main_001
```

This creates one roof assembly containing a closed slab plus four closed parapet solids.
Set `--parapet-height 0` to create the slab without parapets.

## Materials

```text
python scripts/opensu.py apply-material \
  --name Column_A01_001 --material-name Concrete \
  --color "#B8B8B8" --opacity 1.0
```

Opacity ranges from `0` to `1`. Material application is recursive by default.

## Validation expectations

`validate` checks, among other things:
- root loose geometry and duplicate architecture names;
- level metadata uniqueness and valid elevations;
- manifold solids for floors, walls, columns, beams, ceilings, stair steps, roof slabs,
  and parapets;
- wall-opening non-overlap and door/window linkage;
- curtain-wall size/grid metadata and glass panel presence;
- level references used by ceilings, stairs, and roofs.

Treat `valid: false` as incomplete work.

## Current limitations

- Straight horizontal-plan walls, beams, and curtain walls only.
- Rectangular vertical columns only.
- Rectangular wall openings only.
- Stairs are straight runs only; no U/L stairs or landings yet.
- Ceilings and flat roofs are rectangular.
- No pitched roofs, arbitrary polygon slabs, or curved walls yet.
- Never fall back to arbitrary Ruby execution.
