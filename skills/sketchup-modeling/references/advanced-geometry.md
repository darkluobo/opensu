# OpenSU advanced geometry contract

These commands are executed through `scripts/opensu_advanced.py`. All dimensions are millimetres.

## L-shaped stair

```text
python scripts/opensu_advanced.py create-l-stair \
  --origin 2000 2000 150 \
  --direction x+ --turn left \
  --width 1400 --run1 3600 --run2 3600 \
  --landing-length 1400 --landing-thickness 150 \
  --end-elevation 4500 --target-riser-height 165 \
  --level-name Level_01 --name Stair_L_L01_L02_001
```

Creates two step flights and one closed landing solid. The extension calculates the total riser count unless `--riser-count` is given, then splits risers between both flights.

`--direction` accepts `x+`, `x-`, `y+`, or `y-`. `--turn` accepts `left` or `right`.

## U-shaped stair

```text
python scripts/opensu_advanced.py create-u-stair \
  --origin 2000 2000 150 \
  --direction x+ --turn left \
  --width 1400 --gap 200 \
  --run1 3600 --run2 3600 \
  --landing-depth 1400 --landing-thickness 150 \
  --end-elevation 4500 --target-riser-height 165 \
  --level-name Level_01 --name Stair_U_L01_L02_001
```

Creates two parallel return flights and one shared closed landing. `--gap` is the clear spacing between the two flight widths.

For both stair types, the extension rejects calculated tread depths below 150 mm and riser heights outside 80–220 mm.

## Rectangular slab / roof opening

By target name:

```text
python scripts/opensu_advanced.py create-slab-opening \
  --target-name Floor_Level02_001 \
  --offset-x 1800 --offset-y 1600 \
  --width 1800 --depth 4200 \
  --type stair --opening-name StairVoid_L02_001
```

Or by entity id:

```text
python scripts/opensu_advanced.py create-slab-opening \
  --entity-id 1234 \
  --offset-x 2500 --offset-y 2000 \
  --width 1600 --depth 2400 \
  --type skylight --opening-name SkylightVoid_001
```

Supported targets:

- rectangular OpenSU `floor`
- rectangular OpenSU `ceiling`
- OpenSU `flat_roof` (the nested `Roof_Slab` is regenerated; parapets are preserved)

Multiple non-overlapping openings may be added sequentially. Every opening must remain strictly inside the outer slab boundary. The extension regenerates a closed horizontal shell from all opening boundaries and stores `slab_openings_json` on the target group.

Polygon slab/ceiling openings are not supported yet.

## Polygon slab

Repeat `--point` in boundary order:

```text
python scripts/opensu_advanced.py create-polygon-slab \
  --point 0 0 0 \
  --point 12000 0 0 \
  --point 12000 5000 0 \
  --point 8000 5000 0 \
  --point 8000 8000 0 \
  --point 0 8000 0 \
  --thickness 150 --level-name Level_01 \
  --name Floor_LShape_001
```

The polygon may be concave. It must be simple (non-self-intersecting), have at least three vertices, and every vertex must share the same Z elevation.

## Polygon ceiling

```text
python scripts/opensu_advanced.py create-polygon-ceiling \
  --point 0 0 3900 \
  --point 12000 0 3900 \
  --point 12000 5000 3900 \
  --point 8000 5000 3900 \
  --point 8000 8000 3900 \
  --point 0 8000 3900 \
  --thickness 100 --level-name Level_01 \
  --name Ceiling_LShape_001
```

Uses the same polygon validity rules as polygon slabs.

## Validation expectations

After advanced geometry work, run:

```text
python scripts/opensu.py inspect
python scripts/opensu.py validate
```

Validation checks:

- polygon slabs/ceilings are closed manifold solids;
- polygon metadata matches the generated vertex count;
- L/U stairs have consistent total and per-flight riser counts;
- every stair step and landing child group is a manifold solid;
- slab opening metadata is valid, unique, contained, and non-overlapping;
- previously existing floor/ceiling/roof manifold checks still pass after openings are regenerated.

Treat `valid: false` as incomplete work.
