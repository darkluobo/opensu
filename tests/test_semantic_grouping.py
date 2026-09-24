from __future__ import annotations

import argparse
import importlib.util
import sys
from pathlib import Path

import pytest


ROOT = Path(__file__).resolve().parents[1]
SCRIPTS = ROOT / "skills" / "opensu" / "scripts"
SCRIPT = SCRIPTS / "opensu_groups.py"
if str(SCRIPTS) not in sys.path:
    sys.path.insert(0, str(SCRIPTS))

SPEC = importlib.util.spec_from_file_location("opensu_groups_test_module", SCRIPT)
assert SPEC and SPEC.loader
opensu_groups = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(opensu_groups)


def test_group_cli_exposes_expected_commands():
    parser = opensu_groups.build_parser()
    for argv in (
        ["list"],
        ["roots"],
        ["inspect", "--group", "Showroom"],
        ["tree", "--group", "Level_01"],
        ["create", "--group", "Showroom", "--id", "1"],
        ["create", "--group", "Structure", "--child-group", "Columns"],
        ["nest", "--parent", "Level_01", "--child", "Structure"],
        ["unnest", "--parent", "Level_01", "--child", "Structure"],
        ["move", "--group", "Structure", "--parent", "Level_02"],
        ["move", "--group", "Structure", "--to-root"],
        ["add", "--group", "Showroom", "--id", "2"],
        ["remove", "--group", "Showroom", "--id", "2"],
        ["prune-missing", "--group", "Showroom"],
        ["rename", "--group", "Showroom", "--new-name", "Showroom_Main"],
        ["dissolve", "--group", "Showroom"],
        ["visible", "--group", "Showroom", "--hide"],
        ["tag", "--group", "Showroom", "--tag", "A-SHOWROOM"],
        ["transform", "--group", "Showroom", "--translation", "1000", "0", "0"],
        ["duplicate", "--group", "Showroom", "--new-group", "Showroom_Copy"],
    ):
        assert parser.parse_args(argv).command


def test_member_ids_reject_duplicate_members():
    args = argparse.Namespace(entity_ids=[10, 10], entity_names=[])
    with pytest.raises(opensu_groups.OpenSUError):
        opensu_groups._member_ids(args)


def test_member_ids_require_at_least_one_member():
    args = argparse.Namespace(entity_ids=[], entity_names=[])
    with pytest.raises(opensu_groups.OpenSUError):
        opensu_groups._member_ids(args)


def test_ruby_grouping_is_logical_persistent_and_non_destructive():
    ruby = (ROOT / "su_mcp" / "su_mcp" / "semantic_grouping.rb").read_text(encoding="utf-8")
    for tool in (
        "create_entity_group",
        "add_entities_to_group",
        "remove_entities_from_group",
        "prune_missing_entity_group_members",
        "rename_entity_group",
        "delete_entity_group",
        "list_entity_groups",
        "inspect_entity_group",
        "set_entity_group_visibility",
        "set_entity_group_tag",
        "transform_entity_group",
        "duplicate_entity_group",
    ):
        assert tool in ruby
    assert "entity_groups_json" in ruby
    assert "persistent_id" in ruby
    assert "members_deleted: false" in ruby
    assert "erase!" not in ruby
    assert "eval(" not in ruby


def test_group_validation_detects_missing_persistent_members():
    ruby = (
        ROOT / "su_mcp" / "su_mcp" / "semantic_grouping_validation.rb"
    ).read_text(encoding="utf-8")
    assert "references missing member persistent id" in ruby
    assert "entity_group_memberships" in ruby



def test_group_create_allows_child_only_parent():
    parser = opensu_groups.build_parser()
    args = parser.parse_args(
        ["create", "--group", "Structure", "--child-group", "Columns"]
    )
    assert opensu_groups._member_ids(args, required=False) == []
    assert args.child_groups == ["Columns"]


def test_ruby_hierarchy_uses_stable_group_ids_and_cycle_guards():
    ruby = (
        ROOT / "su_mcp" / "su_mcp" / "semantic_group_hierarchy.rb"
    ).read_text(encoding="utf-8")
    for tool in (
        "add_child_entity_group",
        "remove_child_entity_group",
        "move_entity_group",
        "inspect_entity_group_tree",
        "list_entity_group_roots",
    ):
        assert tool in ruby
    assert "group_id" in ruby
    assert "child_group_ids" in ruby
    assert "SecureRandom.uuid" in ruby
    assert "would create a cycle" in ruby
    assert "shared pivot" not in ruby.lower() or "pivot_mm" in ruby
    assert "erase!" not in ruby
    assert "eval(" not in ruby


def test_hierarchy_validation_enforces_tree_and_depth():
    ruby = (
        ROOT / "su_mcp" / "su_mcp" / "semantic_group_hierarchy_validation.rb"
    ).read_text(encoding="utf-8")
    assert "group hierarchy must be a tree" in ruby
    assert "hierarchy cycle detected" in ruby
    assert "maximum depth" in ruby
    assert "legacy_entity_groups" in ruby
