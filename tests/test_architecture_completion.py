"""Unit tests for Phase 1 opening and validation wrappers."""

import json

from sketchup_mcp import architecture_completion


def test_create_opening_forwards_mm_contract(monkeypatch):
    calls = []

    def fake_call(name, arguments):
        calls.append((name, arguments))
        return json.dumps({"ok": True})

    monkeypatch.setattr(architecture_completion.base, "_call", fake_call)
    architecture_completion.sketchup_create_opening(
        wall_id="123",
        offset_mm=1200,
        width_mm=900,
        height_mm=2100,
        sill_height_mm=0,
        opening_type="door",
        name="Door_South_01",
    )

    assert calls == [
        (
            "create_opening",
            {
                "wall_id": "123",
                "offset_mm": 1200,
                "width_mm": 900,
                "height_mm": 2100,
                "sill_height_mm": 0,
                "opening_type": "door",
                "name": "Door_South_01",
            },
        )
    ]


def test_validate_model_is_read_only_forwarder(monkeypatch):
    calls = []

    def fake_call(name, arguments):
        calls.append((name, arguments))
        return json.dumps({"ok": True})

    monkeypatch.setattr(architecture_completion.base, "_call", fake_call)
    architecture_completion.sketchup_validate_model(max_entities=500)

    assert calls == [("validate_model", {"max_entities": 500})]
