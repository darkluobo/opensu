# Grid-driven layout and dealership program reasoning

Use this reference after levels, grids, and spaces are already persisted in the SketchUp model.
The purpose of this layer is to convert verified architectural semantics into geometry without
recomputing coordinates in free-form reasoning.

## Core rule

Authoritative drawings remain the source of dimensions. Grids and Spaces are coordinate and
program semantics, not permission to invent sizes.

Use grids for exact XY location and Levels for Z. Use Space boundaries for partitions only when
the drawing or the user explicitly indicates the Space boundary is also a wall/partition line.
A semantic Space may represent an open functional zone with no walls.

## Grid intersection convention

By default:

- numbered grid -> X axis
- letter grid -> Y axis
- `3/B` means X from grid `3`, Y from grid `B`

If the project documents use another convention, preserve the real project convention. Do not
swap axes midway through a project.

Commands:

```text
python scripts/opensu_layout.py grid-point --at 3/B --level Level_01
python scripts/opensu_layout.py grid-column --at 3/B --level Level_01 --width 500 --depth 500
python scripts/opensu_layout.py grid-beam --from 1/A --to 5/A --level Level_02 --bottom-offset -600
```

`grid-column` uses the Level `floor_to_floor_mm` as column height when `--height` is omitted.
If the Level has no floor-to-floor value, height must be provided explicitly.

`grid-beam` uses explicit beam width/height and resolves both beam endpoints from persisted grids.
The supplied level plus bottom offset controls the beam bottom elevation.

## Space-driven partitions

A Space is not automatically a room. Before creating walls from a Space boundary, verify that
those boundary edges correspond to physical partitions in the source drawing.

Create all perimeter edges only when the whole Space is enclosed by walls:

```text
python scripts/opensu_layout.py space-walls --space Office_01 --thickness 100
```

Create selected zero-based edges when only part of the boundary is a partition:

```text
python scripts/opensu_layout.py space-walls --space Aftersales_Reception_01 --edges 1 2 --thickness 120
```

If `--height` is omitted, the Space level must have `floor_to_floor_mm`.
All generated partition walls are one SketchUp undoable operation.

## Advisory program strategy

`space-strategy` is read-only and advisory:

```text
python scripts/opensu_layout.py space-strategy --space Showroom_01
```

It may suggest modeling priorities such as:

- showroom -> check continuous glazed frontage / preserve display bays
- workshop -> use verified structural grid / preserve large service bays
- reception/customer lounge -> light partitions when drawings show them
- parts/storage -> storage-sensitive enclosure
- circulation -> do not block the route

These suggestions never create geometry by themselves and never override plan/elevation/section dimensions.

## 4S dealership examples

### Showroom

Use grid-driven columns only where the structural plan shows columns. Use curtain wall tools only where
elevation/plan evidence shows continuous glazing. Do not add internal walls merely because a Showroom Space exists.

### Workshop

Use verified grid intersections for structural columns and grid spans for beams. Service-bay module spacing,
lifts, pits, doors, and equipment clearances require project evidence; do not derive them from the word `workshop`.

### Aftersales reception / customer lounge

Space boundaries are useful for organizing front-of-house zones, but many boundaries may be open circulation
edges. Generate only the partition edges evidenced in the plan.

## Validation behavior

Grid/Space-driven entities store semantic provenance in OpenSU attributes:

- `layout_source=grid_intersection` for grid columns
- `layout_source=grid_span` for grid beams
- `layout_source=space_boundary` for Space partitions

`validate_model` checks referenced grids, levels, and spaces still exist. If geometry is later moved away from its
semantic source, validation emits a drift warning rather than deleting or snapping geometry automatically.

This is deliberate: Codex should surface semantic drift and ask/repair deliberately instead of silently moving user geometry.
