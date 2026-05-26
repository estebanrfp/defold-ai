"""Collection tools: Defold's equivalent of a 'scene' (.collection file)."""

from __future__ import annotations

from typing import Any

from fastmcp import FastMCP

from defold_ai.client import DefoldEditorClient


def register(mcp: FastMCP, client: DefoldEditorClient) -> None:
    @mcp.tool()
    def collection_manage(op: str, params: dict[str, Any] | None = None) -> dict[str, Any]:
        """Collection authoring.

        Ops:
          • ``create``(path, name=""): create a new .collection at path
          • ``save_as``(path): save the currently edited collection as path
          • ``get_roots``(): list open collections; flag the edited one
          • ``open``(path): open an existing .collection
          • ``save``(): save the currently edited collection
        """
        return client.call("collection_manage", {"op": op, "params": params or {}})

    @mcp.tool()
    def collection_get_hierarchy(
        path: str = "",
        depth: int = 10,
        limit: int = 100,
        offset: int = 0,
    ) -> dict[str, Any]:
        """Get the game-object tree of an open collection.

        Args:
            path: collection path; empty = currently edited
            depth: max walk depth
            limit: max nodes returned
            offset: nodes to skip
        """
        return client.call("collection_get_hierarchy", {
            "path": path, "depth": depth, "limit": limit, "offset": offset,
        })

    @mcp.tool()
    def collection_open(path: str) -> dict[str, Any]:
        """Open an existing .collection file in the editor."""
        return client.call("collection_open", {"path": path})

    @mcp.tool()
    def collection_save() -> dict[str, Any]:
        """Save the currently edited collection."""
        return client.call("collection_save", {})
