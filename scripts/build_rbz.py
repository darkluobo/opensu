#!/usr/bin/env python3
"""Build an installable SketchUp RBZ archive from the repository source tree."""

from __future__ import annotations

import argparse
from pathlib import Path
from zipfile import ZIP_DEFLATED, ZipFile

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_OUTPUT = ROOT / "dist" / "opensu-sketchup-mcp-phase3.rbz"


def build_rbz(output: Path = DEFAULT_OUTPUT) -> Path:
    loader = ROOT / "su_mcp.rb"
    plugin_dir = ROOT / "su_mcp"

    if not loader.is_file():
        raise FileNotFoundError(f"Missing SketchUp loader: {loader}")
    if not plugin_dir.is_dir():
        raise FileNotFoundError(f"Missing SketchUp plugin directory: {plugin_dir}")

    output = output.resolve()
    output.parent.mkdir(parents=True, exist_ok=True)
    if output.exists():
        output.unlink()

    with ZipFile(output, "w", compression=ZIP_DEFLATED) as archive:
        archive.write(loader, "su_mcp.rb")
        for path in sorted(plugin_dir.rglob("*")):
            if not path.is_file():
                continue
            if path.resolve() == output:
                continue
            archive.write(path, path.relative_to(ROOT).as_posix())

    return output


def main() -> None:
    parser = argparse.ArgumentParser(description="Build the OpenSU SketchUp MCP RBZ package.")
    parser.add_argument(
        "--output",
        type=Path,
        default=DEFAULT_OUTPUT,
        help=f"Output RBZ path (default: {DEFAULT_OUTPUT.relative_to(ROOT)})",
    )
    args = parser.parse_args()
    output = build_rbz(args.output)
    print(output)


if __name__ == "__main__":
    main()
