"""Unit tests for the architecture MCP wrapper layer."""

import json

from sketchup_mcp import architecture_server


def test_inspect_model_forwards_limit(monkeypatch):
    calls = []

    def fake_call(name, arguments):
        calls.append((name, arguments))
        return json.dumps({"ok": True})

    monkeypatch.setattr(architecture_server.base, "_call", fake_call)
    architecture_server.sketchup_inspect_model(max_entities=25)

    assert calls == [("inspect_model", {"max_entities": 25})]


def test_create_floor_uses_mm_contract(monkeypatch):
    calls = []

    def fake_call(name, arguments):
        calls.append((name, arguments))
        return json.dumps({"ok": True})

    monkeypatch.setattr(architecture_server.base, "_call", fake_call)
    architecture_server.sketchup_create_floor(
        width_mm=8000,
        depth_mm=6000,
        thickness_mm=150,
        origin_mm=[0, 0, 0],
        name="Floor_001",
    )

    assert calls == [
        (
            "create_floor",
            {
                "width_mm": 8000,
                "depth_mm": 6000,
                "thickness_mm": 150,
                "origin": [0, 0, 0],
                "name": "Floor_001",
            },
        )
    ]


def test_create_wall_forwards_centerline_in_mm(monkeypatch):
    calls = []

    def fake_call(name, arguments):
        calls.append((name, arguments))
        return json.dumps({"ok": True})

    monkeypatch.setattr(architecture_server.base, "_call", fake_call)
    architecture_server.sketchup_create_wall(
        start_mm=[0, 0, 150],
        end_mm=[8000, 0, 150],
        height_mm=3000,
        thickness_mm=200,
        name="Wall_South",
    )

    assert calls == [
        (
            "create_wall",
            {
                "start": [0, 0, 150],
                "end": [8000, 0, 150],
                "height_mm": 3000,
                "thickness_mm": 200,
                "name": "Wall_South",
            },
        )
    ]


def test_floor_rejects_bad_origin_without_calling_sketchup(monkeypatch):
    called = False

    def fake_call(name, arguments):
        nonlocal called
        called = True
        return json.dumps({"ok": True})

    monkeypatch.setattr(architecture_server.base, "_call", fake_call)
    result = json.loads(
        architecture_server.sketchup_create_floor(
            width_mm=8000,
            depth_mm=6000,
            origin_mm=[0, 0],
        )
    )

    assert result["ok"] is False
    assert "origin_mm" in result["error"]
    assert called is False
