"""Script tools — create, attach, patch .script files."""

from __future__ import annotations

from typing import Any

from fastmcp import FastMCP

from defold_ai.client import DefoldEditorClient


def register(mcp: FastMCP, client: DefoldEditorClient) -> None:
    @mcp.tool()
    def script_create(path: str, content: str = "") -> dict[str, Any]:
        """Create a new .script (or .gui_script / .render_script / .lua) file.

        Args:
            path: res:// path ending in .script, .gui_script, .render_script,
                or .lua
            content: Lua source. Empty creates a blank file.
        """
        return client.call("script_create", {"path": path, "content": content})

    @mcp.tool()
    def script_attach(gameobject: str, script_path: str, id: str = "") -> dict[str, Any]:
        """Attach a .script component to a game object.

        Args:
            gameobject: path to the GO
            script_path: res:// path of the .script
            id: component id (auto-named if empty)
        """
        return client.call("script_attach", {
            "gameobject": gameobject,
            "script_path": script_path,
            "id": id,
        })

    @mcp.tool()
    def script_patch(
        path: str,
        old_text: str,
        new_text: str,
        replace_all: bool = False,
    ) -> dict[str, Any]:
        """Anchor-based string-replace edit on a .script / .lua file.

        Finds exact ``old_text`` and replaces with ``new_text``. Fails on
        multiple matches unless ``replace_all=True``; fails on zero matches.
        """
        return client.call("script_patch", {
            "path": path,
            "old_text": old_text,
            "new_text": new_text,
            "replace_all": replace_all,
        })

    @mcp.tool()
    def script_manage(op: str, params: dict[str, Any] | None = None) -> dict[str, Any]:
        """Script ops: ``read``, ``detach``, ``find_symbols``.

        Args:
            op: operation name
            params: ``read``: {path}; ``detach``: {gameobject, component_id};
                ``find_symbols``: {path}
        """
        return client.call("script_manage", {"op": op, "params": params or {}})
