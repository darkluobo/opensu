#!/usr/bin/env python3
"""Non-destructive OpenSU editing commands for the $opensu Codex Skill."""

from __future__ import annotations

import argparse
from typing import Any

from opensu import OpenSUError, _find_entity_id, _print, _send


def _target(parser: argparse.ArgumentParser) -> None:
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--entity-id", type=int)
    group.add_argument("--name")


def _entity_id(args: argparse.Namespace) -> int:
    return args.entity_id if args.entity_id is not None else _find_entity_id(args.name)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Safely edit existing OpenSU root entities.")
    sub = parser.add_subparsers(dest="command", required=True)

    p = sub.add_parser("rename", help="Rename one root group/component.")
    _target(p)
    p.add_argument("--new-name", required=True)

    p = sub.add_parser("set-tag", help="Assign a SketchUp Tag to one root group/component.")
    _target(p)
    p.add_argument("--tag", required=True)

    p = sub.add_parser("set-visible", help="Show or hide one root group/component.")
    _target(p)
    visibility = p.add_mutually_exclusive_group(required=True)
    visibility.add_argument("--show", action="store_true")
    visibility.add_argument("--hide", action="store_true")

    p = sub.add_parser("transform", help="Move and/or rotate one OpenSU Group while synchronizing semantic coordinates.")
    _target(p)
    p.add_argument("--translation", nargs=3, type=float, metavar=("DX", "DY", "DZ"), default=[0.0, 0.0, 0.0])
    p.add_argument("--rotate-z", type=float, default=0.0, help="Z-axis rotation in degrees.")
    p.add_argument("--pivot", nargs=3, type=float, metavar=("X", "Y", "Z"))

    p = sub.add_parser("duplicate", help="Duplicate an OpenSU Group and optionally offset/rotate the copy.")
    _target(p)
    p.add_argument("--new-name")
    p.add_argument("--translation", nargs=3, type=float, metavar=("DX", "DY", "DZ"), default=[0.0, 0.0, 0.0])
    p.add_argument("--rotate-z", type=float, default=0.0)
    p.add_argument("--pivot", nargs=3, type=float, metavar=("X", "Y", "Z"))

    return parser


def main() -> int:
    args = build_parser().parse_args()
    try:
        target_id = _entity_id(args)
        if args.command == "rename":
            result = _send("rename_entity", {"entity_id": target_id, "new_name": args.new_name})
        elif args.command == "set-tag":
            result = _send("set_entity_tag", {"entity_id": target_id, "tag_name": args.tag})
        elif args.command == "set-visible":
            result = _send("set_entity_visibility", {"entity_id": target_id, "visible": bool(args.show)})
        elif args.command == "transform":
            payload: dict[str, Any] = {
                "entity_id": target_id,
                "translation_mm": args.translation,
                "rotation_z_deg": args.rotate_z,
            }
            if args.pivot is not None:
                payload["pivot_mm"] = args.pivot
            result = _send("transform_entity", payload)
        elif args.command == "duplicate":
            payload = {
                "entity_id": target_id,
                "new_name": args.new_name,
                "translation_mm": args.translation,
                "rotation_z_deg": args.rotate_z,
            }
            if args.pivot is not None:
                payload["pivot_mm"] = args.pivot
            result = _send("duplicate_entity", payload)
        else:
            raise OpenSUError(f"Unsupported edit command: {args.command}")
    except OpenSUError as exc:
        _print({"ok": False, "error": str(exc)})
        return 2

    _print({"ok": True, "result": result})
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
