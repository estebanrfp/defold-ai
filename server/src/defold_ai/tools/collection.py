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
          • ``open``(path): open an existing .collection
          • ``save``(): save the currently edited collection

          • ``add_instance``(path, id, prototype, position?, rotation?, scale?,
              children?, script_properties?):
            Append a GO reference (``instances {...}``) to an existing
            .collection file. ``children`` is a list of sibling instance ids
            that become this instance's transform children.
            ``script_properties`` is ``{component_id: {prop_name: value, ...}}``
            and emits a ``component_properties { ... }`` block — perfect for
            tinting/configuring re-used prototypes without one-off .go files.

          • ``add_embedded``(path, id, components=[...], position?, rotation?,
              scale?, children?, script_properties?):
            Append a GO defined inline (``embedded_instances {...}``). The
            ``components`` list uses the same schema as
            ``gameobject_manage(op="create_file")``.

          • ``add_collection_instance``(path, id, collection, position?, …,
              children?, script_properties?):
            Append a ``collection_instances {...}`` entry that re-uses a
            whole .collection as a sub-tree.

          • ``set_parent``(path, parent_id, child_id):
            Append ``children: "<child_id>"`` to the named parent instance
            block. Idempotency is the caller's responsibility — calling twice
            with the same pair emits two entries.

          • ``remove_instance``(path, id): Remove an instance (reference,
            embedded, or collection_instance) by id.

          • ``save_as`` / ``get_roots``: planned (Defold editor API gap).

        Position / rotation / scale accept ``{x, y, z[, w]}`` dicts. Defaults:
        zero position, identity rotation, unit scale.
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
