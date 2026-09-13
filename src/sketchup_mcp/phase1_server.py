"""Default MCP entrypoint for the Phase 1 architecture-capable server."""

from .architecture_server import base, mcp
from . import architecture_completion as _architecture_completion  # noqa: F401


def main() -> None:
    base.main()


if __name__ == "__main__":
    main()
