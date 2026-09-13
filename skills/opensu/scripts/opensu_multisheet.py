#!/usr/bin/env python3
"""Cross-sheet evidence fusion for drawing-to-SketchUp reconstruction.

Codex should create a Multi-Sheet Pack containing the final Plan Spec plus sheet metadata
and evidence claims. This tool checks source validity, reconciles claims by evidence
strength, detects blocking conflicts, and verifies that resolved dimensions match the
Plan Spec before execution.
"""

from __future__ import annotations

import argparse
import json
import math
import re
from pathlib import Path
from statistics import median
from typing import Any

from opensu import OpenSUError, _print

SCHEMA_VERSION = 1
SHEET_KINDS = {"plan", "elevation", "section", "detail", "schedule", "other"}
BASIS_RANK = {
    "printed_dimension": 0,
    "grid_or_dimension_chain": 1,
    "explicit_detail": 2,
    "derived_from_exact": 3,
    "calibrated_scale": 4,
    "pixel_estimate": 5,
}
CONFIDENCE = {"high", "medium", "low"}
TARGET_RE = re.compile(r"^(levels|floors|columns|beams|walls|openings|curtain_walls|ceilings|stairs|roofs|slab_openings)\.([^.]+)\.([A-Za-z0-9_]+)(?:\[(\d+)\])?$")


def _load(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except OSError as exc:
        raise OpenSUError(f"Cannot read Multi-Sheet Pack: {path}") from exc
    except json.JSONDecodeError as exc:
        raise OpenSUError(f"Invalid JSON at line {exc.lineno}, column {exc.colno}: {exc.msg}") from exc
    if not isinstance(value, dict):
        raise OpenSUError("Multi-Sheet Pack root must be a JSON object.")
    return value


def _is_num(value: Any) -> bool:
    return isinstance(value, (int, float)) and not isinstance(value, bool) and math.isfinite(float(value))


def _numeric_value(value: Any) -> float | list[float] | None:
    if _is_num(value):
        return float(value)
    if isinstance(value, list) and value and all(_is_num(item) for item in value):
        return [float(item) for item in value]
    return None


def _distance(a: float | list[float], b: float | list[float]) -> float:
    if isinstance(a, list) != isinstance(b, list):
        return math.inf
    if isinstance(a, list):
        if len(a) != len(b):
            return math.inf
        return max(abs(x - y) for x, y in zip(a, b)) if a else 0.0
    return abs(a - b)


def _average(values: list[float | list[float]]) -> float | list[float]:
    first = values[0]
    if isinstance(first, list):
        width = len(first)
        return [median([value[i] for value in values if isinstance(value, list)]) for i in range(width)]
    return float(median([value for value in values if not isinstance(value, list)]))


def _index_by_name(plan: dict[str, Any], section: str) -> dict[str, dict[str, Any]]:
    value = plan.get(section, [])
    if not isinstance(value, list):
        return {}
    result: dict[str, dict[str, Any]] = {}
    for item in value:
        if isinstance(item, dict) and isinstance(item.get("name"), str) and item["name"].strip():
            result[item["name"]] = item
    return result


def _resolve_target(plan: dict[str, Any], target: str) -> tuple[bool, Any]:
    match = TARGET_RE.match(target)
    if not match:
        return False, None
    section, name, field, index_text = match.groups()
    item = _index_by_name(plan, section).get(name)
    if item is None or field not in item:
        return False, None
    value = item[field]
    if index_text is not None:
        if not isinstance(value, list):
            return False, None
        index = int(index_text)
        if index >= len(value):
            return False, None
        value = value[index]
    return True, value


def _preferred_sheet_warning(sheet_kind: str, axis_role: str | None) -> str | None:
    if axis_role == "xy" and sheet_kind not in {"plan", "detail", "schedule"}:
        return f"XY claim comes from {sheet_kind}; plan/detail evidence is normally preferred."
    if axis_role == "z" and sheet_kind not in {"elevation", "section", "detail", "schedule"}:
        return f"Z claim comes from {sheet_kind}; elevation/section/detail evidence is normally preferred."
    return None


def _lint(pack: dict[str, Any]) -> dict[str, Any]:
    errors: list[str] = []
    warnings: list[str] = []
    conflicts: list[dict[str, Any]] = []
    resolved: list[dict[str, Any]] = []

    if pack.get("schema_version") != SCHEMA_VERSION:
        errors.append(f"schema_version must be {SCHEMA_VERSION}.")

    plan = pack.get("plan_spec")
    if not isinstance(plan, dict):
        errors.append("plan_spec must be an object.")
        plan = {}

    sheets = pack.get("sheets")
    if not isinstance(sheets, list) or not sheets:
        errors.append("sheets must be a non-empty array.")
        sheets = []

    sheet_map: dict[str, dict[str, Any]] = {}
    for index, sheet in enumerate(sheets):
        if not isinstance(sheet, dict):
            errors.append(f"sheets[{index}] must be an object.")
            continue
        sheet_id = sheet.get("sheet_id")
        if not isinstance(sheet_id, str) or not sheet_id.strip():
            errors.append(f"sheets[{index}] needs sheet_id.")
            continue
        if sheet_id in sheet_map:
            errors.append(f"Duplicate sheet_id: {sheet_id}.")
            continue
        kind = sheet.get("kind")
        if kind not in SHEET_KINDS:
            errors.append(f"Sheet {sheet_id}: kind must be one of {sorted(SHEET_KINDS)}.")
        sheet_map[sheet_id] = sheet

    claims = pack.get("claims")
    if not isinstance(claims, list) or not claims:
        errors.append("claims must be a non-empty array.")
        claims = []

    grouped: dict[str, list[dict[str, Any]]] = {}
    claim_ids: set[str] = set()
    for index, claim in enumerate(claims):
        if not isinstance(claim, dict):
            errors.append(f"claims[{index}] must be an object.")
            continue
        claim_id = claim.get("claim_id")
        if not isinstance(claim_id, str) or not claim_id.strip():
            errors.append(f"claims[{index}] needs claim_id.")
            continue
        if claim_id in claim_ids:
            errors.append(f"Duplicate claim_id: {claim_id}.")
        claim_ids.add(claim_id)
        target = claim.get("target")
        if not isinstance(target, str) or not TARGET_RE.match(target):
            errors.append(f"Claim {claim_id}: invalid target path {target!r}.")
            continue
        source_sheet = claim.get("sheet_id")
        if source_sheet not in sheet_map:
            errors.append(f"Claim {claim_id}: unknown sheet_id {source_sheet!r}.")
            continue
        basis = claim.get("basis")
        if basis not in BASIS_RANK:
            errors.append(f"Claim {claim_id}: invalid basis {basis!r}.")
            continue
        confidence = claim.get("confidence")
        if confidence not in CONFIDENCE:
            errors.append(f"Claim {claim_id}: confidence must be high/medium/low.")
        numeric = _numeric_value(claim.get("value"))
        if numeric is None:
            errors.append(f"Claim {claim_id}: value must be a finite number or numeric array.")
            continue
        tolerance = claim.get("tolerance_mm", pack.get("default_tolerance_mm", 5.0))
        if not _is_num(tolerance) or float(tolerance) < 0:
            errors.append(f"Claim {claim_id}: tolerance_mm must be >= 0.")
            continue
        warning = _preferred_sheet_warning(sheet_map[source_sheet].get("kind"), claim.get("axis_role"))
        if warning:
            warnings.append(f"Claim {claim_id}: {warning}")
        grouped.setdefault(target, []).append(claim)

    for target, target_claims in grouped.items():
        strongest_rank = min(BASIS_RANK[claim["basis"]] for claim in target_claims)
        strongest = [claim for claim in target_claims if BASIS_RANK[claim["basis"]] == strongest_rank]
        tolerance = max(float(claim.get("tolerance_mm", pack.get("default_tolerance_mm", 5.0))) for claim in strongest)
        strongest_values = [_numeric_value(claim["value"]) for claim in strongest]
        assert all(value is not None for value in strongest_values)
        strongest_values = [value for value in strongest_values if value is not None]
        anchor = strongest_values[0]
        disagreement = [value for value in strongest_values[1:] if _distance(anchor, value) > tolerance]
        if disagreement:
            conflict = {
                "target": target,
                "blocking": True,
                "basis": strongest[0]["basis"],
                "claim_ids": [claim["claim_id"] for claim in strongest],
                "values": [claim["value"] for claim in strongest],
                "tolerance_mm": tolerance,
                "message": "Strongest available evidence disagrees beyond tolerance.",
            }
            conflicts.append(conflict)
            continue

        resolved_value = _average(strongest_values)
        found, plan_value_raw = _resolve_target(plan, target)
        if not found:
            errors.append(f"Resolved target {target} does not exist in plan_spec.")
            continue
        plan_value = _numeric_value(plan_value_raw)
        if plan_value is None:
            errors.append(f"Plan Spec target {target} is not numeric.")
            continue
        if _distance(resolved_value, plan_value) > tolerance:
            errors.append(
                f"Plan Spec mismatch for {target}: resolved evidence={resolved_value}, plan={plan_value}, tolerance={tolerance} mm."
            )

        lower = [claim for claim in target_claims if BASIS_RANK[claim["basis"]] > strongest_rank]
        lower_disagreements = []
        for claim in lower:
            value = _numeric_value(claim["value"])
            if value is not None and _distance(resolved_value, value) > float(claim.get("tolerance_mm", tolerance)):
                lower_disagreements.append(claim["claim_id"])
        if lower_disagreements:
            warnings.append(
                f"{target}: lower-priority claims disagree with resolved value: {', '.join(lower_disagreements)}."
            )

        resolved.append(
            {
                "target": target,
                "value": resolved_value,
                "basis": strongest[0]["basis"],
                "source_claim_ids": [claim["claim_id"] for claim in strongest],
                "tolerance_mm": tolerance,
                "plan_matches": _distance(resolved_value, plan_value) <= tolerance,
            }
        )

    blocking_uncertainties = []
    uncertainties = pack.get("uncertainties", [])
    if uncertainties is not None and not isinstance(uncertainties, list):
        errors.append("uncertainties must be an array.")
        uncertainties = []
    for index, item in enumerate(uncertainties):
        if not isinstance(item, dict):
            errors.append(f"uncertainties[{index}] must be an object.")
            continue
        if item.get("blocking") is True:
            blocking_uncertainties.append(item)

    return {
        "valid": not errors and not conflicts,
        "errors": errors,
        "warnings": warnings,
        "blocking_conflicts": conflicts,
        "blocking_uncertainties": blocking_uncertainties,
        "resolved_claims": resolved,
        "sheet_count": len(sheet_map),
        "claim_count": len(claim_ids),
    }


def _template() -> dict[str, Any]:
    return {
        "schema_version": 1,
        "default_tolerance_mm": 5,
        "sheets": [
            {"sheet_id": "A-101", "kind": "plan", "title": "Level 01 Plan", "source": "A-101.pdf", "page": 1},
            {"sheet_id": "A-201", "kind": "elevation", "title": "South Elevation", "source": "A-201.pdf", "page": 1},
            {"sheet_id": "A-301", "kind": "section", "title": "Section A-A", "source": "A-301.pdf", "page": 1},
        ],
        "plan_spec": {
            "schema_version": 1,
            "project": {"name": "MultiSheet Example", "units": "mm"},
            "uncertainties": [],
            "levels": [{"name": "Level_01", "elevation_mm": 0, "floor_to_floor_mm": 4500}],
            "floors": [], "columns": [], "beams": [],
            "walls": [{"name": "Wall_South_001", "start_mm": [0, 0, 150], "end_mm": [12000, 0, 150], "height_mm": 4200, "thickness_mm": 200}],
            "openings": [{"name": "Door_South_Opening_001", "wall_name": "Wall_South_001", "opening_type": "door", "offset_mm": 1800, "width_mm": 1200, "height_mm": 2400, "sill_height_mm": 0}],
            "curtain_walls": [], "ceilings": [], "stairs": [], "roofs": [], "slab_openings": [], "materials": [], "tags": []
        },
        "claims": [
            {"claim_id": "C-001", "target": "walls.Wall_South_001.end_mm[0]", "value": 12000, "sheet_id": "A-101", "basis": "printed_dimension", "confidence": "high", "axis_role": "xy"},
            {"claim_id": "C-002", "target": "walls.Wall_South_001.height_mm", "value": 4200, "sheet_id": "A-201", "basis": "printed_dimension", "confidence": "high", "axis_role": "z"},
            {"claim_id": "C-003", "target": "walls.Wall_South_001.height_mm", "value": 4200, "sheet_id": "A-301", "basis": "printed_dimension", "confidence": "high", "axis_role": "z"},
            {"claim_id": "C-004", "target": "openings.Door_South_Opening_001.height_mm", "value": 2400, "sheet_id": "A-201", "basis": "printed_dimension", "confidence": "high", "axis_role": "z"}
        ],
        "uncertainties": []
    }


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Check and reconcile evidence across plans, elevations, sections, and details.")
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("template", help="Print a starter Multi-Sheet Pack JSON document.")
    p = sub.add_parser("check", help="Validate and cross-check a Multi-Sheet Pack.")
    p.add_argument("path", type=Path)
    return parser


def main() -> int:
    args = build_parser().parse_args()
    try:
        if args.command == "template":
            _print(_template())
            return 0
        result = _lint(_load(args.path))
    except OpenSUError as exc:
        _print({"ok": False, "error": str(exc)})
        return 2
    _print({"ok": result["valid"], "result": result})
    return 0 if result["valid"] else 3


if __name__ == "__main__":
    raise SystemExit(main())
