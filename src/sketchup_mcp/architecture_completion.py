"""Phase 1 completion tools: wall openings and model validation."""

from __future__ import annotations

from typing import Annotated, Optional

from pydantic import Field

from .architecture_server import base, mcp


@mcp.tool(
    name="sketchup_create_opening",
    annotations={
        "title": "Create wall opening",
        "readOnlyHint": False,
        "destructiveHint": False,
        "idempotentHint": False,
        "openWorldHint": False,
    },
)
def sketchup_create_opening(
    wall_id: Annotated[str, Field(description="Entity id of an OpenSU wall Group", min_length=1)],
    offset_mm: Annotated[float, Field(description="Distance from wall start to opening start in millimetres", gt=0)],
    width_mm: Annotated[float, Field(description="Opening width in millimetres", gt=0)],
    height_mm: Annotated[float, Field(description="Opening height in millimetres", gt=0)],
    sill_height_mm: Annotated[float, Field(description="Sill height in millimetres; use 0 for a door", ge=0)] = 0.0,
    opening_type: Annotated[
        Optional[str],
        Field(description="Optional semantic type such as door or window", max_length=120),
    ] = None,
    name: Annotated[
        Optional[str],
        Field(description="Optional stable opening name", max_length=120),
    ] = None,
) -> str:
    """Create one rectangular opening in an OpenSU wall using millimetres.

    Phase 1 supports one opening per wall. The opening must stay away from the
    wall endpoints; doors may touch the wall base by using sill_height_mm=0.
    """
    return base._call(
        "create_opening",
        {
            "wall_id": wall_id,
            "offset_mm": offset_mm,
            "width_mm": width_mm,
            "height_mm": height_mm,
            "sill_height_mm": sill_height_mm,
            "opening_type": opening_type,
            "name": name,
        },
    )


@mcp.tool(
    name="sketchup_validate_model",
    annotations={
        "title": "Validate architecture model",
        "readOnlyHint": True,
        "destructiveHint": False,
        "idempotentHint": True,
        "openWorldHint": False,
    },
)
def sketchup_validate_model(
    max_entities: Annotated[
        int,
        Field(description="Maximum root entities to validate", ge=1, le=5000),
    ] = 1000,
) -> str:
    """Validate OpenSU architecture structure without modifying SketchUp.

    Checks root loose geometry, duplicate names, required metadata and basic
    floor/wall geometry invariants. Returns valid/errors/warnings and counts.
    """
    return base._call("validate_model", {"max_entities": max_entities})
