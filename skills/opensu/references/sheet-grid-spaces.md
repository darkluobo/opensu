# Sheet Index, Grid, and Space Semantics

Phase 5.2 adds persistent drawing semantics around the geometry workflow. These semantics are not decorative geometry. They are model metadata used by Codex to reason consistently across drawing sets and future edits.

## 1. Sheet index

Start a drawing-set task by indexing candidate source files:

```text
python scripts/opensu_semantics.py index-sheets <drawing-folder> --output sheet-index.json
```

The indexer scans PDF/image/CAD-like filenames and infers:

- `sheet_id` when a conventional identifier such as `A-101` is present
- `kind`: plan / elevation / section / detail / schedule / other
- title from filename
- revision when a `Rev A`-style marker is present
- duplicate sheet ids
- files needing manual sheet-id review

Filename inference is only an index aid. Codex must still inspect the actual sheet content before trusting title, revision, kind, scale, or dimensions.

If two files have the same sheet id, review revision/status before using either as authoritative evidence. Do not silently combine superseded and current revisions.

## 2. Grid coordinates

OpenSU grids are stored at model level and do not create loose SketchUp geometry.

Each grid contains:

```json
{
  "name": "3",
  "axis": "x",
  "coordinate_mm": 12000,
  "source_ref": "A-101 grid 3"
}
```

Coordinate convention:

- `axis=x` means a constant X coordinate, normally numbered grids such as 1, 2, 3.
- `axis=y` means a constant Y coordinate, normally lettered grids such as A, B, C.
- This convention is recommended, not universal. Follow the actual drawing set if it clearly uses another convention, but remain internally consistent.
- Grid names are unique model-wide.
- Two grids on the same axis may not share the same coordinate.

For an `A/3` intersection under the recommended convention:

```text
X = grid 3 coordinate
Y = grid A coordinate
```

Columns should use grid intersections when the structural drawing supports that relationship. Do not force non-grid facade mullions, partitions, or equipment onto structural axes.

## 3. Spaces and functional zones

A Space is a 2D semantic polygon attached to a level. It does not generate a floor face or room label automatically.

Example:

```json
{
  "name": "Showroom_01",
  "level_name": "Level_01",
  "boundary_mm": [[0,0],[12000,0],[12000,9000],[0,9000]],
  "program_type": "showroom",
  "department": "sales",
  "zone": "front_of_house",
  "source_ref": "A-101 showroom boundary"
}
```

OpenSU computes and stores `area_m2` from the polygon. Boundaries must be simple, non-self-intersecting polygons.

Recommended program types for dealership work:

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

Program type is semantic guidance, not permission to invent geometry. For example, `showroom` may suggest checking for glazed frontage, but the actual facade still follows plans/elevations/details.

## 4. Semantic spec workflow

Create a semantic JSON file with `grids` and `spaces`, then lint it:

```text
python scripts/opensu_semantics.py lint semantics.json
```

Only after the architectural levels exist in SketchUp, persist it:

```text
python scripts/opensu_semantics.py apply semantics.json
```

`apply` refuses duplicate grid/space names and spaces referencing undefined levels. It finishes with inspect + validate.

Recommended drawing reconstruction sequence:

```text
sheet index
→ inspect sheets
→ multi-sheet evidence pack
→ semantic grid/space spec
→ Plan Spec
→ cross-sheet check
→ semantic lint
→ Plan Spec lint
→ Plan Spec execute
→ semantic apply
→ inspect
→ validate
```

## 5. 4S dealership reasoning

Typical relationships worth encoding explicitly:

- showroom footprint and glazed public frontage
- customer entrance and reception adjacency
- sales consultation within/adjacent to showroom
- customer lounge near aftersales reception but separated from workshop hazards
- workshop bays aligned to structural/service grids when drawings show them
- parts/storage connected to workshop/service circulation
- vehicle delivery area with appropriate access path
- office/support spaces grouped by floor/department

Do not infer missing code-compliance, fire separation, accessibility, or structural requirements from program type alone. Those require explicit project information or authoritative design documents.

## 6. Validation expectations

`inspect_model` now returns:

- `grids`
- `spaces`
- `semantic_summary.grids`
- `semantic_summary.spaces`
- `semantic_summary.space_area_m2`

`validate_model` checks:

- duplicate/invalid grid names
- duplicate same-axis coordinates
- invalid grid axes/coordinates
- duplicate space names
- undefined level references
- malformed/zero-area/self-intersecting space boundaries
- stored area drift warnings

A successful drawing-semantic model should still finish with ordinary geometry validation `valid=true`.
