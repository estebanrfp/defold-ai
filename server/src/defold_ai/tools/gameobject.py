"""Game object tools — Defold's "node" equivalent."""

from __future__ import annotations

from typing import Any

from fastmcp import FastMCP

from defold_ai.client import DefoldEditorClient


def register(mcp: FastMCP, client: DefoldEditorClient) -> None:
    @mcp.tool()
    def gameobject_create(
        collection: str = "",
        id: str = "",
        position: dict[str, float] | None = None,
        rotation: dict[str, float] | None = None,
        scale: dict[str, float] | None = None,
        reference: str = "",
        components: list[dict[str, Any]] | None = None,
    ) -> dict[str, Any]:
        """Create a game object in a collection.

        Args:
            collection: target collection path; empty = current
            id: unique id within the collection (auto-named if empty)
            position: ``{x, y, z}``, defaults to origin
            rotation: ``{x, y, z, w}`` quaternion, defaults to identity
            scale: ``{x, y, z}``, defaults to (1,1,1)
            reference: optional res:// path of an external .go to instance
                (mutually exclusive with components)
            components: list of embedded components to attach, each
                ``{ "type": "script|sprite|model|mesh|sound|particlefx|...",
                    "id": "name", ...type-specific props }``
        """
        return client.call("gameobject_create", {
            "collection": collection, "id": id,
            "position": position, "rotation": rotation, "scale": scale,
            "reference": reference, "components": components or [],
        })

    @mcp.tool()
    def gameobject_set_property(
        path: str,
        property: str,
        value: Any,
    ) -> dict[str, Any]:
        """Set a property on a game object or component.

        Args:
            path: object path in collection (e.g. ``"/main/main.collection!/player"``)
                or ``go:/player/script#movement`` for component property
            property: property name (e.g. ``"position"``, ``"rotation"``, or a
                script's exposed property like ``"__speed"``)
            value: new value. Vector3/Color: dict {x,y,z[,w]}; Resource: res:// path.
        """
        return client.call("gameobject_set_property", {
            "path": path, "property": property, "value": value,
        })

    @mcp.tool()
    def gameobject_get_properties(path: str) -> dict[str, Any]:
        """Get all properties of a game object or component."""
        return client.call("gameobject_get_properties", {"path": path})

    @mcp.tool()
    def gameobject_find(
        collection: str = "",
        name_pattern: str = "",
        type_filter: str = "",
    ) -> dict[str, Any]:
        """Find game objects matching a name pattern / component type."""
        return client.call("gameobject_find", {
            "collection": collection,
            "name_pattern": name_pattern,
            "type_filter": type_filter,
        })

    @mcp.tool()
    def gameobject_manage(op: str, params: dict[str, Any] | None = None) -> dict[str, Any]:
        """Game object tree management.

        Ops: ``delete``, ``duplicate``, ``rename``, ``reparent``, ``get_children``.
        """
        return client.call("gameobject_manage", {"op": op, "params": params or {}})
