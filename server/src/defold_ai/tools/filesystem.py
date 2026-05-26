"""Filesystem tools — read/write text files within the Defold project tree."""

from __future__ import annotations

from typing import Any

from fastmcp import FastMCP

from defold_ai.client import DefoldEditorClient


def register(mcp: FastMCP, client: DefoldEditorClient) -> None:
    @mcp.tool()
    def filesystem_manage(op: str, params: dict[str, Any] | None = None) -> dict[str, Any]:
        """Defold project filesystem access via the editor's resource API.

        Ops:
          • ``read_text``(path): read a text file. Returns {content, size, line_count}.
          • ``write_text``(path, content): create or overwrite a text file.
          • ``reimport``(paths): force-reimport list of res:// paths.
          • ``search``(name, type, path, offset, limit): find resources.
          • ``mkdir``(path): create a directory.
          • ``rm``(path): delete a file.
        """
        return client.call("filesystem_manage", {"op": op, "params": params or {}})
