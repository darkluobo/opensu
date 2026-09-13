#!/usr/bin/env python3
"""Advanced OpenSU commands for the sketchup-modeling Codex Skill."""

from __future__ import annotations

import argparse
from typing import Any

from opensu import OpenSUError, _find_entity_id, _print, _send


def _add_turn_stair_args(parser: argparse.ArgumentParser, u_stair: bool = False) -> None:
    parser.add_argument("--origin", nargs=3, type=float, metavar=("X", "Y", "Z"), required=True)
    parser.add_argument("--direction", choices=["x+", "x-", "y+", "y-"], default="x+")
    parser.add_argument("--turn", choices=["left", "right"], default="left")
    parser.add_argument("--width", type=float, default=1200.0)
    parser.add_argument("--run1", type=float, required=True)
    parser.add_argument("--run2", type=float, required=True)
    parser.add_argument("--end-elevation", type=float, required=True)
    parser.add_argument("--target-riser-height", type=float, default=165.0)
    parser.add_argument("--riser-count", type=int)
    parser.add_argument("--landing-thickness", type=float, default=150.0)
    parser.add_argument("--level-name")
    parser.add_argument("--name")
    if u_stair:
        parser.add_argument("--gap", type=float, default=200.0)
        parser.add_argument("--landing-depth", type=float)
    else:
        parser.add_argument("--landing-length", type=float)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Advanced OpenSU building commands.")
    sub = parser.add_subparsers(dest="command", required=True)

    p = sub.add_parser("create-l-stair", help="Create a two-flight 90-degree stair with one landing.")
    _add_turn_stair_args(p, u_stair=False)

    p = sub.add_parser("create-u-stair", help="Create a two-flight 180-degree return stair with one landing.")
    _add_turn_stair_args(p, u_stair=True)

    p = sub.add_parser("create-slab-opening", help="Create a rectangular opening in a rectangular floor, ceiling, or flat roof slab.")
    target = p.add_mutually_exclusive_group(required=True)
    target.add_argument("--entity-id", type=int)
    target.add_argument("--target-name")
    p.add_argument("--offset-x", type=float, required=True)
    p.add_argument("--offset-y", type=float, required=True)
    p.add_argument("--width", type=float, required=True)
    p.add_argument("--depth", type=float, required=True)
    p.add_argument("--type", dest="opening_type", default="void")
    p.add_argument("--opening-name")

    for command, help_text in (
        ("create-polygon-slab", "Create a simple horizontal polygon floor/slab."),
        ("create-polygon-ceiling", "Create a simple horizontal polygon ceiling slab."),
    ):
        p = sub.add_parser(command, help=help_text)
        p.add_argument(
            "--point",
            nargs=3,
            type=float,
            action="append",
            metavar=("X", "Y", "Z"),
            required=True,
            help="Polygon vertex in mm; repeat at least three times in boundary order.",
        )
        p.add_argument("--thickness", type=float, default=100.0 if command.endswith("ceiling") else 150.0)
        p.add_argument("--level-name")
        p.add_argument("--name")

    return parser


def _turn_stair_payload(args: argparse.Namespace) -> dict[str, Any]:
    payload: dict[str, Any] = {
        "origin_mm": args.origin,
        "direction": args.direction,
        "turn": args.turn,
        "width_mm": args.width,
        "run1_mm": args.run1,
        "run2_mm": args.run2,
        "end_elevation_mm": args.end_elevation,
        "target_riser_height_mm": args.target_riser_height,
        "landing_thickness_mm": args.landing_thickness,
        "level_name": args.level_name,
        "name": args.name,
    }
    if args.riser_count is not None:
        payload["riser_count"] = args.riser_count
    return payload


def main() -> int:
    args = build_parser().parse_args()
    try:
        if args.command == "create-l-stair":
            payload = _turn_stair_payload(args)
            if args.landing_length is not None:
                payload["landing_length_mm"] = args.landing_length
            result = _send("create_l_stair", payload)
        elif args.command == "create-u-stair":
            payload = _turn_stair_payload(args)
            payload["gap_mm"] = args.gap
            if args.landing_depth is not None:
                payload["landing_depth_mm"] = args.landing_depth
            result = _send("create_u_stair", payload)
        elif args.command == "create-slab-opening":
            entity_id = args.entity_id if args.entity_id is not None else _find_entity_id(args.target_name)
            result = _send(
                "create_slab_opening",
                {
                    "entity_id": entity_id,
                    "offset_x_mm": args.offset_x,
                    "offset_y_mm": args.offset_y,
                    "width_mm": args.width,
                    "depth_mm": args.depth,
                    "opening_type": args.opening_type,
                    "name": args.opening_name,
                },
            )
        elif args.command in {"create-polygon-slab", "create-polygon-ceiling"}:
            tool = "create_polygon_slab" if args.command == "create-polygon-slab" else "create_polygon_ceiling"
            result = _send(
                tool,
                {
                    "points_mm": args.point,
                    "thickness_mm": args.thickness,
                    "level_name": args.level_name,
                    "name": args.name,
                },
            )
        else:
            raise OpenSUError(f"Unsupported command: {args.command}")
    except OpenSUError as exc:
        _print({"ok": False, "error": str(exc)})
        return 2

    _print({"ok": True, "result": result})
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
