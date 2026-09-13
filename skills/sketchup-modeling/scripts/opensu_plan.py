#!/usr/bin/env python3
"""Auditable drawing-plan reconstruction bridge for the sketchup-modeling Codex Skill.

Codex should first translate a drawing/PDF/image into a Plan Spec JSON document, lint it,
and only then execute it against the local OpenSU SketchUp extension.
"""

from __future__ import annotations

import argparse
import json
import math
from pathlib import Path
from typing import Any

from opensu import OpenSUError, _inspect, _print, _send

SCHEMA_VERSION = 1
CONFIDENCE_VALUES = {"high", "medium", "low"}
ROOT_SECTIONS = (
    "floors",
    "columns",
    "beams",
    "walls",
    "curtain_walls",
    "ceilings",
    "stairs",
    "roofs",
)


def _load(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except OSError as exc:
        raise OpenSUError(f"Cannot read Plan Spec: {path}") from exc
    except json.JSONDecodeError as exc:
        raise OpenSUError(f"Invalid Plan Spec JSON at line {exc.lineno}, column {exc.colno}: {exc.msg}") from exc
    if not isinstance(value, dict):
        raise OpenSUError("Plan Spec root must be a JSON object.")
    return value


def _is_num(value: Any) -> bool:
    return isinstance(value, (int, float)) and not isinstance(value, bool) and math.isfinite(float(value))


def _point(value: Any) -> bool:
    return isinstance(value, list) and len(value) == 3 and all(_is_num(item) for item in value)


def _positive(value: Any) -> bool:
    return _is_num(value) and float(value) > 0.0


def _section(spec: dict[str, Any], name: str) -> list[dict[str, Any]]:
    value = spec.get(name, [])
    if value is None:
        return []
    if not isinstance(value, list):
        return []
    return [item for item in value if isinstance(item, dict)]


def _name(item: dict[str, Any]) -> str | None:
    value = item.get("name")
    return value.strip() if isinstance(value, str) and value.strip() else None


def _confidence(item: dict[str, Any], label: str, warnings: list[str]) -> None:
    evidence = item.get("evidence")
    if evidence is None:
        return
    if not isinstance(evidence, dict):
        warnings.append(f"{label}: evidence should be an object.")
        return
    confidence = evidence.get("confidence")
    if confidence is not None and confidence not in CONFIDENCE_VALUES:
        warnings.append(f"{label}: evidence.confidence should be high/medium/low.")


def _lint(spec: dict[str, Any]) -> dict[str, Any]:
    errors: list[str] = []
    warnings: list[str] = []

    if spec.get("schema_version") != SCHEMA_VERSION:
        errors.append(f"schema_version must be {SCHEMA_VERSION}.")

    project = spec.get("project")
    if not isinstance(project, dict):
        errors.append("project must be an object.")
    elif project.get("units") != "mm":
        errors.append("project.units must be 'mm'.")

    uncertainties = spec.get("uncertainties", [])
    if not isinstance(uncertainties, list):
        errors.append("uncertainties must be an array.")
        uncertainties = []
    blocking_uncertainties = []
    for index, item in enumerate(uncertainties):
        if not isinstance(item, dict):
            errors.append(f"uncertainties[{index}] must be an object.")
            continue
        if not isinstance(item.get("description"), str) or not item.get("description", "").strip():
            errors.append(f"uncertainties[{index}] needs a description.")
        if item.get("blocking") is True:
            blocking_uncertainties.append(item)

    levels = _section(spec, "levels")
    level_names: set[str] = set()
    level_elevations: set[float] = set()
    for index, level in enumerate(levels):
        name = _name(level)
        if not name:
            errors.append(f"levels[{index}] needs a name.")
            continue
        if name in level_names:
            errors.append(f"Duplicate level name: {name}.")
        level_names.add(name)
        elevation = level.get("elevation_mm")
        if not _is_num(elevation):
            errors.append(f"Level {name}: elevation_mm must be finite.")
        else:
            rounded = round(float(elevation), 3)
            if rounded in level_elevations:
                errors.append(f"Duplicate level elevation: {rounded} mm.")
            level_elevations.add(rounded)
        if level.get("floor_to_floor_mm") is not None and not _positive(level.get("floor_to_floor_mm")):
            errors.append(f"Level {name}: floor_to_floor_mm must be positive.")
        _confidence(level, f"Level {name}", warnings)

    root_names: set[str] = set()
    roots_by_name: dict[str, tuple[str, dict[str, Any]]] = {}
    for section_name in ROOT_SECTIONS:
        raw = spec.get(section_name, [])
        if raw is not None and not isinstance(raw, list):
            errors.append(f"{section_name} must be an array.")
            continue
        for index, item in enumerate(_section(spec, section_name)):
            name = _name(item)
            if not name:
                errors.append(f"{section_name}[{index}] needs a name.")
                continue
            if name in root_names:
                errors.append(f"Duplicate root entity name in Plan Spec: {name}.")
            root_names.add(name)
            roots_by_name[name] = (section_name, item)
            _confidence(item, f"{section_name}:{name}", warnings)

    def check_level_ref(item: dict[str, Any], label: str) -> None:
        level_name = item.get("level_name")
        if level_name and level_name not in level_names:
            errors.append(f"{label}: references undefined level {level_name!r}.")

    for item in _section(spec, "floors"):
        name = _name(item) or "<unnamed floor>"
        shape = item.get("shape", "rect")
        if shape == "rect":
            if not _point(item.get("origin_mm")):
                errors.append(f"Floor {name}: origin_mm must be [x,y,z].")
            if not _positive(item.get("width_mm")) or not _positive(item.get("depth_mm")):
                errors.append(f"Floor {name}: width_mm/depth_mm must be positive.")
        elif shape == "polygon":
            points = item.get("points_mm")
            if not isinstance(points, list) or len(points) < 3 or not all(_point(point) for point in points):
                errors.append(f"Floor {name}: polygon points_mm requires at least three 3D points.")
            elif len({round(float(p[2]), 6) for p in points}) != 1:
                errors.append(f"Floor {name}: all polygon points must share one Z elevation.")
        else:
            errors.append(f"Floor {name}: unsupported shape {shape!r}.")
        if not _positive(item.get("thickness_mm", 150)):
            errors.append(f"Floor {name}: thickness_mm must be positive.")
        check_level_ref(item, f"Floor {name}")

    for item in _section(spec, "columns"):
        name = _name(item) or "<unnamed column>"
        if not _point(item.get("center_mm")):
            errors.append(f"Column {name}: center_mm must be [x,y,z].")
        for key in ("width_mm", "depth_mm", "height_mm"):
            if not _positive(item.get(key)):
                errors.append(f"Column {name}: {key} must be positive.")
        check_level_ref(item, f"Column {name}")

    for item in _section(spec, "beams"):
        name = _name(item) or "<unnamed beam>"
        start, end = item.get("start_mm"), item.get("end_mm")
        if not _point(start) or not _point(end):
            errors.append(f"Beam {name}: start_mm/end_mm must be 3D points.")
        elif abs(float(start[2]) - float(end[2])) > 0.001:
            errors.append(f"Beam {name}: start/end Z must match.")
        if not _positive(item.get("width_mm")) or not _positive(item.get("height_mm")):
            errors.append(f"Beam {name}: width_mm/height_mm must be positive.")
        check_level_ref(item, f"Beam {name}")

    walls: dict[str, dict[str, Any]] = {}
    for item in _section(spec, "walls"):
        name = _name(item) or "<unnamed wall>"
        start, end = item.get("start_mm"), item.get("end_mm")
        if not _point(start) or not _point(end):
            errors.append(f"Wall {name}: start_mm/end_mm must be 3D points.")
            continue
        if abs(float(start[2]) - float(end[2])) > 0.001:
            errors.append(f"Wall {name}: start/end Z must match.")
        if math.hypot(float(end[0]) - float(start[0]), float(end[1]) - float(start[1])) <= 0.001:
            errors.append(f"Wall {name}: start and end cannot coincide.")
        if not _positive(item.get("height_mm")) or not _positive(item.get("thickness_mm")):
            errors.append(f"Wall {name}: height_mm/thickness_mm must be positive.")
        walls[name] = item
        check_level_ref(item, f"Wall {name}")

    openings_by_wall: dict[str, list[dict[str, Any]]] = {}
    openings_raw = spec.get("openings", [])
    if openings_raw is not None and not isinstance(openings_raw, list):
        errors.append("openings must be an array.")
    opening_names: set[str] = set()
    for index, opening in enumerate(_section(spec, "openings")):
        name = _name(opening)
        if not name:
            errors.append(f"openings[{index}] needs a name.")
            continue
        if name in opening_names:
            errors.append(f"Duplicate opening name: {name}.")
        opening_names.add(name)
        wall_name = opening.get("wall_name")
        if wall_name not in walls:
            errors.append(f"Opening {name}: wall_name {wall_name!r} is not defined in walls.")
            continue
        wall = walls[wall_name]
        start, end = wall["start_mm"], wall["end_mm"]
        wall_length = math.hypot(float(end[0]) - float(start[0]), float(end[1]) - float(start[1]))
        offset = opening.get("offset_mm")
        width = opening.get("width_mm")
        height = opening.get("height_mm")
        sill = opening.get("sill_height_mm", 0)
        if not _is_num(offset) or float(offset) < 0 or not _positive(width):
            errors.append(f"Opening {name}: offset_mm must be >=0 and width_mm positive.")
        elif float(offset) + float(width) > wall_length + 0.001:
            errors.append(f"Opening {name}: exceeds wall {wall_name} length ({wall_length:.3f} mm).")
        if not _positive(height) or not _is_num(sill) or float(sill) < 0:
            errors.append(f"Opening {name}: height_mm must be positive and sill_height_mm >=0.")
        elif float(sill) + float(height) > float(wall.get("height_mm", 0)) + 0.001:
            errors.append(f"Opening {name}: exceeds wall {wall_name} height.")
        if opening.get("opening_type") not in {None, "door", "window", "void"}:
            warnings.append(f"Opening {name}: unusual opening_type {opening.get('opening_type')!r}.")
        openings_by_wall.setdefault(wall_name, []).append(opening)
        _confidence(opening, f"Opening {name}", warnings)

    for wall_name, items in openings_by_wall.items():
        spans = []
        for item in items:
            if _is_num(item.get("offset_mm")) and _positive(item.get("width_mm")):
                spans.append((float(item["offset_mm"]), float(item["offset_mm"]) + float(item["width_mm"]), _name(item) or "?"))
        spans.sort()
        for left, right in zip(spans, spans[1:]):
            if right[0] < left[1] - 0.001:
                errors.append(f"Wall {wall_name}: openings {left[2]} and {right[2]} overlap horizontally.")

    for section_name in ("curtain_walls", "ceilings", "stairs", "roofs"):
        for item in _section(spec, section_name):
            check_level_ref(item, f"{section_name}:{_name(item) or '?'}")

    for item in _section(spec, "curtain_walls"):
        name = _name(item) or "<unnamed curtain wall>"
        if not _point(item.get("start_mm")) or not _point(item.get("end_mm")):
            errors.append(f"Curtain wall {name}: start_mm/end_mm must be 3D points.")
        if not _positive(item.get("height_mm")):
            errors.append(f"Curtain wall {name}: height_mm must be positive.")

    for item in _section(spec, "ceilings"):
        name = _name(item) or "<unnamed ceiling>"
        shape = item.get("shape", "rect")
        if shape == "rect":
            if not _point(item.get("origin_mm")) or not _positive(item.get("width_mm")) or not _positive(item.get("depth_mm")):
                errors.append(f"Ceiling {name}: rectangular geometry is incomplete.")
        elif shape == "polygon":
            points = item.get("points_mm")
            if not isinstance(points, list) or len(points) < 3 or not all(_point(point) for point in points):
                errors.append(f"Ceiling {name}: polygon points_mm requires at least three 3D points.")
        else:
            errors.append(f"Ceiling {name}: unsupported shape {shape!r}.")
        if not _positive(item.get("thickness_mm", 100)):
            errors.append(f"Ceiling {name}: thickness_mm must be positive.")

    for item in _section(spec, "stairs"):
        name = _name(item) or "<unnamed stair>"
        kind = item.get("kind", "straight")
        if kind == "straight":
            if not _point(item.get("start_mm")) or not _point(item.get("end_mm")):
                errors.append(f"Stair {name}: straight stair needs start_mm/end_mm.")
        elif kind in {"l", "u"}:
            if not _point(item.get("origin_mm")) or not _positive(item.get("run1_mm")) or not _positive(item.get("run2_mm")):
                errors.append(f"Stair {name}: {kind.upper()} stair needs origin_mm and positive run1_mm/run2_mm.")
            if not _is_num(item.get("end_elevation_mm")):
                errors.append(f"Stair {name}: end_elevation_mm is required.")
        else:
            errors.append(f"Stair {name}: unsupported kind {kind!r}.")

    slab_targets = {
        _name(item)
        for section_name in ("floors", "ceilings", "roofs")
        for item in _section(spec, section_name)
        if _name(item)
    }
    slab_openings_raw = spec.get("slab_openings", [])
    if slab_openings_raw is not None and not isinstance(slab_openings_raw, list):
        errors.append("slab_openings must be an array.")
    for index, item in enumerate(_section(spec, "slab_openings")):
        name = _name(item)
        if not name:
            errors.append(f"slab_openings[{index}] needs a name.")
        target = item.get("target_name")
        if target not in slab_targets:
            errors.append(f"Slab opening {name or index}: target_name {target!r} is not a floor/ceiling/roof in this Plan Spec.")
        for key in ("offset_x_mm", "offset_y_mm", "width_mm", "depth_mm"):
            value = item.get(key)
            if key.startswith("offset"):
                if not _is_num(value) or float(value) <= 0:
                    errors.append(f"Slab opening {name or index}: {key} must be >0.")
            elif not _positive(value):
                errors.append(f"Slab opening {name or index}: {key} must be positive.")

    for section_name in ("materials", "tags"):
        raw = spec.get(section_name, [])
        if raw is not None and not isinstance(raw, list):
            errors.append(f"{section_name} must be an array.")

    counts = {section: len(_section(spec, section)) for section in (*ROOT_SECTIONS, "openings", "slab_openings", "materials", "tags", "levels")}
    return {
        "valid": not errors,
        "errors": errors,
        "warnings": warnings,
        "blocking_uncertainties": blocking_uncertainties,
        "counts": counts,
    }


def _root_names(spec: dict[str, Any]) -> set[str]:
    names: set[str] = set()
    for section_name in ROOT_SECTIONS:
        for item in _section(spec, section_name):
            name = _name(item)
            if name:
                names.add(name)
    return names


def _find_id(name: str, created: dict[str, int]) -> int:
    if name in created:
        return created[name]
    model = _inspect(1000)
    matches = [item for item in model.get("entities", []) if item.get("name") == name]
    if not matches:
        raise OpenSUError(f"No root entity named {name!r} exists in SketchUp.")
    if len(matches) > 1:
        raise OpenSUError(f"More than one root entity named {name!r}; Plan execution requires unique names.")
    return int(matches[0]["entity_id"])


def _remember(name: str, result: Any, created: dict[str, int]) -> None:
    if isinstance(result, dict) and result.get("entity_id") is not None:
        created[name] = int(result["entity_id"])


def _execute(spec: dict[str, Any], allow_blocking_uncertainties: bool, allow_existing_names: bool) -> dict[str, Any]:
    lint = _lint(spec)
    if not lint["valid"]:
        raise OpenSUError("Plan Spec lint failed; run `opensu_plan.py lint` and fix errors first.")
    if lint["blocking_uncertainties"] and not allow_blocking_uncertainties:
        raise OpenSUError("Plan Spec contains blocking uncertainties. Resolve them or explicitly pass --allow-blocking-uncertainties.")

    before = _inspect(1000)
    existing_names = {item.get("name") for item in before.get("entities", []) if item.get("name")}
    collisions = sorted(_root_names(spec) & existing_names)
    if collisions and not allow_existing_names:
        raise OpenSUError(f"Plan Spec names already exist in SketchUp: {', '.join(collisions)}")

    existing_levels = {item.get("name") for item in before.get("levels", []) if isinstance(item, dict)}
    created: dict[str, int] = {}
    steps: list[dict[str, Any]] = []

    def run(label: str, command: str, payload: dict[str, Any], remember_name: str | None = None) -> Any:
        result = _send(command, payload)
        steps.append({"label": label, "command": command, "result": result})
        if remember_name:
            _remember(remember_name, result, created)
        return result

    for item in _section(spec, "levels"):
        name = _name(item)
        if name in existing_levels:
            continue
        payload = {"name": name, "elevation_mm": item["elevation_mm"]}
        if item.get("floor_to_floor_mm") is not None:
            payload["floor_to_floor_mm"] = item["floor_to_floor_mm"]
        run(f"level:{name}", "define_level", payload)

    for item in _section(spec, "floors"):
        name = _name(item)
        if item.get("shape", "rect") == "polygon":
            run(f"floor:{name}", "create_polygon_slab", {"points_mm": item["points_mm"], "thickness_mm": item.get("thickness_mm", 150), "level_name": item.get("level_name"), "name": name}, name)
        else:
            run(f"floor:{name}", "create_floor", {"origin": item["origin_mm"], "width_mm": item["width_mm"], "depth_mm": item["depth_mm"], "thickness_mm": item.get("thickness_mm", 150), "name": name}, name)

    for item in _section(spec, "columns"):
        name = _name(item)
        run(f"column:{name}", "create_column", {"center_mm": item["center_mm"], "width_mm": item["width_mm"], "depth_mm": item["depth_mm"], "height_mm": item["height_mm"], "name": name}, name)

    for item in _section(spec, "beams"):
        name = _name(item)
        run(f"beam:{name}", "create_beam", {"start_mm": item["start_mm"], "end_mm": item["end_mm"], "width_mm": item["width_mm"], "height_mm": item["height_mm"], "name": name}, name)

    for item in _section(spec, "walls"):
        name = _name(item)
        run(f"wall:{name}", "create_wall", {"start": item["start_mm"], "end": item["end_mm"], "height_mm": item["height_mm"], "thickness_mm": item["thickness_mm"], "name": name}, name)

    for item in _section(spec, "openings"):
        name = _name(item)
        wall_name = item["wall_name"]
        wall_id = _find_id(wall_name, created)
        payload = {
            "wall_id": wall_id,
            "offset_mm": item["offset_mm"],
            "width_mm": item["width_mm"],
            "height_mm": item["height_mm"],
            "sill_height_mm": item.get("sill_height_mm", 0),
            "opening_type": item.get("opening_type"),
            "name": name,
        }
        run(f"opening:{name}", "create_opening", payload)
        if item.get("create_assembly"):
            opening_type = item.get("opening_type")
            assembly_name = item.get("assembly_name") or f"{name}_Assembly"
            if opening_type == "door":
                result = run(f"door:{assembly_name}", "create_door", {"wall_id": wall_id, "opening_name": name, "frame_width_mm": item.get("frame_width_mm", 60), "gap_mm": item.get("gap_mm", 5), "leaf_depth_mm": item.get("leaf_depth_mm", 40), "name": assembly_name}, assembly_name)
                _remember(assembly_name, result, created)
            elif opening_type == "window":
                result = run(f"window:{assembly_name}", "create_window", {"wall_id": wall_id, "opening_name": name, "frame_width_mm": item.get("frame_width_mm", 60), "gap_mm": item.get("gap_mm", 5), "glass_thickness_mm": item.get("glass_thickness_mm", 8), "name": assembly_name}, assembly_name)
                _remember(assembly_name, result, created)

    for item in _section(spec, "curtain_walls"):
        name = _name(item)
        run(f"curtain_wall:{name}", "create_curtain_wall", {
            "start_mm": item["start_mm"], "end_mm": item["end_mm"], "height_mm": item["height_mm"],
            "panel_width_mm": item.get("panel_width_mm", 1500), "row_height_mm": item.get("row_height_mm", item["height_mm"]),
            "mullion_width_mm": item.get("mullion_width_mm", 60), "mullion_depth_mm": item.get("mullion_depth_mm", 100),
            "glass_thickness_mm": item.get("glass_thickness_mm", 10), "gap_mm": item.get("gap_mm", 8),
            "frame_color_hex": item.get("frame_color_hex", "#3F4448"), "glass_color_hex": item.get("glass_color_hex", "#9CC9E8"),
            "glass_opacity": item.get("glass_opacity", 0.35), "name": name,
        }, name)

    for item in _section(spec, "ceilings"):
        name = _name(item)
        if item.get("shape", "rect") == "polygon":
            run(f"ceiling:{name}", "create_polygon_ceiling", {"points_mm": item["points_mm"], "thickness_mm": item.get("thickness_mm", 100), "level_name": item.get("level_name"), "name": name}, name)
        else:
            run(f"ceiling:{name}", "create_ceiling", {"origin_mm": item["origin_mm"], "width_mm": item["width_mm"], "depth_mm": item["depth_mm"], "thickness_mm": item.get("thickness_mm", 100), "level_name": item.get("level_name"), "name": name}, name)

    for item in _section(spec, "stairs"):
        name = _name(item)
        kind = item.get("kind", "straight")
        if kind == "straight":
            payload = {"start_mm": item["start_mm"], "end_mm": item["end_mm"], "width_mm": item.get("width_mm", 1200), "target_riser_height_mm": item.get("target_riser_height_mm", 165), "level_name": item.get("level_name"), "name": name}
            if item.get("riser_count") is not None:
                payload["riser_count"] = item["riser_count"]
            run(f"stair:{name}", "create_stair", payload, name)
        else:
            payload = {"origin_mm": item["origin_mm"], "direction": item.get("direction", "x+"), "turn": item.get("turn", "left"), "width_mm": item.get("width_mm", 1200), "run1_mm": item["run1_mm"], "run2_mm": item["run2_mm"], "end_elevation_mm": item["end_elevation_mm"], "target_riser_height_mm": item.get("target_riser_height_mm", 165), "level_name": item.get("level_name"), "name": name}
            if item.get("riser_count") is not None:
                payload["riser_count"] = item["riser_count"]
            if kind == "l":
                payload["landing_length_mm"] = item.get("landing_length_mm", item.get("width_mm", 1200))
                run(f"stair:{name}", "create_l_stair", payload, name)
            else:
                payload["gap_mm"] = item.get("gap_mm", 200)
                payload["landing_depth_mm"] = item.get("landing_depth_mm", item.get("width_mm", 1200))
                run(f"stair:{name}", "create_u_stair", payload, name)

    for item in _section(spec, "roofs"):
        name = _name(item)
        run(f"roof:{name}", "create_flat_roof", {"origin_mm": item["origin_mm"], "width_mm": item["width_mm"], "depth_mm": item["depth_mm"], "slab_thickness_mm": item.get("slab_thickness_mm", 180), "parapet_height_mm": item.get("parapet_height_mm", 900), "parapet_thickness_mm": item.get("parapet_thickness_mm", 150), "level_name": item.get("level_name"), "name": name}, name)

    for item in _section(spec, "slab_openings"):
        name = _name(item)
        target_id = _find_id(item["target_name"], created)
        run(f"slab_opening:{name}", "create_slab_opening", {"entity_id": target_id, "offset_x_mm": item["offset_x_mm"], "offset_y_mm": item["offset_y_mm"], "width_mm": item["width_mm"], "depth_mm": item["depth_mm"], "opening_type": item.get("opening_type", "void"), "name": name})

    for item in _section(spec, "materials"):
        target_id = _find_id(item["target_name"], created)
        run(f"material:{item['target_name']}", "apply_material", {"entity_id": target_id, "material_name": item.get("material_name", "OpenSU_Material"), "color_hex": item.get("color_hex", "#B8B8B8"), "opacity": item.get("opacity", 1.0), "recursive": item.get("recursive", True)})

    for item in _section(spec, "tags"):
        target_ids = [_find_id(name, created) for name in item.get("target_names", [])]
        if not target_ids:
            continue
        run(f"tag:{item.get('tag_name')}", "batch_set_tag", {"entity_ids": target_ids, "tag_name": item["tag_name"]})

    after = _inspect(1000)
    validation = _send("validate_model", {"max_entities": 5000})
    return {
        "ok": bool(validation.get("valid")) if isinstance(validation, dict) else False,
        "plan_counts": lint["counts"],
        "warnings": lint["warnings"],
        "blocking_uncertainties": lint["blocking_uncertainties"],
        "created_ids": created,
        "step_count": len(steps),
        "steps": steps,
        "inspect": after,
        "validation": validation,
    }


def _template() -> dict[str, Any]:
    return {
        "schema_version": 1,
        "project": {"name": "Drawing_Reconstruction", "units": "mm", "source": "plan.pdf", "source_revision": ""},
        "assumptions": [],
        "uncertainties": [],
        "levels": [{"name": "Level_01", "elevation_mm": 0, "floor_to_floor_mm": 4500, "evidence": {"confidence": "high", "source_ref": "dimension"}}],
        "floors": [{"name": "Floor_Level01_001", "shape": "rect", "origin_mm": [0, 0, 0], "width_mm": 12000, "depth_mm": 8000, "thickness_mm": 150, "level_name": "Level_01"}],
        "columns": [], "beams": [],
        "walls": [{"name": "Wall_South_001", "start_mm": [0, 0, 150], "end_mm": [12000, 0, 150], "height_mm": 4200, "thickness_mm": 200, "level_name": "Level_01"}],
        "openings": [{"name": "Door_South_Opening_001", "wall_name": "Wall_South_001", "opening_type": "door", "offset_mm": 1500, "width_mm": 1200, "height_mm": 2400, "sill_height_mm": 0, "create_assembly": True, "assembly_name": "Door_South_001"}],
        "curtain_walls": [], "ceilings": [], "stairs": [], "roofs": [], "slab_openings": [], "materials": [],
        "tags": [{"tag_name": "A-WALL", "target_names": ["Wall_South_001"]}],
    }


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Lint and execute OpenSU drawing Plan Spec JSON files.")
    sub = parser.add_subparsers(dest="command", required=True)

    p = sub.add_parser("template", help="Print or write a minimal Plan Spec v1 template.")
    p.add_argument("--output", type=Path)

    p = sub.add_parser("lint", help="Validate a Plan Spec without changing SketchUp.")
    p.add_argument("spec", type=Path)

    p = sub.add_parser("execute", help="Execute a lint-clean Plan Spec against the local SketchUp extension.")
    p.add_argument("spec", type=Path)
    p.add_argument("--allow-blocking-uncertainties", action="store_true")
    p.add_argument("--allow-existing-names", action="store_true")

    return parser


def main() -> int:
    args = build_parser().parse_args()
    try:
        if args.command == "template":
            value = _template()
            if args.output:
                args.output.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
                _print({"ok": True, "output": str(args.output)})
            else:
                _print(value)
            return 0

        spec = _load(args.spec)
        lint = _lint(spec)
        if args.command == "lint":
            _print({"ok": lint["valid"], "lint": lint})
            return 0 if lint["valid"] else 2

        result = _execute(spec, args.allow_blocking_uncertainties, args.allow_existing_names)
        _print(result)
        return 0 if result.get("ok") else 3
    except OpenSUError as exc:
        _print({"ok": False, "error": str(exc)})
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
