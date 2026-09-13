# Phase 1 Real-SketchUp Acceptance Test

This checklist is the merge gate for the architecture MVP. Python tests and Ruby syntax checks are necessary, but they cannot replace one real SketchUp geometry pass.

## Test model

Start from a completely empty SketchUp model.

Create:

- floor: 8000 × 6000 × 150 mm
- four walls: 3000 mm high, 200 mm thick
- south wall door: 900 × 2100 mm, sill 0 mm
- east wall window: 1800 × 1500 mm, sill 900 mm

Walls should start at z = 150 mm so their bases sit on the top of the slab.

## Suggested call sequence

1. `sketchup_status`
2. `sketchup_inspect_model`
3. `sketchup_create_floor`
4. `sketchup_create_wall` × 4
5. `sketchup_create_opening` for the south door
6. `sketchup_create_opening` for the east window
7. `sketchup_inspect_model`
8. `sketchup_validate_model`

## Suggested dimensions

Floor:

```text
width_mm=8000
depth_mm=6000
thickness_mm=150
origin_mm=[0,0,0]
name=Floor_001
```

Walls:

```text
South: start=[0,0,150]       end=[8000,0,150]       name=Wall_South
East:  start=[8000,0,150]    end=[8000,6000,150]    name=Wall_East
North: start=[8000,6000,150] end=[0,6000,150]       name=Wall_North
West:  start=[0,6000,150]    end=[0,0,150]          name=Wall_West

height_mm=3000
thickness_mm=200
```

South door:

```text
offset_mm=1200
width_mm=900
height_mm=2100
sill_height_mm=0
opening_type=door
name=Door_South_001
```

East window:

```text
offset_mm=1800
width_mm=1800
height_mm=1500
sill_height_mm=900
opening_type=window
name=Window_East_001
```

## Pass criteria

The Phase 1 MVP passes only when all items below are true:

- extension loads without Ruby Console exceptions
- `Extensions → SketchUp MCP → Start Server` starts the localhost server
- `sketchup_status` succeeds
- inspection works before any geometry exists
- slab dimensions are correct
- four walls are separate named Groups
- wall dimensions are correct
- door opening reaches the wall base and passes through the full wall thickness
- window opening has the correct sill and passes through the full wall thickness
- generated floor/wall groups remain closed manifold solids
- no architectural faces/edges are loose at model root
- inspection reports bounds in millimetres
- validation returns `valid: true`
- each mutating MCP call can be undone cleanly in SketchUp
- inspection and validation do not modify the model

## Failure evidence

For any failed item, record:

- exact MCP call
- returned JSON
- SketchUp version
- Ruby Console error, if any
- screenshot of the incorrect geometry
- whether the model was empty before the test

Do not merge Phase 1 based solely on wrapper tests. The final geometry path depends on SketchUp's embedded Ruby runtime and geometry kernel.
