#!/usr/bin/env python3
"""OpenSU logical and hierarchical grouping commands for the $opensu Codex Skill."""

from __future__ import annotations

import argparse
from typing import Any

from opensu import OpenSUError, _find_entity_id, _print, _send


def _member_args(parser: argparse.ArgumentParser) -> None:
    parser.add_argument("--id", dest="entity_ids", action="append", type=int, default=[])
    parser.add_argument("--name", dest="entity_names", action="append", default=[])


def _member_ids(args: argparse.Namespace, *, required: bool = True) -> list[int]:
    ids = list(args.entity_ids or [])
    for name in args.entity_names or []:
        ids.append(_find_entity_id(name))
    if required and not ids:
        raise OpenSUError("Provide at least one --id or --name member.")
    if len(ids) != len(set(ids)):
        raise OpenSUError("Duplicate entity member detected.")
    return ids


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Create and operate persistent OpenSU logical entity-group trees."
    )
    sub = parser.add_subparsers(dest="command", required=True)

    sub.add_parser("list", help="List logical entity groups.")
    sub.add_parser("roots", help="List root groups in the parent-child hierarchy.")

    p = sub.add_parser("inspect", help="Inspect one logical entity group and its direct members.")
    p.add_argument("--group", required=True)

    p = sub.add_parser("tree", help="Recursively inspect a group subtree.")
    p.add_argument("--group", required=True)
    p.add_argument("--max-depth", type=int, default=32)

    p = sub.add_parser(
        "create",
        help="Create a group from entity members, child groups, or both.",
    )
    p.add_argument("--group", required=True)
    _member_args(p)
    p.add_argument("--child-group", dest="child_groups", action="append", default=[])
    p.add_argument("--description")
    p.add_argument("--source-ref")

    p = sub.add_parser("add", help="Add existing OpenSU entities to a logical group.")
    p.add_argument("--group", required=True)
    _member_args(p)

    p = sub.add_parser("remove", help="Remove entity members without deleting geometry.")
    p.add_argument("--group", required=True)
    _member_args(p)

    p = sub.add_parser("nest", help="Attach one existing group as a child of another.")
    p.add_argument("--parent", required=True)
    p.add_argument("--child", required=True)

    p = sub.add_parser("unnest", help="Detach a child group so it becomes a hierarchy root.")
    p.add_argument("--parent", required=True)
    p.add_argument("--child", required=True)

    p = sub.add_parser("move", help="Reparent a group or move it to hierarchy root.")
    p.add_argument("--group", required=True)
    destination = p.add_mutually_exclusive_group(required=True)
    destination.add_argument("--parent")
    destination.add_argument("--to-root", action="store_true")

    p = sub.add_parser("prune-missing", help="Remove stale references to entity members that no longer exist.")
    p.add_argument("--group", required=True)

    p = sub.add_parser("rename", help="Rename a logical group; hierarchy links remain stable.")
    p.add_argument("--group", required=True)
    p.add_argument("--new-name", required=True)

    p = sub.add_parser(
        "dissolve",
        help="Delete only this grouping node; children are promoted and geometry remains.",
    )
    p.add_argument("--group", required=True)

    p = sub.add_parser(
        "visible",
        help="Show or hide every entity in this group and all descendants.",
    )
    p.add_argument("--group", required=True)
    visibility = p.add_mutually_exclusive_group(required=True)
    visibility.add_argument("--show", action="store_true")
    visibility.add_argument("--hide", action="store_true")

    p = sub.add_parser(
        "tag",
        help="Assign one SketchUp Tag recursively to this group subtree.",
    )
    p.add_argument("--group", required=True)
    p.add_argument("--tag", required=True)

    p = sub.add_parser(
        "transform",
        help="Move/rotate a complete group subtree around one shared pivot.",
    )
    p.add_argument("--group", required=True)
    p.add_argument(
        "--translation",
        nargs=3,
        type=float,
        metavar=("DX", "DY", "DZ"),
        default=[0.0, 0.0, 0.0],
    )
    p.add_argument("--rotate-z", type=float, default=0.0)
    p.add_argument("--pivot", nargs=3, type=float, metavar=("X", "Y", "Z"))

    p = sub.add_parser(
        "duplicate",
        help="Duplicate an entire group subtree, preserving parent-child relationships.",
    )
    p.add_argument("--group", required=True)
    p.add_argument("--new-group")
    p.add_argument(
        "--translation",
        nargs=3,
        type=float,
        metavar=("DX", "DY", "DZ"),
        default=[0.0, 0.0, 0.0],
    )
    p.add_argument("--rotate-z", type=float, default=0.0)
    p.add_argument("--pivot", nargs=3, type=float, metavar=("X", "Y", "Z"))
    p.add_argument("--description")
    p.add_argument("--source-ref")

    return parser


def main() -> int:
    args = build_parser().parse_args()
    try:
        if args.command == "list":
            result = _send("list_entity_groups", {})
        elif args.command == "roots":
            result = _send("list_entity_group_roots", {})
        elif args.command == "inspect":
            result = _send("inspect_entity_group", {"group_name": args.group})
        elif args.command == "tree":
            result = _send(
                "inspect_entity_group_tree",
                {"group_name": args.group, "max_depth": args.max_depth},
            )
        elif args.command == "create":
            entity_ids = _member_ids(args, required=False)
            child_groups = list(args.child_groups or [])
            if not entity_ids and not child_groups:
                raise OpenSUError(
                    "Create needs at least one entity member or --child-group."
                )
            payload: dict[str, Any] = {
                "name": args.group,
                "entity_ids": entity_ids,
                "child_group_names": child_groups,
            }
            if args.description:
                payload["description"] = args.description
            if args.source_ref:
                payload["source_ref"] = args.source_ref
            result = _send("create_entity_group", payload)
        elif args.command == "add":
            result = _send(
                "add_entities_to_group",
                {"group_name": args.group, "entity_ids": _member_ids(args)},
            )
        elif args.command == "remove":
            result = _send(
                "remove_entities_from_group",
                {"group_name": args.group, "entity_ids": _member_ids(args)},
            )
        elif args.command == "nest":
            result = _send(
                "add_child_entity_group",
                {
                    "parent_group_name": args.parent,
                    "child_group_name": args.child,
                },
            )
        elif args.command == "unnest":
            result = _send(
                "remove_child_entity_group",
                {
                    "parent_group_name": args.parent,
                    "child_group_name": args.child,
                },
            )
        elif args.command == "move":
            payload = {"group_name": args.group}
            if args.to_root:
                payload["to_root"] = True
            else:
                payload["new_parent_group_name"] = args.parent
            result = _send("move_entity_group", payload)
        elif args.command == "prune-missing":
            result = _send(
                "prune_missing_entity_group_members",
                {"group_name": args.group},
            )
        elif args.command == "rename":
            result = _send(
                "rename_entity_group",
                {"group_name": args.group, "new_name": args.new_name},
            )
        elif args.command == "dissolve":
            result = _send("delete_entity_group", {"group_name": args.group})
        elif args.command == "visible":
            result = _send(
                "set_entity_group_visibility",
                {"group_name": args.group, "visible": bool(args.show)},
            )
        elif args.command == "tag":
            result = _send(
                "set_entity_group_tag",
                {"group_name": args.group, "tag_name": args.tag},
            )
        elif args.command == "transform":
            payload = {
                "group_name": args.group,
                "translation_mm": args.translation,
                "rotation_z_deg": args.rotate_z,
            }
            if args.pivot is not None:
                payload["pivot_mm"] = args.pivot
            result = _send("transform_entity_group", payload)
        elif args.command == "duplicate":
            payload = {
                "group_name": args.group,
                "new_group_name": args.new_group,
                "translation_mm": args.translation,
                "rotation_z_deg": args.rotate_z,
            }
            if args.pivot is not None:
                payload["pivot_mm"] = args.pivot
            if args.description:
                payload["description"] = args.description
            if args.source_ref:
                payload["source_ref"] = args.source_ref
            result = _send("duplicate_entity_group", payload)
        else:
            raise OpenSUError(f"Unsupported group command: {args.command}")
    except OpenSUError as exc:
        _print({"ok": False, "error": str(exc)})
        return 2

    _print({"ok": True, "result": result})
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
