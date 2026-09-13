# Multi-Sheet Drawing Fusion

Use this workflow when reconstruction depends on more than one drawing, page, or image.
The goal is not to average drawings blindly. The goal is to preserve traceable evidence,
resolve dimensions by source authority, and stop before SketchUp mutation when authoritative
sources genuinely conflict.

## Workflow

1. Inventory every source as a sheet in a Multi-Sheet Pack.
2. Build the final Plan Spec using the normal drawing reconstruction rules.
3. Add claims for critical geometry that is confirmed, derived, or contradicted across sheets.
4. Run `python scripts/opensu_multisheet.py check <pack.json>`.
5. Do not execute the embedded Plan Spec when `blocking_conflicts` is non-empty.
6. Do not execute while a blocking uncertainty remains unresolved unless the user explicitly
   provides or approves the missing value.
7. After the pack passes, lint the embedded Plan Spec with `opensu_plan.py lint`.
8. Only then execute the Plan Spec in SketchUp.

## Sheet roles

Treat sheet type as a strong hint about which coordinates it should control:

- **plan**: XY layout, grid spacing, wall centerlines, column centers, room boundaries,
  horizontal opening offsets, circulation footprint.
- **elevation**: facade Z dimensions, overall height, sill/head heights, storefront module
  heights, parapet heights, signage bands.
- **section**: floor-to-floor heights, slab thicknesses, ceiling elevations, stair rise,
  roof build-up, vertical relationships hidden from elevations.
- **detail**: local assembly dimensions and exact interface geometry. A detail may outrank
  a general drawing for the specific local condition it explicitly dimensions.
- **schedule**: repeated door/window/component sizes when the schedule clearly maps to the
  same type or mark in the Plan Spec.

Do not prohibit unusual evidence when it is explicit; record it and let the checker warn
about unexpected sheet roles rather than silently discarding it.

## Evidence authority

The checker uses this order, strongest first:

1. `printed_dimension`
2. `grid_or_dimension_chain`
3. `explicit_detail`
4. `derived_from_exact`
5. `calibrated_scale`
6. `pixel_estimate`

Only claims at the strongest available level for one target determine the resolved value.
Lower-priority claims may disagree and produce warnings, but they cannot overwrite stronger
sources.

If two strongest claims disagree beyond tolerance, the result is a blocking conflict.
Example: A-201 says showroom height 4200 and A-301 says 4500, both printed dimensions.
Codex must not pick one silently.

## Target paths

Claims point into the embedded Plan Spec by stable semantic name:

```text
walls.Wall_South_001.height_mm
walls.Wall_South_001.end_mm[0]
openings.Door_Main_Opening_001.width_mm
openings.Window_East_001.sill_height_mm
levels.Level_02.elevation_mm
columns.Column_A1.width_mm
curtain_walls.CurtainWall_Showroom_001.height_mm
```

Use stable entity names before creating claims. Do not target list indexes such as
`walls[3]`; indexes become unstable when the Plan Spec is edited.

## Tolerance

Default tolerance is 5 mm unless a project or claim requires another value.
Use tighter tolerance for exact prefabricated components only when the drawing warrants it.
Do not make pixel-based evidence artificially precise.

## 4S dealership reconstruction

For typical dealership work, cross-check at least these items when the drawings provide them:

- overall showroom width/depth
- structural grid spacing
- showroom clear/facade height
- floor-to-floor heights
- main entrance width/height
- storefront curtain-wall height and bay module
- workshop door width/height
- second-floor slab/void location
- stair start/end elevation and opening size
- parapet/brand fascia height

Functional labels such as showroom, reception, customer lounge, delivery bay, workshop,
parts, office, and service reception help interpretation but do not substitute for dimensions.

## Conflict handling

When a blocking conflict occurs:

1. quote the conflicting target and both sheet ids
2. report the values and tolerance
3. inspect whether one source is a revision/superseded sheet or a different local condition
4. ask the user only when the documents do not resolve the conflict
5. after resolution, preserve the decision in the pack instead of deleting evidence silently

A user-approved resolution can be represented by updating the final Plan Spec and adding a
new high-authority claim whose source is clearly marked as a user instruction or revised sheet.

## Never do this

- average two conflicting printed dimensions and call the average correct
- use a resized screenshot to override a printed dimension
- infer Z height from a plan when a section exists
- infer XY bay spacing from an elevation when a dimensioned plan exists
- throw away contradictory evidence without reporting it
- execute SketchUp before cross-sheet checks and Plan Spec lint both pass
