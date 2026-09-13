#!/usr/bin/env python3
"""Standalone OpenSU bridge for Codex skills.

Uses only the Python standard library. It talks directly to the local SketchUp
extension JSON-RPC socket on 127.0.0.1:9876, so users only need the SketchUp
extension plus this Codex skill.
"""

from __future__ import annotations

import argparse
import json
import os
import socket
from typing import Any

HOST = os.environ.get("OPENSU_HOST", "127.0.0.1")
PORT = int(os.environ.get("OPENSU_PORT", "9876"))
TIMEOUT = float(os.environ.get("OPENSU_TIMEOUT", "30"))


class OpenSUError(RuntimeError):
    pass


def _send(command: str, arguments: dict[str, Any]) -> Any:
    request = {
        "jsonrpc": "2.0",
        "id": 1,
        "method": "tools/call",
        "params": {"name": command, "arguments": arguments},
    }
    payload = (json.dumps(request, ensure_ascii=False) + "\n").encode("utf-8")

    try:
        with socket.create_connection((HOST, PORT), timeout=TIMEOUT) as sock:
            sock.sendall(payload)
            stream = sock.makefile("rb")
            line = stream.readline()
    except OSError as exc:
        raise OpenSUError(
            f"Cannot connect to SketchUp at {HOST}:{PORT}. Open SketchUp, then use "
            "Extensions > MCP Server > Start Server."
        ) from exc

    if not line:
        raise OpenSUError("SketchUp closed the connection without returning a response.")

    try:
        response = json.loads(line.decode("utf-8"))
    except json.JSONDecodeError as exc:
        raise OpenSUError(f"Invalid JSON response from SketchUp: {line!r}") from exc

    if "error" in response:
        message = response.get("error", {}).get("message", "Unknown SketchUp error")
        raise OpenSUError(message)

    result = response.get("result", {})
    content = result.get("content") if isinstance(result, dict) else None
    if isinstance(content, list) and content:
        text = content[0].get("text") if isinstance(content[0], dict) else None
        if isinstance(text, str):
            try:
                return json.loads(text)
            except json.JSONDecodeError:
                return text
    return result


def _status() -> dict[str, Any]:
    try:
        with socket.create_connection((HOST, PORT), timeout=TIMEOUT):
            pass
    except OSError as exc:
        raise OpenSUError(
            f"Cannot connect to SketchUp at {HOST}:{PORT}. Open SketchUp, then use "
            "Extensions > MCP Server > Start Server."
        ) from exc
    return {"ok": True, "host": HOST, "port": PORT}


def _inspect(max_entities: int = 200) -> Any:
    return _send("inspect_model", {"max_entities": max_entities})


def _find_wall_id(name: str) -> int:
    model = _inspect(1000)
    if not isinstance(model, dict):
        raise OpenSUError("inspect_model returned an unexpected response.")
    matches = [
        entity
        for entity in model.get("entities", [])
        if entity.get("opensu_type") == "wall" and entity.get("name") == name
    ]
    if not matches:
        raise OpenSUError(f"No OpenSU wall named {name!r} was found.")
    if len(matches) > 1:
        raise OpenSUError(f"More than one OpenSU wall is named {name!r}; use --wall-id instead.")
    return int(matches[0]["entity_id"])


def _print(value: Any) -> None:
    print(json.dumps(value, ensure_ascii=False, indent=2))


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Control the local OpenSU SketchUp extension.")
    sub = parser.add_subparsers(dest="command", required=True)

    sub.add_parser("status", help="Check whether the SketchUp extension server is reachable.")

    p = sub.add_parser("inspect", help="Inspect top-level SketchUp groups/components.")
    p.add_argument("--max-entities", type=int, default=200)

    p = sub.add_parser("validate", help="Validate OpenSU architectural geometry.")
    p.add_argument("--max-entities", type=int, default=1000)

    p = sub.add_parser("create-floor", help="Create a rectangular floor/slab in millimetres.")
    p.add_argument("--width", type=float, required=True)
    p.add_argument("--depth", type=float, required=True)
    p.add_argument("--thickness", type=float, default=150.0)
    p.add_argument("--origin", nargs=3, type=float, metavar=("X", "Y", "Z"), default=[0.0, 0.0, 0.0])
    p.add_argument("--name")

    p = sub.add_parser("create-wall", help="Create a straight wall from a centerline in millimetres.")
    p.add_argument("--start", nargs=3, type=float, metavar=("X", "Y", "Z"), required=True)
    p.add_argument("--end", nargs=3, type=float, metavar=("X", "Y", "Z"), required=True)
    p.add_argument("--height", type=float, default=3000.0)
    p.add_argument("--thickness", type=float, default=200.0)
    p.add_argument("--name")

    p = sub.add_parser("create-opening", help="Create one rectangular opening in an OpenSU wall.")
    target = p.add_mutually_exclusive_group(required=True)
    target.add_argument("--wall-id", type=int)
    target.add_argument("--wall-name")
    p.add_argument("--offset", type=float, required=True)
    p.add_argument("--width", type=float, required=True)
    p.add_argument("--height", type=float, required=True)
    p.add_argument("--sill", type=float, default=0.0)
    p.add_argument("--type", dest="opening_type")
    p.add_argument("--name")

    return parser


def main() -> int:
    args = build_parser().parse_args()
    try:
        if args.command == "status":
            result = _status()
        elif args.command == "inspect":
            result = _inspect(args.max_entities)
        elif args.command == "validate":
            result = _send("validate_model", {"max_entities": args.max_entities})
        elif args.command == "create-floor":
            result = _send(
                "create_floor",
                {
                    "width_mm": args.width,
                    "depth_mm": args.depth,
                    "thickness_mm": args.thickness,
                    "origin": args.origin,
                    "name": args.name,
                },
            )
        elif args.command == "create-wall":
            result = _send(
                "create_wall",
                {
                    "start": args.start,
                    "end": args.end,
                    "height_mm": args.height,
                    "thickness_mm": args.thickness,
                    "name": args.name,
                },
            )
        elif args.command == "create-opening":
            wall_id = args.wall_id if args.wall_id is not None else _find_wall_id(args.wall_name)
            result = _send(
                "create_opening",
                {
                    "wall_id": wall_id,
                    "offset_mm": args.offset,
                    "width_mm": args.width,
                    "height_mm": args.height,
                    "sill_height_mm": args.sill,
                    "opening_type": args.opening_type,
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
