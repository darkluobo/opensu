#!/usr/bin/env python3
"""Sheet indexing and persistent grid/space semantics for the sketchup-modeling Skill."""

from __future__ import annotations

import argparse
import json
import math
import re
from pathlib import Path
from typing import Any

from opensu import OpenSUError, _inspect, _print, _send

SCHEMA_VERSION = 1
DRAWING_EXTENSIONS = {".pdf", ".png", ".jpg", ".jpeg", ".tif", ".tiff", ".dwg", ".dxf"}
SHEET_ID_RE = re.compile(r"(?<![A-Z0-9])([A-Z]{1,4})[-_ ]?(\d{2,4})(?!\d)", re.IGNORECASE)
REV_RE = re.compile(r"(?:(?<![A-Z0-9])rev(?:ision)?|版次|版本)[-_ .]*([A-Z0-9]+)", re.IGNORECASE)
KIND_RULES = (
    ("schedule", ("schedule", "door schedule", "window schedule", "门窗表", "材料表", "设备表", "表格")),
    ("section", ("section", "剖面")),
    ("elevation", ("elevation", "立面")),
    ("detail", ("detail", "详图", "节点", "大样")),
    ("plan", ("plan", "floor plan", "平面", "总平")),
)
PROGRAM_TYPES = {
    "showroom", "sales", "reception", "customer_lounge", "delivery", "aftersales_reception",
    "workshop", "parts", "office", "support", "circulation", "service", "storage", "other",
}


def _load(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except OSError as exc:
        raise OpenSUError(f"Cannot read semantic spec: {path}") from exc
    except json.JSONDecodeError as exc:
        raise OpenSUError(f"Invalid semantic JSON at line {exc.lineno}, column {exc.colno}: {exc.msg}") from exc
    if not isinstance(value, dict):
        raise OpenSUError("Semantic spec root must be a JSON object.")
    return value


def _sheet_id(name: str) -> str | None:
    match = SHEET_ID_RE.search(name.upper())
    if not match:
        return None
    return f"{match.group(1).upper()}-{match.group(2)}"


def _sheet_kind(name: str) -> str:
    lower = name.lower()
    for kind, keywords in KIND_RULES:
        if any(keyword in lower for keyword in keywords):
            return kind
    return "other"


def _sheet_revision(name: str) -> str | None:
    match = REV_RE.search(name)
    return match.group(1).upper() if match else None


def _index_sheets(root: Path) -> dict[str, Any]:
    if not root.exists() or not root.is_dir():
        raise OpenSUError(f"Drawing root is not a directory: {root}")
    sheets = []
    for path in sorted(root.rglob("*"), key=lambda item: str(item).lower()):
        if not path.is_file() or path.suffix.lower() not in DRAWING_EXTENSIONS:
            continue
        relative = path.relative_to(root).as_posix()
        sheets.append(
            {
                "sheet_id": _sheet_id(path.stem),
                "kind": _sheet_kind(path.stem),
                "title": path.stem,
                "source": relative,
                "revision": _sheet_revision(path.stem),
                "needs_manual_sheet_id": _sheet_id(path.stem) is None,
            }
        )
    duplicates: dict[str, list[str]] = {}
    for sheet in sheets:
        if not sheet["sheet_id"]:
            continue
        duplicates.setdefault(sheet["sheet_id"], []).append(sheet["source"])
    duplicate_ids = {key: value for key, value in duplicates.items() if len(value) > 1}
    return {
        "schema_version": 1,
        "root": str(root),
        "sheet_count": len(sheets),
        "sheets": sheets,
        "duplicate_sheet_ids": duplicate_ids,
        "unidentified_count": sum(1 for sheet in sheets if not sheet["sheet_id"]),
        "ready_for_review": len(sheets) > 0 and not duplicate_ids,
    }


def _finite(value: Any) -> bool:
    return isinstance(value, (int, float)) and not isinstance(value, bool) and math.isfinite(float(value))


def _area(points: list[list[float]]) -> float:
    total = 0.0
    for index, (x1, y1) in enumerate(points):
        x2, y2 = points[(index + 1) % len(points)]
        total += x1 * y2 - x2 * y1
    return total / 2.0


def _orientation(a: list[float], b: list[float], c: list[float]) -> float:
    return (b[0] - a[0]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[0] - a[0])


def _intersect(a: list[float], b: list[float], c: list[float], d: list[float]) -> bool:
    o1, o2 = _orientation(a, b, c), _orientation(a, b, d)
    o3, o4 = _orientation(c, d, a), _orientation(c, d, b)
    return o1 * o2 < 0 and o3 * o4 < 0


def _self_intersects(points: list[list[float]]) -> bool:
    count = len(points)
    for i in range(count):
        a, b = points[i], points[(i + 1) % count]
        for j in range(i + 1, count):
            if abs(i - j) == 1 or (i == 0 and j == count - 1):
                continue
            c, d = points[j], points[(j + 1) % count]
            if _intersect(a, b, c, d):
                return True
    return False


def _lint(spec: dict[str, Any]) -> dict[str, Any]:
    errors: list[str] = []
    warnings: list[str] = []
    if spec.get("schema_version") != SCHEMA_VERSION:
        errors.append(f"schema_version must be {SCHEMA_VERSION}.")

    grids = spec.get("grids", [])
    spaces = spec.get("spaces", [])
    if not isinstance(grids, list):
        errors.append("grids must be an array.")
        grids = []
    if not isinstance(spaces, list):
        errors.append("spaces must be an array.")
        spaces = []

    grid_names: set[str] = set()
    coordinates: set[tuple[str, float]] = set()
    for index, grid in enumerate(grids):
        if not isinstance(grid, dict):
            errors.append(f"grids[{index}] must be an object.")
            continue
        name = str(grid.get("name", "")).strip()
        axis = str(grid.get("axis", "")).lower()
        coordinate = grid.get("coordinate_mm")
        if not name:
            errors.append(f"grids[{index}] needs a name.")
        elif name.lower() in grid_names:
            errors.append(f"Duplicate grid name: {name}.")
        grid_names.add(name.lower())
        if axis not in {"x", "y"}:
            errors.append(f"Grid {name or index}: axis must be x or y.")
        if not _finite(coordinate):
            errors.append(f"Grid {name or index}: coordinate_mm must be finite.")
        elif axis in {"x", "y"}:
            key = (axis, round(float(coordinate), 3))
            if key in coordinates:
                errors.append(f"Duplicate {axis.upper()} grid coordinate: {coordinate} mm.")
            coordinates.add(key)

    space_names: set[str] = set()
    for index, space in enumerate(spaces):
        if not isinstance(space, dict):
            errors.append(f"spaces[{index}] must be an object.")
            continue
        name = str(space.get("name", "")).strip()
        level = str(space.get("level_name", "")).strip()
        boundary = space.get("boundary_mm")
        if not name:
            errors.append(f"spaces[{index}] needs a name.")
        elif name.lower() in space_names:
            errors.append(f"Duplicate space name: {name}.")
        space_names.add(name.lower())
        if not level:
            errors.append(f"Space {name or index}: level_name is required.")
        if not isinstance(boundary, list) or len(boundary) < 3 or not all(
            isinstance(point, list) and len(point) == 2 and all(_finite(value) for value in point)
            for point in (boundary or [])
        ):
            errors.append(f"Space {name or index}: boundary_mm needs at least three [x,y] points.")
            continue
        points = [[float(value) for value in point] for point in boundary]
        if abs(_area(points)) < 1.0:
            errors.append(f"Space {name or index}: boundary has zero area.")
        if _self_intersects(points):
            errors.append(f"Space {name or index}: boundary self-intersects.")
        program = str(space.get("program_type", "other")).strip() or "other"
        if program not in PROGRAM_TYPES:
            warnings.append(f"Space {name or index}: non-standard program_type {program!r}.")

    return {
        "valid": not errors,
        "errors": errors,
        "warnings": warnings,
        "counts": {"grids": len(grids), "spaces": len(spaces)},
    }


def _apply(spec: dict[str, Any]) -> dict[str, Any]:
    lint = _lint(spec)
    if not lint["valid"]:
        raise OpenSUError("Semantic spec failed lint: " + " | ".join(lint["errors"]))
    current = _inspect(1000)
    if not isinstance(current, dict):
        raise OpenSUError("inspect_model returned an unexpected response.")
    level_names = {str(level.get("name")) for level in current.get("levels", []) if isinstance(level, dict)}
    existing_grids = {str(grid.get("name", "")).lower() for grid in current.get("grids", []) if isinstance(grid, dict)}
    existing_spaces = {str(space.get("name", "")).lower() for space in current.get("spaces", []) if isinstance(space, dict)}

    results = []
    for grid in spec.get("grids", []):
        if str(grid["name"]).lower() in existing_grids:
            raise OpenSUError(f"Grid {grid['name']!r} already exists in SketchUp.")
        args = {"name": grid["name"], "axis": grid["axis"], "coordinate_mm": grid["coordinate_mm"]}
        if grid.get("source_ref"):
            args["source_ref"] = grid["source_ref"]
        results.append(_send("define_grid", args))

    for space in spec.get("spaces", []):
        if space["level_name"] not in level_names:
            raise OpenSUError(f"Space {space['name']!r} references undefined SketchUp level {space['level_name']!r}.")
        if str(space["name"]).lower() in existing_spaces:
            raise OpenSUError(f"Space {space['name']!r} already exists in SketchUp.")
        args = {
            "name": space["name"],
            "level_name": space["level_name"],
            "boundary_mm": space["boundary_mm"],
            "program_type": space.get("program_type", "other"),
        }
        for key in ("department", "zone", "source_ref"):
            if space.get(key):
                args[key] = space[key]
        results.append(_send("define_space", args))

    return {
        "applied": len(results),
        "inspect": _inspect(1000),
        "validation": _send("validate_model", {"max_entities": 1000}),
    }


def _template() -> dict[str, Any]:
    return {
        "schema_version": 1,
        "grids": [
            {"name": "1", "axis": "x", "coordinate_mm": 0, "source_ref": "A-101 grid 1"},
            {"name": "2", "axis": "x", "coordinate_mm": 6000, "source_ref": "A-101 grid 2"},
            {"name": "A", "axis": "y", "coordinate_mm": 0, "source_ref": "A-101 grid A"},
            {"name": "B", "axis": "y", "coordinate_mm": 7200, "source_ref": "A-101 grid B"},
        ],
        "spaces": [
            {
                "name": "Showroom_01",
                "level_name": "Level_01",
                "boundary_mm": [[0, 0], [12000, 0], [12000, 9000], [0, 9000]],
                "program_type": "showroom",
                "department": "sales",
                "zone": "front_of_house",
                "source_ref": "A-101 showroom boundary",
            }
        ],
    }


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Index drawing sheets and persist OpenSU grid/space semantics.")
    sub = parser.add_subparsers(dest="command", required=True)
    p = sub.add_parser("index-sheets", help="Build a deterministic file-name based drawing sheet inventory.")
    p.add_argument("root", type=Path)
    p.add_argument("--output", type=Path)
    sub.add_parser("template", help="Print a semantic grid/space spec template.")
    p = sub.add_parser("lint", help="Validate a grid/space semantic spec without changing SketchUp.")
    p.add_argument("path", type=Path)
    p = sub.add_parser("apply", help="Persist lint-clean grid/space semantics into the current SketchUp model.")
    p.add_argument("path", type=Path)
    return parser


def main() -> int:
    args = build_parser().parse_args()
    try:
        if args.command == "index-sheets":
            result = _index_sheets(args.root)
            if args.output:
                args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
            _print(result)
            return 0 if result["sheet_count"] else 3
        if args.command == "template":
            _print(_template())
            return 0
        spec = _load(args.path)
        if args.command == "lint":
            result = _lint(spec)
            _print({"ok": result["valid"], "result": result})
            return 0 if result["valid"] else 3
        result = _apply(spec)
        _print({"ok": True, "result": result})
        return 0
    except OpenSUError as exc:
        _print({"ok": False, "error": str(exc)})
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
