#!/usr/bin/env python3
"""Grid- and space-driven layout bridge for the sketchup-modeling Codex Skill."""

from __future__ import annotations

import argparse
import json
from typing import Any

from opensu import OpenSUError, _inspect, _print, _send


SPACE_STRATEGIES: dict[str, dict[str, Any]] = {
    "showroom": {
        "facade": "curtain_wall_candidate",
        "partitioning": "minimal",
        "structure": "preserve_clear_display_bays",
        "notes": ["Prefer authoritative facade/elevation evidence before creating glazing."],
    },
    "sales": {"partitioning": "light", "structure": "open_plan"},
    "reception": {"partitioning": "light", "structure": "front_of_house"},
    "customer_lounge": {"partitioning": "light", "structure": "front_of_house"},
    "delivery": {"partitioning": "minimal", "structure": "vehicle_clearance_sensitive"},
    "aftersales_reception": {"partitioning": "moderate", "structure": "vehicle_and_customer_interface"},
    "workshop": {
        "partitioning": "minimal",
        "structure": "grid_driven_large_bays",
        "notes": ["Do not invent service-bay spacing; use plan/grid evidence."],
    },
    "parts": {"partitioning": "moderate", "structure": "storage_sensitive"},
    "office": {"partitioning": "moderate", "structure": "room_scale"},
    "support": {"partitioning": "moderate", "structure": "room_scale"},
    "circulation": {"partitioning": "avoid_blocking_route", "structure": "clear_path"},
    "service": {"partitioning": "moderate", "structure": "service_specific"},
    "storage": {"partitioning": "moderate", "structure": "storage_sensitive"},
    "other": {"partitioning": "evidence_driven", "structure": "evidence_driven"},
}


def _intersection(value: str) -> tuple[str, str]:
    text = value.strip()
    for separator in ("/", ",", "×", "x", "X"):
        if separator in text:
            left, right = (part.strip() for part in text.split(separator, 1))
            if left and right:
                return left, right
    raise OpenSUError(f"Grid intersection {value!r} must look like '3/B'.")


def _strategy(space_name: str) -> dict[str, Any]:
    model = _inspect(1000)
    if not isinstance(model, dict):
        raise OpenSUError("inspect_model returned an unexpected response.")
    matches = [space for space in model.get("spaces", []) if isinstance(space, dict) and space.get("name") == space_name]
    if not matches:
        raise OpenSUError(f"No semantic Space named {space_name!r} was found.")
    space = matches[0]
    program = str(space.get("program_type") or "other")
    base = dict(SPACE_STRATEGIES.get(program, SPACE_STRATEGIES["other"]))
    base.update(
        {
            "space_name": space_name,
            "program_type": program,
            "level_name": space.get("level_name"),
            "area_m2": space.get("area_m2"),
            "source_ref": space.get("source_ref"),
            "advisory_only": True,
            "dimension_rule": "Never override authoritative drawing/grid dimensions with program defaults.",
        }
    )
    return base


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Drive OpenSU geometry from persisted grids and functional spaces.")
    sub = parser.add_subparsers(dest="command", required=True)

    p = sub.add_parser("grid-point", help="Resolve an intersection like 3/B to model coordinates.")
    p.add_argument("--at", required=True, dest="intersection")
    p.add_argument("--level")
    p.add_argument("--z-offset", type=float, default=0.0)

    p = sub.add_parser("grid-column", help="Create a column centered on a persisted grid intersection.")
    p.add_argument("--at", required=True, dest="intersection")
    p.add_argument("--level", required=True)
    p.add_argument("--width", type=float, default=400.0)
    p.add_argument("--depth", type=float, default=400.0)
    p.add_argument("--height", type=float)
    p.add_argument("--base-offset", type=float, default=0.0)
    p.add_argument("--name")

    p = sub.add_parser("grid-beam", help="Create a beam between two persisted grid intersections.")
    p.add_argument("--from", required=True, dest="start_intersection")
    p.add_argument("--to", required=True, dest="end_intersection")
    p.add_argument("--level", required=True)
    p.add_argument("--width", type=float, default=300.0)
    p.add_argument("--height", type=float, default=500.0)
    p.add_argument("--bottom-offset", type=float, default=0.0)
    p.add_argument("--name")

    p = sub.add_parser("space-walls", help="Create partition walls on selected edges of a semantic Space.")
    p.add_argument("--space", required=True)
    p.add_argument("--thickness", type=float, default=100.0)
    p.add_argument("--height", type=float)
    p.add_argument("--base-offset", type=float, default=0.0)
    p.add_argument("--edges", nargs="*", type=int, help="Zero-based space edge indices. Omit to use the full perimeter.")
    p.add_argument("--name-prefix")

    p = sub.add_parser("space-strategy", help="Return advisory-only modeling strategy for a semantic Space program type.")
    p.add_argument("--space", required=True)

    return parser


def main() -> int:
    args = build_parser().parse_args()
    try:
        if args.command == "space-strategy":
            _print({"ok": True, "result": _strategy(args.space)})
            return 0

        if args.command in {"grid-point", "grid-column"}:
            x_grid, y_grid = _intersection(args.intersection)
        if args.command == "grid-beam":
            start_x, start_y = _intersection(args.start_intersection)
            end_x, end_y = _intersection(args.end_intersection)

        if args.command == "grid-point":
            payload: dict[str, Any] = {"x_grid": x_grid, "y_grid": y_grid, "z_offset_mm": args.z_offset}
            if args.level:
                payload["level_name"] = args.level
            result = _send("resolve_grid_intersection", payload)
        elif args.command == "grid-column":
            payload = {
                "x_grid": x_grid,
                "y_grid": y_grid,
                "level_name": args.level,
                "width_mm": args.width,
                "depth_mm": args.depth,
                "base_offset_mm": args.base_offset,
            }
            if args.height is not None:
                payload["height_mm"] = args.height
            if args.name:
                payload["name"] = args.name
            result = _send("create_grid_column", payload)
        elif args.command == "grid-beam":
            payload = {
                "start_x_grid": start_x,
                "start_y_grid": start_y,
                "end_x_grid": end_x,
                "end_y_grid": end_y,
                "level_name": args.level,
                "width_mm": args.width,
                "height_mm": args.height,
                "bottom_offset_mm": args.bottom_offset,
            }
            if args.name:
                payload["name"] = args.name
            result = _send("create_grid_beam", payload)
        elif args.command == "space-walls":
            payload = {
                "space_name": args.space,
                "thickness_mm": args.thickness,
                "base_offset_mm": args.base_offset,
            }
            if args.height is not None:
                payload["height_mm"] = args.height
            if args.edges:
                payload["edge_indices"] = args.edges
            if args.name_prefix:
                payload["name_prefix"] = args.name_prefix
            result = _send("create_space_partitions", payload)
        else:
            raise OpenSUError(f"Unsupported command: {args.command}")

        _print({"ok": True, "result": result})
        return 0
    except OpenSUError as exc:
        _print({"ok": False, "error": str(exc)})
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
