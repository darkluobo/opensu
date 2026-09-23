# Changelog

All notable changes to this project are documented here. Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [1.15.0] — 2026-09-23

### Added
- Recursive Group-of-Groups parent-child hierarchy with stable group IDs.
- Nest, unnest, reparent, move-to-root, root listing, and recursive tree inspection.
- Parent-only organizational groups with zero direct entity members.
- Recursive visibility, Tag, shared-pivot transform, and subtree duplication.
- Safe dissolve semantics that promote child groups instead of deleting them.
- Cycle, multiple-parent, missing-child, and maximum-depth validation.
- Automatic migration of legacy v1.14 groups when the first hierarchy mutation occurs.

### Safety
- Hierarchy remains semantic only; native SketchUp geometry is not reparented.
- A child group may have only one parent.
- Cycles such as A → B → A are rejected before persistence.
- Subtree operations deduplicate entity members by persistent id.

## [1.14.0] — 2026-09-23

### Added
- Persistent OpenSU logical entity groups stored at model level by SketchUp persistent id.
- Group create/add/remove/rename/dissolve/list/inspect operations.
- Group-wide visibility, Tag assignment, shared-pivot transform, and duplication.
- `opensu_groups.py` bridge for the `$opensu` Codex Skill.
- Validation for missing/stale group members and duplicate group metadata.

### Safety
- Logical groups do not reparent SketchUp geometry.
- Dissolving a group removes only the grouping relationship and never deletes member geometry.
- Group transform/duplicate remains bounded to OpenSU Groups and uses one shared assembly pivot.

## [1.1.0] — 2026-07-02

### Changed
- Server rewritten following MCP best practices: all 13 tools renamed with a `sketchup_` prefix (avoids name collisions with other MCP servers), input validation via Pydantic (`Annotated` + `Field` constraints, `Literal` enums instead of free strings), actionable error messages (e.g. exactly how to start the SketchUp extension when the connection fails).
- Socket client now retries once on a dead connection instead of failing immediately.
- Configurable via environment variables: `SKETCHUP_MCP_HOST`, `SKETCHUP_MCP_PORT`, `SKETCHUP_MCP_TIMEOUT`.

### Added
- `sketchup_status` — new tool to verify the connection to the SketchUp extension; the first call to make in any session.

### Security
- Repository sanitized after an external security audit flagged installation-hygiene issues: unpinned `uvx` installs and client-specific references inside `SKILL.md`/`README.md` that an unrelated auditor could reasonably read as attempting to manipulate an AI reviewer. Both are fixed — the skill guide and README are now generic, install instructions pin an exact version, and provenance (maintainer, fork origin) is stated plainly instead of implied.

## [1.0.0] — 2026-07-02

### Added
- Initial hardened fork of `mhyrr/sketchup-mcp`. `eval_ruby` removed from both the Python server and the Ruby extension (see [SECURITY.md](SECURITY.md)). Extension socket bound to `127.0.0.1` only.
- 12 curated tools: create/delete/transform a component, set material, export scene, boolean operations (union/difference/intersection), chamfer/fillet edges, and three woodworking joints (mortise & tenon, dovetail, finger joint).
- `skills/sketchup-usage/SKILL.md` — usage guide for Claude Code / Claude Desktop.
