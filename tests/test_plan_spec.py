from __future__ import annotations

import importlib.util
import json
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SCRIPTS = ROOT / "skills" / "sketchup-modeling" / "scripts"
SCRIPT = SCRIPTS / "opensu_plan.py"
sys.path.insert(0, str(SCRIPTS))
SPEC = importlib.util.spec_from_file_location("opensu_plan_test_module", SCRIPT)
assert SPEC and SPEC.loader
opensu_plan = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(opensu_plan)


def test_template_lints_cleanly():
    result = opensu_plan._lint(opensu_plan._template())
    assert result["valid"] is True
    assert result["errors"] == []


def test_showroom_example_lints_cleanly():
    path = ROOT / "skills" / "sketchup-modeling" / "references" / "examples" / "showroom-plan-v1.json"
    value = json.loads(path.read_text(encoding="utf-8"))
    result = opensu_plan._lint(value)
    assert result["valid"] is True, result["errors"]


def test_opening_outside_wall_is_rejected():
    value = opensu_plan._template()
    opening = value["openings"][0]
    opening["offset_mm"] = 11800
    opening["width_mm"] = 1200
    result = opensu_plan._lint(value)
    assert result["valid"] is False
    assert any("exceeds wall" in error for error in result["errors"])


def test_overlapping_openings_are_rejected():
    value = opensu_plan._template()
    value["openings"].append(
        {
            "name": "Window_South_Opening_002",
            "wall_name": "Wall_South_001",
            "opening_type": "window",
            "offset_mm": 2000,
            "width_mm": 1800,
            "height_mm": 1500,
            "sill_height_mm": 800,
        }
    )
    result = opensu_plan._lint(value)
    assert result["valid"] is False
    assert any("overlap horizontally" in error for error in result["errors"])


def test_blocking_uncertainty_is_reported_but_not_a_schema_error():
    value = opensu_plan._template()
    value["uncertainties"] = [
        {
            "id": "U-01",
            "description": "showroom glazing height is unreadable",
            "blocking": True,
        }
    ]
    result = opensu_plan._lint(value)
    assert result["valid"] is True
    assert len(result["blocking_uncertainties"]) == 1
