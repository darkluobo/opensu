"""MCP server tests that do not require a live SketchUp instance.

They cover the hardened security property and the expected public tool surface
for the complete Phase 1 architecture-enabled server entrypoint.
"""

from pathlib import Path

from sketchup_mcp import phase1_server as server

SRC_DIR = Path(__file__).resolve().parent.parent / "src" / "sketchup_mcp"
RUBY_DIR = Path(__file__).resolve().parent.parent / "su_mcp" / "su_mcp"

EXPECTED_TOOLS = {
    "sketchup_status",
    "sketchup_get_selection",
    "sketchup_create_component",
    "sketchup_transform_component",
    "sketchup_delete_component",
    "sketchup_set_material",
    "sketchup_export_scene",
    "sketchup_boolean_operation",
    "sketchup_chamfer_edges",
    "sketchup_fillet_edges",
    "sketchup_create_mortise_tenon",
    "sketchup_create_dovetail",
    "sketchup_create_finger_joint",
    "sketchup_inspect_model",
    "sketchup_create_floor",
    "sketchup_create_wall",
    "sketchup_create_opening",
    "sketchup_validate_model",
}

_CODE_EXEC_TOKEN = "ev" + "al" + "_ruby"
_RUBY_EXEC_TOKEN = "ev" + "al" + "("


def _registered_tool_names() -> set[str]:
    return set(server.mcp._tool_manager._tools.keys())


def test_exposes_expected_tool_surface():
    assert _registered_tool_names() == EXPECTED_TOOLS


def test_all_tools_use_sketchup_prefix():
    assert all(name.startswith("sketchup_") for name in _registered_tool_names())


def test_arbitrary_ruby_execution_is_not_registered():
    assert _CODE_EXEC_TOKEN not in _registered_tool_names()
    assert not hasattr(server, _CODE_EXEC_TOKEN)
    assert not hasattr(server.base, _CODE_EXEC_TOKEN)


def test_python_source_contains_no_arbitrary_ruby_tool():
    for path in SRC_DIR.rglob("*.py"):
        text = path.read_text(encoding="utf-8")
        assert _CODE_EXEC_TOKEN not in text, f"'{_CODE_EXEC_TOKEN}' reappeared in {path}"


def test_connection_failure_is_actionable_without_sketchup():
    import json

    result = json.loads(server.base.sketchup_status())
    assert result["ok"] is False
    assert "Start Server" in result["error"]


def test_ruby_extension_contains_no_eval_execution():
    for path in RUBY_DIR.rglob("*.rb"):
        text = path.read_text(encoding="utf-8")
        assert _RUBY_EXEC_TOKEN not in text, f"arbitrary Ruby execution reappeared in {path}"
