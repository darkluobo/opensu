---
name: opensu
description: >-
  Control a local SketchUp model from Codex through the installed OpenSU extension.
  Use for natural-language architectural modeling, reconstruction from one or many
  drawings/PDFs/images, persistent levels/grids/spaces, grid-driven structure,
  space-driven partitions, persistent logical entity-group trees, inspection, organization,
  repair, and validation. Supports
  auditable Plan Specs, cross-sheet evidence fusion, floors, walls, columns, beams,
  openings, doors/windows, curtain walls, ceilings, stairs, roofs, Tags, materials,
  semantic edits, batch repair, and controlled deletion.
---

# OpenSU

Use the bundled deterministic bridges instead of ad-hoc socket code or arbitrary Ruby:

- `scripts/opensu.py` — core modeling, levels, materials, inspect and validate.
- `scripts/opensu_advanced.py` — L/U stairs, polygon slabs/ceilings, slab/roof openings.
- `scripts/opensu_edit.py` — single-entity semantic edits.
- `scripts/opensu_repair.py` — search, diagnosis, batch repair, controlled deletion.
- `scripts/opensu_plan.py` — drawing-derived Plan Spec lint + execution.
- `scripts/opensu_multisheet.py` — cross-sheet evidence reconciliation.
- `scripts/opensu_semantics.py` — drawing sheet index plus persistent grids/spaces.
- `scripts/opensu_layout.py` — grid intersection, grid columns/beams, Space partitions, advisory program strategy.
- `scripts/opensu_groups.py` — persistent logical grouping, group-wide visibility/Tag/transform/duplication.

Resolve scripts relative to this Skill directory.

## Always start with the live model

1. Run `python scripts/opensu.py status`.
2. If connection fails, ask the user to open SketchUp and choose `Extensions > MCP Server > Start Server`.
3. Run `python scripts/opensu.py inspect` before mutations.
4. Use millimetres for architecture.
5. Preserve existing user geometry unless the request explicitly changes it.
6. Inspect existing levels, grids, spaces, entity groups, names, Tags, and semantic layout relationships before creating duplicates.

## Drawing-set workflow

For PDF/image/CAD-export reconstruction, never model directly from visual impression. Use:

```text
sheet index
→ read/review actual sheets
→ establish XYZ + levels + structural grids
→ multi-sheet evidence pack when >1 source contributes
→ semantic Grid/Space spec
→ Plan Spec
→ cross-sheet check
→ semantic lint
→ Plan Spec lint
→ Plan Spec execute
→ semantic apply
→ grid/space-driven layout where explicitly supported
→ inspect
→ validate
→ diagnose and smallest repair
```

Read when relevant:

- `references/drawing-reconstruction.md`
- `references/multisheet-fusion.md`
- `references/sheet-grid-spaces.md`
- `references/grid-driven-layout.md`
- `references/semantic-grouping.md`
- `references/plan-spec.schema.json`

### Sheet indexing

Start a drawing set with:

```text
python scripts/opensu_semantics.py index-sheets <drawing-folder> --output sheet-index.json
```

Filename inference is navigation assistance only. Inspect the real pages and correct sheet id,
kind, title, revision, and role. Never silently combine duplicate sheet ids; determine the current revision.

### Evidence priority

Single-sheet authority, strongest first:

1. printed dimensions / written levels
2. grid and chained dimensions
3. repeated confirmed modules
4. geometry derived from exact dimensions
5. calibrated scale
6. pixel estimate only with explicit approximation permission

Multi-sheet checker vocabulary, strongest first:

1. `printed_dimension`
2. `grid_or_dimension_chain`
3. `explicit_detail`
4. `derived_from_exact`
5. `calibrated_scale`
6. `pixel_estimate`

Never average contradictory authoritative dimensions. Equal-strength disagreement beyond tolerance is blocking.

### Multi-sheet evidence

Plans normally control XY; elevations/sections normally control Z/heights; schedules/details confirm local sizes.
Run:

```text
python scripts/opensu_multisheet.py template
python scripts/opensu_multisheet.py check multisheet-pack.json
```

If `blocking_conflicts` or unresolved blocking uncertainties remain, do not model unless the user explicitly resolves/accepts them.
Use stable semantic targets such as `walls.Wall_South_001.height_mm` or `levels.Level_02.elevation_mm`, never unstable list indexes.

### Plan Spec

Commands:

```text
python scripts/opensu_plan.py template
python scripts/opensu_plan.py lint plan.json
python scripts/opensu_plan.py execute plan.json
```

Execution refuses lint errors, blocking uncertainties by default, and conflicting root names. Do not bypass guards merely to continue.

## Persistent levels, grids, and spaces

Levels, grids, and spaces are model semantics, not fake drawing geometry.

Default architectural grid convention:

- numbered grid = X axis
- letter grid = Y axis
- `3/B` = X from grid `3`, Y from grid `B`

Follow the real project if its convention differs, but never change convention midway.

Semantic commands:

```text
python scripts/opensu_semantics.py template
python scripts/opensu_semantics.py lint semantics.json
python scripts/opensu_semantics.py apply semantics.json
```

Spaces store level, 2D boundary, area, program type, department/zone, and source reference.
Useful dealership program types include `showroom`, `sales`, `reception`, `customer_lounge`,
`delivery`, `aftersales_reception`, `workshop`, `parts`, `office`, `support`, `circulation`,
`service`, `storage`, and `other`.

Program semantics guide reasoning only. They never override authoritative geometry evidence.

## Grid-driven structure

Prefer persisted grids over manually retyping coordinates when the drawings explicitly place structure on grids.

```text
python scripts/opensu_layout.py grid-point --at 3/B --level Level_01
python scripts/opensu_layout.py grid-column --at 3/B --level Level_01 --width 500 --depth 500
python scripts/opensu_layout.py grid-beam --from 1/A --to 5/A --level Level_02 --bottom-offset -600
```

Rules:

- `grid-column` centers the column at the verified intersection.
- If column `--height` is omitted, the referenced Level must have `floor_to_floor_mm`; otherwise ask/provide height.
- Beam endpoints come from two verified intersections and use the referenced Level plus bottom offset.
- Never create a column/beam on a grid merely because a grid exists; structural placement still requires plan evidence or explicit user instruction.
- After grid-driven structural batches, inspect and validate.

## Space-driven partitions

**A Space is not automatically a room and a Space boundary is not automatically a wall.**
A showroom, workshop, lounge, or reception zone may have open edges.

Only convert Space edges to walls when the plan or user explicitly indicates physical partitions.

All perimeter edges:

```text
python scripts/opensu_layout.py space-walls --space Office_01 --thickness 100
```

Selected zero-based boundary edges:

```text
python scripts/opensu_layout.py space-walls --space Aftersales_Reception_01 --edges 1 2 --thickness 120
```

If wall height is omitted, the Space's Level must define `floor_to_floor_mm`. Generated walls are one undoable SketchUp operation.

Use read-only program guidance when useful:

```text
python scripts/opensu_layout.py space-strategy --space Showroom_01
```

A strategy may suggest checking glazing, preserving display/service bays, or using lighter partitions, but it must never generate dimensions or geometry by itself.

## 4S dealership reasoning

When supported by drawings:

- showroom: preserve display bays; check plan/elevation evidence for continuous glazed frontage
- workshop: use verified structural grids; preserve large service bays
- aftersales reception: coordinate customer/vehicle interface; only wall evidenced edges
- customer lounge/sales/office: use actual partition lines, not Space boundaries by default
- delivery: preserve vehicle clearance and entrance evidence
- parts/storage: respect enclosure/storage plan evidence
- circulation: never wall across an intended route

Do not infer fire separation, accessibility, structural capacity, service equipment clearance, or code compliance from a program label alone.

## General modeling order

1. levels
2. verified grids
3. floor/slab
4. slab/shaft openings
5. grid-driven or explicit columns/beams
6. exterior/interior walls
7. openings
8. door/window assemblies
9. curtain walls/storefronts
10. ceilings
11. stairs
12. roof/parapets/openings
13. materials/Tags
14. persistent Spaces
15. Space-driven partitions only where explicitly evidenced
16. inspect
17. validate
18. diagnose and smallest repair
19. inspect + validate again

Use stable semantic names such as `Level_01`, `Column_3_B_Level_01`, `Beam_1_A_5_A_Level_02`,
`Wall_South_001`, `CurtainWall_Showroom_001`, `Showroom_01`.

## Core commands

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

## Building rules

- Wall thickness is centered on the supplied centerline.
- Wall start/end direction matters because opening offsets are directional.
- Beam endpoints represent bottom centerline and share Z.
- Create wall openings before door/window assemblies.
- Door/window assemblies read opening metadata; do not guess rotation.
- Prefer curtain walls for continuous glazed fronts only when drawings support them.
- Use slab openings where stairs/shafts penetrate floors.
- Tags belong on Groups/Components, never raw edges/faces.
- Functional labels never override drawing dimensions.

## Semantic entity grouping

Use logical OpenSU entity groups when several existing semantic entities should be managed as one assembly without changing the real SketchUp hierarchy.

Typical uses:

- showroom facade or structure set
- one entrance assembly
- one floor's columns or partitions
- workshop bay elements
- furniture/display collections

Commands:

```text
python scripts/opensu_groups.py list
python scripts/opensu_groups.py inspect --group Showroom_Structure
python scripts/opensu_groups.py create --group Showroom_Structure --name Wall_001 --name Column_1_A
python scripts/opensu_groups.py add --group Showroom_Structure --name Beam_1_A_3_A
python scripts/opensu_groups.py remove --group Showroom_Structure --name Beam_1_A_3_A
python scripts/opensu_groups.py prune-missing --group Showroom_Structure
python scripts/opensu_groups.py rename --group Showroom_Structure --new-name Showroom_Main_Structure
python scripts/opensu_groups.py visible --group Showroom_Main_Structure --hide
python scripts/opensu_groups.py tag --group Showroom_Main_Structure --tag A-SHOWROOM
python scripts/opensu_groups.py transform --group Showroom_Main_Structure --translation 1000 0 0
python scripts/opensu_groups.py duplicate --group Showroom_Main_Structure --new-group Showroom_Copy --translation 18000 0 0
python scripts/opensu_groups.py dissolve --group Showroom_Copy
python scripts/opensu_groups.py roots
python scripts/opensu_groups.py tree --group Level_01
python scripts/opensu_groups.py nest --parent Structure --child Columns
python scripts/opensu_groups.py unnest --parent Structure --child Columns
python scripts/opensu_groups.py move --group Columns --parent Level_02
python scripts/opensu_groups.py move --group Columns --to-root
```

Rules:

- Logical grouping does **not** create a parent SketchUp Group and does not reparent member geometry.
- Membership is persisted by SketchUp persistent id, so renaming a member does not break the group.
- Group membership must come from explicit user intent, drawing/semantic evidence, or an existing OpenSU group definition; never infer membership only from spatial proximity.
- A member keeps its original OpenSU type, name, Tag, level/grid/Space references, and semantic metadata.
- The same entity may belong to more than one logical group when that is intentional.
- A child group has at most one parent. The hierarchy is a tree/forest, never a DAG with multiple parents.
- Parent/child links use stable `group_id` values, so renaming a group does not break hierarchy.
- Never create a parent-child link that would form a cycle; `A → B → A` is invalid.
- Parent visibility, Tag, transform, and duplication recurse through all descendants and deduplicate entities that appear more than once.
- A parent group may contain only child groups and zero direct entities.
- Dissolving a parent promotes its children to the dissolved node's parent (or to roots) and never deletes child groups or geometry.
- Group visibility and Tag operations apply to all live members in one undoable SketchUp operation.
- Group transform uses one shared pivot for the whole assembly; it must not rotate each member around its own center.
- Group transform/duplicate currently require OpenSU Groups as members.
- `dissolve` removes only the grouping relationship. It must never delete member geometry.
- If a group references a member that was manually deleted, validation must report the broken semantic reference rather than silently dropping it.
- Use `prune-missing` only after that stale reference is confirmed; it removes missing membership ids but never deletes live geometry.

## Editing and repair

For existing model errors:

```text
python scripts/opensu_repair.py diagnose
python scripts/opensu_repair.py find ...
```

Apply the smallest repair, inspect, validate, and repeat only for remaining issues.

Single-entity edit:

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

Grid/Space-driven entities retain semantic provenance. If later edits move them away from their source grid/Space edge, validation reports semantic drift; never silently snap user geometry back.

## Controlled deletion

Only use:

```text
python scripts/opensu_repair.py delete-confirmed ...
```

Deletion requires explicit user intent, exact entity id, exact current name, and confirmation. Never infer delete targets from partial names or delete arbitrary loose user geometry.

## Inspect / validation expectations

`inspect_model` exposes entities/levels plus `grids`, `spaces`, `entity_groups`, and semantic summary.
`validate_model` checks ordinary geometry/manifold rules, semantic metadata, grid/Space layout references, and persistent entity-group membership.

A finished architecture model should normally have:

- no loose root architecture faces/edges
- zero non-manifold OpenSU solids where solids are expected
- valid levels/grids/spaces
- no broken semantic layout or entity-group references
- final `valid=true`

Semantic drift warnings require review but are not automatically repaired.

## References

- `references/drawing-reconstruction.md`
- `references/multisheet-fusion.md`
- `references/sheet-grid-spaces.md`
- `references/grid-driven-layout.md`
- `references/semantic-grouping.md`
- `references/plan-spec.schema.json`
- `references/examples/showroom-plan-v1.json`
- `references/examples/showroom-multisheet-pack-v1.json`
- `references/examples/showroom-semantics-v1.json`
- `references/tool-contract.md`
- `references/advanced-geometry.md`

## Current limits

- Never use arbitrary Ruby execution.
- Grid/Space metadata is persistent but visible grid bubbles/room labels are not yet generated.
- Entity groups support recursive semantic parent-child trees, but OpenSU still does not reparent them into physical nested SketchUp Groups.
- Grid-driven layout currently supports point resolution, columns, straight beams, and straight Space-edge partition walls.
- It does not yet generate an entire structural framing system from a grid range automatically.
- Straight, L, and U stairs are supported; spiral/multi-landing stairs are not.
- Polygon floors/ceilings may be concave but not self-intersecting.
- Pitched roofs and curved walls are not yet exposed.
- If a request exceeds the tool surface, explain the missing capability instead of pretending it was modeled.
