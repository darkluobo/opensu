"""Architecture-focused MCP tools layered on top of the base SketchUp server.

These tools use millimetres at the protocol boundary and delegate to bounded
Ruby handlers in the companion SketchUp extension.
"""

from __future__ import annotations

import json
from typing import Annotated, Optional

from pydantic import Field

from . import server as base

mcp = base.mcp


def _vector3(value: Optional[list[float]], label: str, default: list[float] | None = None) -> list[float] | str:
    vector = default if value is None else value
    if vector is None or len(vector) != 3:
        return json.dumps({"ok": False, "error": f"{label} must be [x, y, z]."})
    return vector


@mcp.tool(
    name="sketchup_inspect_model",
    annotations={
        "title": "Inspect SketchUp model",
        "readOnlyHint": True,
        "destructiveHint": False,
        "idempotentHint": True,
        "openWorldHint": False,
    },
)
def sketchup_inspect_model(
    max_entities: Annotated[
        int,
        Field(description="Maximum number of top-level groups/components to return", ge=1, le=1000),
    ] = 200,
) -> str:
    """Inspect the current model root without modifying it.

    Returns root-level group/component metadata, loose geometry counts, model
    edit context, names, tags and world-space bounds in millimetres. Call this
    before architectural edits and again after a modeling batch.
    """
    return base._call("inspect_model", {"max_entities": max_entities})


@mcp.tool(
    name="sketchup_create_floor",
    annotations={
        "title": "Create architectural floor",
        "readOnlyHint": False,
        "destructiveHint": False,
        "idempotentHint": False,
        "openWorldHint": False,
    },
)
def sketchup_create_floor(
    width_mm: Annotated[float, Field(description="Floor width in millimetres", gt=0)],
    depth_mm: Annotated[float, Field(description="Floor depth in millimetres", gt=0)],
    thickness_mm: Annotated[float, Field(description="Floor thickness in millimetres", gt=0)] = 150.0,
    origin_mm: Annotated[
        Optional[list[float]],
        Field(description="Lower corner [x, y, z] in millimetres; default [0,0,0]"),
    ] = None,
    name: Annotated[
        Optional[str],
        Field(description="Optional stable SketchUp group name; auto-generated when omitted", max_length=120),
    ] = None,
) -> str:
    """Create one isolated rectangular floor Group using millimetres.

    Geometry is created at the model root, annotated with OpenSU metadata and
    wrapped in a single undoable SketchUp operation.
    """
    origin = _vector3(origin_mm, "origin_mm", [0.0, 0.0, 0.0])
    if isinstance(origin, str):
        return origin
    return base._call(
        "create_floor",
        {
            "width_mm": width_mm,
            "depth_mm": depth_mm,
            "thickness_mm": thickness_mm,
            "origin": origin,
            "name": name,
        },
    )


@mcp.tool(
    name="sketchup_create_wall",
    annotations={
        "title": "Create architectural wall",
        "readOnlyHint": False,
        "destructiveHint": False,
        "idempotentHint": False,
        "openWorldHint": False,
    },
)
def sketchup_create_wall(
    start_mm: Annotated[list[float], Field(description="Wall centerline start [x, y, z] in millimetres")],
    end_mm: Annotated[list[float], Field(description="Wall centerline end [x, y, z] in millimetres")],
    height_mm: Annotated[float, Field(description="Wall height in millimetres", gt=0)] = 3000.0,
    thickness_mm: Annotated[float, Field(description="Wall thickness in millimetres", gt=0)] = 200.0,
    name: Annotated[
        Optional[str],
        Field(description="Optional stable SketchUp group name; auto-generated when omitted", max_length=120),
    ] = None,
) -> str:
    """Create an isolated straight wall Group from a centerline in millimetres.

    Phase 1 requires start and end to share the same Z elevation. Thickness is
    centered on the supplied centerline. The wall may use any horizontal angle.
    """
    start = _vector3(start_mm, "start_mm")
    if isinstance(start, str):
        return start
    end = _vector3(end_mm, "end_mm")
    if isinstance(end, str):
        return end
    return base._call(
        "create_wall",
        {
            "start": start,
            "end": end,
            "height_mm": height_mm,
            "thickness_mm": thickness_mm,
            "name": name,
        },
    )


def main() -> None:
    """Run the MCP server with the architecture tool layer registered."""
    base.main()


if __name__ == "__main__":
    main()
