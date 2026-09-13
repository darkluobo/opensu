# Drawing / PDF to SketchUp reconstruction workflow

This reference defines how Codex should turn a floor plan, PDF sheet, screenshot, or exported CAD image into an OpenSU Plan Spec before modeling.

## Core rule

Never model directly from visual impression when a dimensioned source exists. Convert the source into explicit millimetre coordinates and semantic objects first, lint the Plan Spec, then execute it.

Evidence priority, highest first:

1. explicit printed dimensions and written elevations
2. grid/axis dimensions and chained dimensions
3. repeated module dimensions confirmed elsewhere on the same drawing set
4. stated drawing scale, only when the source image/PDF has not been rescaled or cropped unpredictably
5. geometric inference from other exact dimensions
6. pixel/visual estimation, only when the user explicitly accepts an approximate reconstruction

When sources conflict, do not silently choose one. Record an uncertainty and prefer asking for clarification when it affects primary geometry.

## Intake checklist

Before producing geometry, identify:

- sheet title / floor / revision when visible
- stated units
- stated scale, if any
- north/orientation marker when relevant
- structural axes / grids
- overall building extents
- floor datum and known elevations
- wall thicknesses
- column sizes and centers
- beam sizes/elevations when shown
- door/window widths and locating dimensions
- stairs, shafts, atria, slab openings
- curtain-wall/storefront extents
- ceiling and roof information when present
- dimensions that are unreadable, cropped, contradictory, or absent

Do not treat title-block scale as reliable after a screenshot has been resized unless another exact dimension can calibrate it.

## Coordinate convention

Use millimetres. Establish one drawing origin and keep it stable for the whole Plan Spec.

Recommended convention for ordinary architectural plans:

- X = plan east/right
- Y = plan north/up
- Z = elevation
- Level_01 floor datum normally starts at Z=0 unless the drawing specifies another datum

If the source drawing uses another axis orientation, preserve the geometry but document the mapping in `project.coordinate_note`.

## Wall reconstruction

Represent each straight wall by its centerline. Wall thickness is centered on that line by OpenSU.

Prefer wall endpoints derived from:

- grid intersections
- face-to-face dimensions adjusted by half-thickness when necessary
- explicit centerline dimensions

Do not mix inside-face and centerline dimensions without converting them.

For wall openings, `offset_mm` is measured from the wall start point along the wall centerline direction. The Plan Spec must therefore preserve a deliberate start/end direction for every wall.

When multiple openings exist on one wall, verify both horizontal non-overlap and vertical fit before execution.

## Columns and structural grid

If a structural grid is shown, place column centers on grid intersections first and derive walls from the structural layout when appropriate. Record exact column width/depth from schedules or plan labels when available.

Repeated bays should use repeated exact coordinates rather than visually copied spacing.

## Doors and windows

Separate three facts:

- opening position in the wall
- opening size
- assembly type

A symbol alone may indicate type but not exact size. Prefer dimension/schedule values over symbol appearance.

If the drawing provides a wall opening but no reliable frame detail, create the opening first. Only create the door/window assembly when its basic type is known.

## Curtain wall / showroom facade

For automotive showrooms and glazed commercial fronts, prefer one semantic curtain-wall/storefront assembly over many arbitrary window objects when the drawing describes a continuous glazed grid.

Capture:

- baseline start/end
- total height
- intended bay/module width when dimensioned
- horizontal row height when dimensioned
- frame depth/width only when known or when the user accepts a standard placeholder

## Multi-storey plans

Create named levels before level-dependent geometry. Do not infer floor-to-floor heights from stair graphics alone if an elevation/section provides an exact value.

For stairs passing through upper floors, explicitly model the corresponding slab opening.

## Polygon floors and irregular rooms

Use polygon slabs/ceilings only after the perimeter is resolved into an ordered, non-self-intersecting point list. Avoid excessive vertices caused by raster noise; preserve meaningful architectural corners, not every pixel kink.

## 4S dealership recognition notes

When the plan is an automotive dealership, common semantic zones may include:

- showroom / vehicle display
- main customer entrance
- reception / consultation
- customer lounge
- delivery area
- sales offices
- aftersales reception
- service workshop bays
- vehicle workshop entrances
- parts / spare-parts storage
- staff / office / meeting support spaces

These labels help naming and grouping, but they never override the actual drawing geometry.

## Confidence and uncertainty

Each important item may include:

```json
"evidence": {
  "confidence": "high",
  "source_ref": "A-101 dimension chain 7200+7200",
  "note": "wall centerline derived from two exact face dimensions"
}
```

Use:

- `high`: directly dimensioned or explicitly scheduled
- `medium`: derived from exact dimensions or repeated confirmed modules
- `low`: visual/scale estimate or ambiguous symbol interpretation

Put unresolved issues in top-level `uncertainties`:

```json
{
  "id": "U-03",
  "description": "east showroom glazing height is not legible on the supplied screenshot",
  "blocking": true
}
```

A blocking uncertainty should stop execution unless the user explicitly authorizes an approximate assumption. Never clear a blocking uncertainty merely to make the lint pass.

## Required Codex workflow

For drawing-driven tasks:

1. inspect the source drawing(s)
2. identify sheet/revision/units/scale evidence
3. establish coordinate origin and level datums
4. extract exact dimensions first
5. derive secondary coordinates
6. record uncertainties and assumptions
7. generate Plan Spec v1 JSON
8. run `python scripts/opensu_plan.py lint <spec.json>`
9. fix every lint error
10. if blocking uncertainties remain, ask the user unless approximation was explicitly authorized
11. inspect the existing SketchUp model
12. execute with `python scripts/opensu_plan.py execute <spec.json>`
13. inspect and validate the resulting model
14. use repair tools only for localized corrections
15. report what was exact, derived, estimated, or still unresolved

## Do not do these

- do not trust raster scale when the image may have been resized
- do not infer a dimension from perspective imagery as though it were an orthographic plan
- do not collapse two walls into one centerline when they have different thicknesses
- do not ignore wall direction when calculating opening offsets
- do not invent hidden rooms, doors, or structural members because they are common in similar buildings
- do not execute a Plan Spec with unresolved blocking uncertainty unless the user explicitly approved approximation
