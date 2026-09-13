#!/usr/bin/env python3
"""Query, diagnose, batch-repair, and confirmed-delete commands for the OpenSU Codex Skill."""

from __future__ import annotations

import argparse
from typing import Any

from opensu import OpenSUError, _print, _send


def _ids(parser: argparse.ArgumentParser) -> None:
    parser.add_argument("--id", dest="entity_ids", action="append", type=int, required=True, help="Root entity id; repeat for a batch.")


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Diagnose and repair existing OpenSU model content.")
    sub = parser.add_subparsers(dest="command", required=True)

    p = sub.add_parser("find", help="Find root groups/components using safe filters.")
    p.add_argument("--name-contains")
    p.add_argument("--type", dest="opensu_type")
    p.add_argument("--tag")
    visible = p.add_mutually_exclusive_group()
    visible.add_argument("--visible", action="store_true")
    visible.add_argument("--hidden", action="store_true")
    p.add_argument("--limit", type=int, default=200)

    p = sub.add_parser("diagnose", help="Run model validation and map issues back to named entities when possible.")
    p.add_argument("--max-entities", type=int, default=1000)

    p = sub.add_parser("batch-tag", help="Assign one SketchUp Tag to multiple root entities in one undoable operation.")
    _ids(p)
    p.add_argument("--tag", required=True)

    p = sub.add_parser("batch-visible", help="Show or hide multiple root entities in one undoable operation.")
    _ids(p)
    visibility = p.add_mutually_exclusive_group(required=True)
    visibility.add_argument("--show", action="store_true")
    visibility.add_argument("--hide", action="store_true")

    p = sub.add_parser("batch-transform", help="Move/rotate multiple OpenSU Groups, synchronizing semantic coordinates.")
    _ids(p)
    p.add_argument("--translation", nargs=3, type=float, metavar=("DX", "DY", "DZ"), default=[0.0, 0.0, 0.0])
    p.add_argument("--rotate-z", type=float, default=0.0)

    p = sub.add_parser("delete-confirmed", help="Delete one OpenSU root entity only after id, exact name, and confirmation all match.")
    p.add_argument("--entity-id", type=int, required=True)
    p.add_argument("--confirm-name", required=True)
    p.add_argument("--confirm-delete", action="store_true", required=True)

    return parser


def main() -> int:
    args = build_parser().parse_args()
    try:
        if args.command == "find":
            payload: dict[str, Any] = {"limit": args.limit}
            if args.name_contains:
                payload["name_contains"] = args.name_contains
            if args.opensu_type:
                payload["opensu_type"] = args.opensu_type
            if args.tag:
                payload["tag_name"] = args.tag
            if args.visible:
                payload["visible"] = True
            elif args.hidden:
                payload["visible"] = False
            result = _send("find_entities", payload)
        elif args.command == "diagnose":
            result = _send("diagnose_model", {"max_entities": args.max_entities})
        elif args.command == "batch-tag":
            result = _send("batch_set_tag", {"entity_ids": args.entity_ids, "tag_name": args.tag})
        elif args.command == "batch-visible":
            result = _send("batch_set_visibility", {"entity_ids": args.entity_ids, "visible": bool(args.show)})
        elif args.command == "batch-transform":
            result = _send(
                "batch_transform_entities",
                {
                    "entity_ids": args.entity_ids,
                    "translation_mm": args.translation,
                    "rotation_z_deg": args.rotate_z,
                },
            )
        elif args.command == "delete-confirmed":
            if not args.confirm_delete:
                raise OpenSUError("Deletion requires --confirm-delete.")
            result = _send(
                "delete_entity_confirmed",
                {
                    "entity_id": args.entity_id,
                    "confirm_name": args.confirm_name,
                    "confirm_delete": True,
                },
            )
        else:
            raise OpenSUError(f"Unsupported repair command: {args.command}")
    except OpenSUError as exc:
        _print({"ok": False, "error": str(exc)})
        return 2

    _print({"ok": True, "result": result})
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
