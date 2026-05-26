"""FastMCP server entry. Registers all tool modules."""

from __future__ import annotations

from fastmcp import FastMCP

from defold_ai.client import DefoldEditorClient
from defold_ai.tools import (
    camera,
    collection,
    component,
    editor,
    filesystem,
    gameobject,
    input_binding,
    project,
    resource,
    script,
)


def build_server() -> FastMCP:
    mcp = FastMCP(
        name="defold-ai",
        instructions=(
            "MCP server for the Defold game engine. "
            "Tools forward calls to a running Defold editor's HTTP server. "
            "Open Defold with a project containing plugin/mcp/mcp.editor_script "
            "before invoking tools. Use editor_state to verify connection."
        ),
    )
    client = DefoldEditorClient()
    # Each module registers its own @mcp.tool() decorators
    editor.register(mcp, client)
    collection.register(mcp, client)
    gameobject.register(mcp, client)
    component.register(mcp, client)
    script.register(mcp, client)
    resource.register(mcp, client)
    filesystem.register(mcp, client)
    input_binding.register(mcp, client)
    project.register(mcp, client)
    camera.register(mcp, client)
    return mcp
