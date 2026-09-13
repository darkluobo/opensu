from __future__ import annotations

import importlib.util
import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "skills" / "sketchup-modeling" / "scripts" / "opensu_multisheet.py"
SPEC = importlib.util.spec_from_file_location("opensu_multisheet_test_module", SCRIPT)
assert SPEC and SPEC.loader
opensu_multisheet = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(opensu_multisheet)


def test_template_cross_checks_cleanly():
    result = opensu_multisheet._lint(opensu_multisheet._template())
    assert result["valid"] is True
    assert result["blocking_conflicts"] == []
    assert result["errors"] == []


def test_showroom_multisheet_example_cross_checks_cleanly():
    path = ROOT / "skills" / "sketchup-modeling" / "references" / "examples" / "showroom-multisheet-pack-v1.json"
    value = json.loads(path.read_text(encoding="utf-8"))
    result = opensu_multisheet._lint(value)
    assert result["valid"] is True, result
    assert result["blocking_conflicts"] == []
    assert result["sheet_count"] == 4


def test_equal_priority_conflict_blocks():
    value = opensu_multisheet._template()
    value["claims"].append(
        {
            "claim_id": "C-099",
            "target": "walls.Wall_South_001.height_mm",
            "value": 4500,
            "sheet_id": "A-301",
            "basis": "printed_dimension",
            "confidence": "high",
            "axis_role": "z",
        }
    )
    result = opensu_multisheet._lint(value)
    assert result["valid"] is False
    assert len(result["blocking_conflicts"]) == 1
    assert result["blocking_conflicts"][0]["target"] == "walls.Wall_South_001.height_mm"


def test_lower_priority_disagreement_warns_but_does_not_override():
    value = opensu_multisheet._template()
    value["claims"].append(
        {
            "claim_id": "C-099",
            "target": "walls.Wall_South_001.height_mm",
            "value": 4350,
            "sheet_id": "A-101",
            "basis": "pixel_estimate",
            "confidence": "low",
            "axis_role": "z",
            "tolerance_mm": 20,
        }
    )
    result = opensu_multisheet._lint(value)
    assert result["valid"] is True
    resolved = next(item for item in result["resolved_claims"] if item["target"] == "walls.Wall_South_001.height_mm")
    assert resolved["value"] == 4200
    assert any("C-099" in warning for warning in result["warnings"])


def test_plan_spec_must_match_resolved_evidence():
    value = opensu_multisheet._template()
    value["plan_spec"]["walls"][0]["height_mm"] = 4300
    result = opensu_multisheet._lint(value)
    assert result["valid"] is False
    assert any("Plan Spec mismatch" in error for error in result["errors"])


def test_unknown_sheet_reference_is_rejected():
    value = opensu_multisheet._template()
    value["claims"][0]["sheet_id"] = "A-999"
    result = opensu_multisheet._lint(value)
    assert result["valid"] is False
    assert any("unknown sheet_id" in error for error in result["errors"])


def test_blocking_uncertainty_is_reported_separately():
    value = opensu_multisheet._template()
    value["uncertainties"] = [
        {
            "id": "U-01",
            "description": "Workshop roller shutter height is unreadable on both elevation and schedule.",
            "blocking": True,
        }
    ]
    result = opensu_multisheet._lint(value)
    assert result["valid"] is True
    assert len(result["blocking_uncertainties"]) == 1
