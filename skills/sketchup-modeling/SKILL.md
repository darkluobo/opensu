---
name: sketchup-modeling
description: >-
  Control a local SketchUp model from Codex through the installed OpenSU/SketchUp MCP
  extension. Use whenever the user asks Codex to create, reconstruct from drawings/PDFs,
  modify, inspect, organize, repair, materialize, or validate architectural SketchUp
  geometry from natural language. Supports auditable Plan Spec reconstruction, levels,
  rectangular or polygon floors/ceilings, slab and roof openings, walls, columns, beams,
  straight/L/U stairs, flat roofs, door/window assemblies, glass curtain walls/storefronts,
  materials, Tags, transforms, duplication, safe batch operations, controlled deletion,
  dimensions, and model QA.
---

# SketchUp Modeling

Use the bundled scripts as deterministic bridges to the installed SketchUp extension:

- `scripts/opensu.py` — stable core modeling.
- `scripts/opensu_advanced.py` — L/U stairs, slab/roof openings, polygon slabs/ceilings.
- `scripts/opensu_edit.py` — single-entity semantic edits.
- `scripts/opensu_repair.py` — search, diagnosis, batch repair, controlled deletion.
- `scripts/opensu_plan.py` — lint and execute drawing-derived Plan Spec JSON.

Resolve scripts relative to this Skill directory. Do not copy them into the user's project
and do not write ad-hoc socket/Ruby code when an exposed command already exists.

## Start every SketchUp task

1. Run `python scripts/opensu.py status`.
2. If it cannot connect, ask the user to open SketchUp and choose
   `Extensions > MCP Server > Start Server`, then retry.
3. Run `python scripts/opensu.py inspect` before changing the model.
4. Treat architectural dimensions as millimetres.
5. Preserve existing user geometry unless the request explicitly changes it.
6. For multi-storey work, inspect existing levels first and define missing levels.

## Drawing / PDF / image reconstruction

When the user asks to reconstruct a plan, PDF, screenshot, exported CAD image, or similar
2D source, do **not** model directly from visual impression. First read
`references/drawing-reconstruction.md`, then create an auditable Plan Spec v1 JSON.

Use this workflow:

1. inspect all supplied sheets/images relevant to the requested model
2. identify units, floor, revision, scale evidence, axes, dimensions, and known elevations
3. establish one stable X/Y/Z coordinate convention
4. extract explicit printed dimensions before using any scale or visual estimate
5. derive secondary coordinates from exact dimensions and wall thicknesses
6. record assumptions and unresolved items in `uncertainties`
7. attach `evidence.confidence` / `source_ref` to important geometry when useful
8. write a Plan Spec v1 JSON using `references/plan-spec.schema.json`
9. run `python scripts/opensu_plan.py lint <spec.json>`
10. fix every lint error before touching SketchUp
11. if blocking uncertainties remain, ask the user unless they explicitly authorized approximation
12. inspect the current SketchUp model and check for conflicting names
13. run `python scripts/opensu_plan.py execute <spec.json>`
14. review the returned inspect/validation result
15. repair only localized errors with edit/repair tools
16. report which dimensions were exact, derived, estimated, or unresolved

Evidence priority for drawing reconstruction:

1. printed dimensions / written levels
2. grid and chained dimensions
3. repeated confirmed modules
4. drawing scale when the source has not been unpredictably resized
5. geometry derived from other exact dimensions
6. pixel/visual estimation only with explicit permission for approximation

Never silently resolve contradictory dimensions. Never treat a resized screenshot's printed
scale as reliable without calibration to at least one known dimension.

## Plan Spec commands

```text
python scripts/opensu_plan.py template
python scripts/opensu_plan.py template --output plan.json
python scripts/opensu_plan.py lint plan.json
python scripts/opensu_plan.py execute plan.json
```

`execute` refuses a spec with lint errors. It also refuses blocking uncertainties unless
`--allow-blocking-uncertainties` is explicitly passed. Use that flag only when the user has
explicitly accepted approximate reconstruction for those unresolved items.

By default, Plan execution also refuses root names that already exist in SketchUp. Do not
use `--allow-existing-names` merely to suppress a collision; inspect and resolve the naming
or scope conflict first.

The Plan Spec may describe:

- levels
- rectangular or polygon floors
- columns and beams
- straight walls
- multiple wall openings plus optional door/window assemblies
- curtain walls/storefront grids
- rectangular or polygon ceilings
- straight/L/U stairs
- flat roofs
- rectangular slab/roof openings
- materials
- Tag assignments

Use the example at `references/examples/showroom-plan-v1.json` as a structural reference,
not as a source of dimensions for the user's project.

## General modeling workflow

For non-drawing tasks, normally execute in this order:

1. define levels/storey elevations
2. floor/slab, including polygon slabs where needed
3. slab circulation/shaft openings
4. primary columns and beams
5. opaque exterior/interior walls
6. door/window openings and assemblies
7. curtain-wall/storefront assemblies
8. ceilings
9. stairs/circulation
10. flat roof/parapets and roof openings
11. materials and Tags
12. inspect
13. validate
14. if validation fails, diagnose the exact entities
15. apply the smallest targeted repair
16. inspect and validate again

Use stable semantic names such as `Level_01`, `Floor_Level01_001`, `Ceiling_Level01_001`,
`Column_A01_001`, `Beam_A01_B01_001`, `Wall_South_001`, `Door_South_001`,
`Window_East_001`, `Stair_L_L01_L02_001`, `CurtainWall_Showroom_001`, and `Roof_Main_001`.

## Repair workflow

When an existing model is wrong, do not immediately rebuild it. Use this sequence:

1. `opensu_repair.py diagnose`
2. inspect the returned issue, matched entity id/name, and repair hint
3. use `opensu_repair.py find` when a broader type/name/tag query is needed
4. apply a single edit or batch edit
5. inspect
6. validate
7. repeat only for remaining errors

Use batch commands when several known entities need the same operation. A batch is one
SketchUp undoable operation, so the user can undo it from SketchUp if needed.

## Single-entity editing

Use `opensu_edit.py` for:

- `rename`: rename one root Group/Component.
- `set-tag`: assign a SketchUp Tag to one root Group/Component.
- `set-visible`: show/hide one root entity.
- `transform`: move/rotate one OpenSU Group while synchronizing semantic coordinates.
- `duplicate`: copy one OpenSU Group with a unique name and optional offset/rotation.

After any transform or duplicate, run `inspect` and `validate` immediately.

## Batch repair

Use `opensu_repair.py` for:

- `find`: filter root Groups/Components by name fragment, OpenSU type, Tag, or visibility.
- `diagnose`: run validation and map messages back to named root entities when possible.
- `batch-tag`: assign one Tag to multiple known root entities.
- `batch-visible`: show/hide multiple known root entities.
- `batch-transform`: apply one translation/Z rotation to multiple OpenSU Groups while
  synchronizing semantic coordinates for each object.

Do not batch-transform mixed non-OpenSU content. Resolve exact target ids first.

## Controlled deletion

Deletion is exposed only through `opensu_repair.py delete-confirmed`. Use it only when the
user explicitly asks to delete/remove an object or has explicitly authorized removal as
part of a repair.

Before deleting:

1. inspect/find the target
2. capture its `entity_id` and exact current name
3. confirm it is an OpenSU semantic root entity
4. call delete with exact id, exact name, and confirmation flag
5. inspect and validate immediately

Never infer a delete target from a partial name. Never delete loose faces/edges or arbitrary
non-OpenSU user geometry.

## Building reasoning rules

- Level metadata is model-level data; do not fake storeys with labels only.
- Wall thickness is centered on the supplied wall centerline.
- Preserve a deliberate wall start/end direction because opening offsets are measured from start.
- Keep column centers on explicit grid intersections when a structural grid exists.
- Beam start/end coordinates represent the bottom centerline and should share Z.
- Door/window assemblies read opening metadata from the wall; do not guess rotation.
- Prefer `create-curtain-wall` for continuous glazed showroom/dealership fronts.
- Use a floor opening when a stair passes through an upper slab.
- Tags belong on Groups/Components, never raw edges/faces.
- Re-inspect after structural, opening, facade, circulation, roof, and edit batches.

## Core commands

```text
python scripts/opensu.py status
python scripts/opensu.py inspect
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
python scripts/opensu.py validate
```

Advanced geometry:

```text
python scripts/opensu_advanced.py create-l-stair ...
python scripts/opensu_advanced.py create-u-stair ...
python scripts/opensu_advanced.py create-slab-opening ...
python scripts/opensu_advanced.py create-polygon-slab ...
python scripts/opensu_advanced.py create-polygon-ceiling ...
```

Single edit:

```text
python scripts/opensu_edit.py rename ...
python scripts/opensu_edit.py set-tag ...
python scripts/opensu_edit.py set-visible ...
python scripts/opensu_edit.py transform ...
python scripts/opensu_edit.py duplicate ...
```

Repair/batch:

```text
python scripts/opensu_repair.py find ...
python scripts/opensu_repair.py diagnose ...
python scripts/opensu_repair.py batch-tag ...
python scripts/opensu_repair.py batch-visible ...
python scripts/opensu_repair.py batch-transform ...
python scripts/opensu_repair.py delete-confirmed ...
```

## References

- `references/drawing-reconstruction.md` — drawing/PDF evidence and reconstruction rules.
- `references/plan-spec.schema.json` — Plan Spec v1 structural contract.
- `references/examples/showroom-plan-v1.json` — example only.
- `references/tool-contract.md` — core command details.
- `references/advanced-geometry.md` — advanced geometry details.

## Safety and current limits

- Never use arbitrary Ruby execution or invent unsupported SketchUp capabilities.
- Keep architecture in named Groups/Components rather than loose root geometry.
- Plan Spec v1 is an interpretation/execution layer; it does not magically make an unreadable
  drawing reliable. Preserve uncertainty instead of inventing dimensions.
- Semantic transforms/batch transforms are restricted to OpenSU Groups.
- Controlled deletion requires exact-id + exact-name confirmation.
- Straight, L-shaped, and U-shaped stairs are supported; spiral/multi-landing stairs are not.
- Polygon floors/ceilings may be concave but may not self-intersect.
- Pitched roofs and curved walls are not yet exposed.
- Plan Spec slab openings currently target rectangular floor/ceiling/flat-roof objects.
- If a request exceeds the current tool surface, explain the missing capability instead of pretending it was modeled.
