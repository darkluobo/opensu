---
name: sketchup-modeling
description: >-
  Control a local SketchUp model from Codex through the installed OpenSU/SketchUp MCP
  extension. Use for natural-language architectural modeling, reconstruction from one or
  many drawings/PDFs/images, persistent grid and room-program semantics, inspection,
  organization, repair, and validation. Supports auditable Plan Specs, cross-sheet evidence
  fusion, levels, floors, walls, columns, beams, openings, doors/windows, curtain walls,
  ceilings, stairs, roofs, Tags, materials, semantic edits, batch repair, and controlled deletion.
---

# SketchUp Modeling

Use the bundled deterministic bridges. Do not replace an available command with ad-hoc
socket code or arbitrary Ruby.

- `scripts/opensu.py` — core modeling and validation.
- `scripts/opensu_advanced.py` — L/U stairs, polygon slabs/ceilings, slab/roof openings.
- `scripts/opensu_edit.py` — single-entity semantic edits.
- `scripts/opensu_repair.py` — search, diagnosis, batch repair, controlled deletion.
- `scripts/opensu_plan.py` — drawing-derived Plan Spec lint + execution.
- `scripts/opensu_multisheet.py` — cross-sheet evidence reconciliation.
- `scripts/opensu_semantics.py` — automatic sheet indexing plus persistent grids/spaces.

Resolve scripts relative to this Skill directory.

## Always start with the live model

1. Run `python scripts/opensu.py status`.
2. If connection fails, ask the user to open SketchUp and choose
   `Extensions > MCP Server > Start Server`, then retry.
3. Run `python scripts/opensu.py inspect` before mutations.
4. Use millimetres for architecture.
5. Preserve existing user geometry unless the request explicitly changes it.
6. Inspect existing levels, grids, spaces, names, and Tags before creating duplicates.

## Drawing-set workflow

For PDF/image/CAD-export reconstruction, do not model directly from visual impression.
Use this pipeline:

```text
sheet index
→ read/review sheets
→ establish XYZ + levels + grids
→ multi-sheet evidence pack when >1 source contributes
→ semantic grid/space spec
→ Plan Spec
→ cross-sheet check
→ semantic lint
→ Plan Spec lint
→ Plan Spec execute
→ semantic apply
→ inspect
→ validate
→ diagnose/repair if needed
```

Read these references when relevant:

- `references/drawing-reconstruction.md`
- `references/multisheet-fusion.md`
- `references/sheet-grid-spaces.md`
- `references/plan-spec.schema.json`

### 1. Auto-index the drawing folder

When a project directory contains a drawing set, first run:

```text
python scripts/opensu_semantics.py index-sheets <drawing-folder> --output sheet-index.json
```

The index is filename-based only. Treat it as navigation assistance, not evidence. Then
inspect the actual files/pages and correct sheet id, kind, title, revision, and role as needed.

Never silently combine duplicate sheet ids. Determine which revision/status is current.

### 2. Establish coordinates and grids

Use a stable project coordinate system. For conventional architectural grids, prefer:

- numbered grids as constant X (`axis=x`)
- lettered grids as constant Y (`axis=y`)

For `A/3`, this normally means `X=grid 3`, `Y=grid A`. Follow the real documents if they
clearly use another convention, but never change convention midway.

Use exact printed grid/dimension chains before scale or pixel inference. Do not force
partitions/facade modules onto structural grids unless drawings support that relationship.

### 3. Record functional spaces

Use spaces for persistent room/zone semantics, not fake geometry. A space stores a simple
2D boundary, level, computed area, program type, department/zone, and source reference.

For dealership projects, useful program types include:

- `showroom`
- `sales`
- `reception`
- `customer_lounge`
- `delivery`
- `aftersales_reception`
- `workshop`
- `parts`
- `office`
- `support`
- `circulation`
- `service`
- `storage`
- `other`

Program semantics may influence modeling strategy but never override dimensions. Example:
`showroom` suggests checking for glazed frontage; it does not authorize inventing curtain wall geometry.

Semantic commands:

```text
python scripts/opensu_semantics.py template
python scripts/opensu_semantics.py lint semantics.json
python scripts/opensu_semantics.py apply semantics.json
```

`apply` requires referenced levels to already exist in SketchUp. It persists Grid/Space data
inside the `.skp`, then runs inspect + validate.

### 4. Evidence priority

For a single drawing, prefer:

1. printed dimensions / written levels
2. grid and chained dimensions
3. repeated confirmed modules
4. geometry derived from exact dimensions
5. calibrated scale
6. pixel estimate only when approximation is explicitly acceptable

For multi-sheet work, use the exact basis vocabulary understood by the checker:

1. `printed_dimension`
2. `grid_or_dimension_chain`
3. `explicit_detail`
4. `derived_from_exact`
5. `calibrated_scale`
6. `pixel_estimate`

Never average contradictory authoritative dimensions. A conflict between equally strong
sources is blocking until resolved.

### 5. Multi-sheet Pack

If more than one drawing contributes to the model, inventory the sources and encode claims.
Use plans mainly for XY, elevations/sections for Z/heights, and schedules/details for local
exact sizes.

Run:

```text
python scripts/opensu_multisheet.py template
python scripts/opensu_multisheet.py check multisheet-pack.json
```

If `blocking_conflicts` is non-empty, do not model. Report target, source sheets, values,
and tolerance. If `blocking_uncertainties` remains, ask the user unless approximation was
explicitly authorized.

Use stable semantic targets such as:

```text
walls.Wall_South_001.height_mm
walls.Wall_South_001.end_mm[0]
openings.Door_Main_Opening_001.width_mm
levels.Level_02.elevation_mm
curtain_walls.CurtainWall_Showroom_001.height_mm
```

Never target unstable list indexes like `walls[3]`.

### 6. Plan Spec

Write the final auditable Plan Spec only after coordinate/evidence reasoning is stable.
Important geometry should carry useful source references/confidence where supported.
Record unresolved items in `uncertainties` rather than silently guessing.

Commands:

```text
python scripts/opensu_plan.py template
python scripts/opensu_plan.py template --output plan.json
python scripts/opensu_plan.py lint plan.json
python scripts/opensu_plan.py execute plan.json
```

Execution refuses lint errors and, by default, blocking uncertainties and root-name collisions.
Do not bypass those guards just to make a task continue.

## General modeling order

For ordinary modeling and for Plan Spec execution, reason in roughly this order:

1. levels/storey elevations
2. floor/slab
3. slab circulation/shaft openings
4. primary columns and beams
5. exterior/interior walls
6. wall openings
7. door/window assemblies
8. curtain-wall/storefront assemblies
9. ceilings
10. stairs/circulation
11. flat roof/parapets and roof openings
12. materials and Tags
13. persistent grids/spaces when drawing semantics are available
14. inspect
15. validate
16. diagnose and smallest targeted repair
17. inspect + validate again

Use stable names such as `Level_01`, `Floor_Level01_001`, `Column_A_3_001`,
`Wall_South_001`, `Door_Main_001`, `CurtainWall_Showroom_001`, `Showroom_01`.

## Core modeling commands

```text
python scripts/opensu.py status
python scripts/opensu.py inspect
python scripts/opensu.py validate
python scripts/opensu.py define-level ...
python scripts/opensu.py create-floor ...
python scripts/opensu.py create-ceiling ...
python scripts/opensu.py create-column ...
python scripts/opensu.py create-beam ...
python scripts/opensu.py create-wall ...
python scripts/opensu.py create-opening ...
python scripts/opensu.py create-door ...
python scripts/opensu.py create-window ...
python scripts/opensu.py create-curtain-wall ...
python scripts/opensu.py create-stair ...
python scripts/opensu.py create-flat-roof ...
python scripts/opensu.py apply-material ...
```

Advanced geometry:

```text
python scripts/opensu_advanced.py create-l-stair ...
python scripts/opensu_advanced.py create-u-stair ...
python scripts/opensu_advanced.py create-slab-opening ...
python scripts/opensu_advanced.py create-polygon-slab ...
python scripts/opensu_advanced.py create-polygon-ceiling ...
```

## Building reasoning rules

- Levels, grids, and spaces are model semantics, not fake drawing geometry.
- Wall thickness is centered on the supplied centerline.
- Wall start/end direction matters because opening offsets are directional.
- Put structural columns on verified grid intersections when documents show that relationship.
- Beam endpoints represent the bottom centerline and share Z.
- Create wall openings before door/window assemblies.
- Door/window assemblies read wall opening metadata; do not guess rotation.
- Prefer curtain walls for continuous glazed dealership/showroom fronts when drawings support it.
- Use slab openings where stairs/shafts penetrate upper floors.
- Tags belong on Groups/Components, never raw edges/faces.
- Functional space names/programs never override authoritative geometry evidence.

## Editing and repair

For an existing wrong model, do not rebuild everything first.

```text
python scripts/opensu_repair.py diagnose
python scripts/opensu_repair.py find ...
```

Then apply the smallest edit, inspect, validate, and repeat only for remaining issues.

Single-entity editing:

```text
python scripts/opensu_edit.py rename ...
python scripts/opensu_edit.py set-tag ...
python scripts/opensu_edit.py set-visible ...
python scripts/opensu_edit.py transform ...
python scripts/opensu_edit.py duplicate ...
```

Batch repair:

```text
python scripts/opensu_repair.py batch-tag ...
python scripts/opensu_repair.py batch-visible ...
python scripts/opensu_repair.py batch-transform ...
```

Semantic transforms synchronize OpenSU coordinates. Re-inspect and validate after transforms/duplicates.

## Controlled deletion

Deletion is only through:

```text
python scripts/opensu_repair.py delete-confirmed ...
```

Use it only when the user explicitly asks to delete/remove something or explicitly authorizes
removal as part of repair. Before deletion, resolve exact entity id + exact current name and
confirm it is an OpenSU semantic root object. Never infer delete targets from partial names.
Never delete loose user geometry automatically.

## 4S dealership semantic reasoning

When documents explicitly support the relationships, encode areas such as showroom, sales,
reception, customer lounge, delivery, aftersales reception, workshop, parts/storage, office,
and support/circulation.

Useful cross-checks include:

- showroom overall width/depth versus structural grid
- public facade/curtain-wall height versus elevation/section
- main entrance dimensions versus plan/elevation/schedule
- customer reception/lounge adjacency from plan
- workshop bay/module and service-door sizes
- stair void and floor-to-floor rise
- roof/parapet/brand fascia levels

Do not infer fire separation, accessibility, structural capacity, or code compliance solely
from a room program label. Those need explicit authoritative project information.

## Inspect and validation expectations

`inspect_model` should expose ordinary entities/levels plus:

- `grids`
- `spaces`
- `semantic_summary.grids`
- `semantic_summary.spaces`
- `semantic_summary.space_area_m2`

`validate_model` includes grid/space metadata checks in addition to existing geometry/manifold checks.
A finished model should normally have zero loose architecture geometry, zero non-manifold OpenSU
solids where solid geometry is expected, valid semantics, and final `valid=true`.

## References

- `references/drawing-reconstruction.md`
- `references/multisheet-fusion.md`
- `references/sheet-grid-spaces.md`
- `references/plan-spec.schema.json`
- `references/examples/showroom-plan-v1.json`
- `references/examples/showroom-multisheet-pack-v1.json`
- `references/examples/showroom-semantics-v1.json`
- `references/tool-contract.md`
- `references/advanced-geometry.md`

## Safety and current limits

- Never use arbitrary Ruby execution.
- Do not invent unsupported SketchUp capabilities.
- Keep architecture in named Groups/Components rather than loose root geometry.
- Preserve uncertainty instead of manufacturing dimensions.
- Never average contradictory authoritative drawing dimensions.
- Grid/Space metadata is persistent but non-geometric; visible grid annotations/room labels are not yet generated.
- Straight, L, and U stairs are supported; spiral/multi-landing stairs are not.
- Polygon floors/ceilings may be concave but not self-intersecting.
- Pitched roofs and curved walls are not yet exposed.
- If a request exceeds the tool surface, explain the missing capability instead of pretending it was modeled.
