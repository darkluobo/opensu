from __future__ import annotations

import importlib.util
import sys
from pathlib import Path

import pytest


ROOT = Path(__file__).resolve().parents[1]
SCRIPTS = ROOT / "skills" / "sketchup-modeling" / "scripts"
SCRIPT = SCRIPTS / "opensu_layout.py"
if str(SCRIPTS) not in sys.path:
    sys.path.insert(0, str(SCRIPTS))

SPEC = importlib.util.spec_from_file_location("opensu_layout_test_module", SCRIPT)
assert SPEC and SPEC.loader
opensu_layout = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(opensu_layout)


def test_grid_intersection_parser_accepts_architectural_notation():
    assert opensu_layout._intersection("3/B") == ("3", "B")
    assert opensu_layout._intersection(" 12 / C ") == ("12", "C")
    assert opensu_layout._intersection("4×D") == ("4", "D")


def test_grid_intersection_parser_rejects_single_token():
    with pytest.raises(opensu_layout.OpenSUError):
        opensu_layout._intersection("A3")


def test_showroom_strategy_is_advisory_and_does_not_define_dimensions():
    strategy = opensu_layout.SPACE_STRATEGIES["showroom"]
    assert strategy["facade"] == "curtain_wall_candidate"
    assert "width_mm" not in strategy
    assert "height_mm" not in strategy


def test_workshop_strategy_requires_grid_evidence_not_invented_bays():
    strategy = opensu_layout.SPACE_STRATEGIES["workshop"]
    assert strategy["structure"] == "grid_driven_large_bays"
    assert any("Do not invent service-bay spacing" in note for note in strategy["notes"])


def test_ruby_semantic_layout_exposes_bounded_tools_without_eval():
    ruby = (ROOT / "su_mcp" / "su_mcp" / "semantic_layout.rb").read_text(encoding="utf-8")
    for tool in (
        "resolve_grid_intersection",
        "create_grid_column",
        "create_grid_beam",
        "create_space_partitions",
    ):
        assert tool in ruby
    assert "eval(" not in ruby
