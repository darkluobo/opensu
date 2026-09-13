from __future__ import annotations

import importlib.util
from pathlib import Path
from zipfile import ZipFile


ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts" / "build_rbz.py"


def load_builder():
    spec = importlib.util.spec_from_file_location("build_rbz", SCRIPT)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


def test_build_rbz_contains_required_extension_files(tmp_path):
    builder = load_builder()
    output = tmp_path / "opensu-test.rbz"

    result = builder.build_rbz(output)

    assert result == output.resolve()
    assert output.is_file()

    with ZipFile(output) as archive:
        names = set(archive.namelist())

    required = {
        "su_mcp.rb",
        "su_mcp/su_mcp/bootstrap.rb",
        "su_mcp/su_mcp/main.rb",
        "su_mcp/su_mcp/architecture.rb",
        "su_mcp/su_mcp/architecture_completion.rb",
        "su_mcp/su_mcp/architecture_validation.rb",
    }
    assert required.issubset(names)
