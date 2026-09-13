from __future__ import annotations

import importlib.util
import json
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SCRIPTS = ROOT / "skills" / "opensu" / "scripts"
if str(SCRIPTS) not in sys.path:
    sys.path.insert(0, str(SCRIPTS))
SCRIPT = SCRIPTS / "opensu_semantics.py"
SPEC = importlib.util.spec_from_file_location("opensu_semantics_test_module", SCRIPT)
assert SPEC and SPEC.loader
opensu_semantics = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(opensu_semantics)


def test_semantic_template_lints_cleanly():
    result = opensu_semantics._lint(opensu_semantics._template())
    assert result["valid"] is True, result
    assert result["counts"] == {"grids": 4, "spaces": 1}


def test_showroom_semantic_example_lints_cleanly():
    path = ROOT / "skills" / "opensu" / "references" / "examples" / "showroom-semantics-v1.json"
    result = opensu_semantics._lint(json.loads(path.read_text(encoding="utf-8")))
    assert result["valid"] is True, result
    assert result["counts"]["grids"] == 9
    assert result["counts"]["spaces"] == 4


def test_duplicate_grid_coordinate_is_rejected():
    value = opensu_semantics._template()
    value["grids"].append({"name": "3", "axis": "x", "coordinate_mm": 6000})
    result = opensu_semantics._lint(value)
    assert result["valid"] is False
    assert any("Duplicate X grid coordinate" in error for error in result["errors"])


def test_self_intersecting_space_is_rejected():
    value = opensu_semantics._template()
    value["spaces"][0]["boundary_mm"] = [[0, 0], [1000, 1000], [0, 1000], [1000, 0]]
    result = opensu_semantics._lint(value)
    assert result["valid"] is False
    assert any("self-intersects" in error for error in result["errors"])


def test_sheet_index_classifies_common_architectural_names(tmp_path: Path):
    names = [
        "A-101_一层平面_RevA.pdf",
        "A-201_南立面.pdf",
        "A-301_剖面A-A.pdf",
        "A-501_入口节点详图.png",
        "A-601_门窗表.pdf",
        "reference_photo.jpg",
    ]
    for name in names:
        (tmp_path / name).write_bytes(b"")
    result = opensu_semantics._index_sheets(tmp_path)
    by_id = {item["sheet_id"]: item for item in result["sheets"] if item["sheet_id"]}
    assert result["sheet_count"] == 6
    assert by_id["A-101"]["kind"] == "plan"
    assert by_id["A-101"]["revision"] == "A"
    assert by_id["A-201"]["kind"] == "elevation"
    assert by_id["A-301"]["kind"] == "section"
    assert by_id["A-501"]["kind"] == "detail"
    assert by_id["A-601"]["kind"] == "schedule"
    assert result["unidentified_count"] == 1


def test_sheet_index_reports_duplicate_sheet_ids(tmp_path: Path):
    (tmp_path / "A-101_一层平面_RevA.pdf").write_bytes(b"")
    (tmp_path / "A-101_一层平面_RevB.pdf").write_bytes(b"")
    result = opensu_semantics._index_sheets(tmp_path)
    assert "A-101" in result["duplicate_sheet_ids"]
    assert result["ready_for_review"] is False
