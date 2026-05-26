"""Component tools — add Defold components (script, sprite, model, ...) to GOs."""

from __future__ import annotations

from typing import Any

from fastmcp import FastMCP

from defold_ai.client import DefoldEditorClient


COMPONENT_TYPES = (
    "script", "gui", "sprite", "model", "mesh", "label",
    "sound", "particlefx", "factory", "collectionfactory",
    "collisionobject", "tilemap", "camera", "buffer", "spinemodel",
)


def register(mcp: FastMCP, client: DefoldEditorClient) -> None:
    @mcp.tool()
    def component_add(
        gameobject: str,
        type: str,
        id: str = "",
        resource: str = "",
        properties: dict[str, Any] | None = None,
    ) -> dict[str, Any]:
        """Add a component to a game object.

        Args:
            gameobject: path to the GO (e.g. ``"/main/main.collection!/player"``)
            type: one of script | gui | sprite | model | mesh | label | sound |
                particlefx | factory | collectionfactory | collisionobject |
                tilemap | camera | buffer | spinemodel
            id: component id (auto-named if empty)
            resource: res:// path to the underlying resource (e.g. ``.script``,
                ``.atlas``, ``.dae``, ``.particlefx`` file)
            properties: type-specific properties. Examples:
                - sprite: ``{default_animation, material}``
                - model: ``{mesh, material, textures}``
                - camera: ``{fov, near_z, far_z, orthographic_projection}``
                - collisionobject: ``{shapes: [{type, dimensions}], ...}``
        """
        return client.call("component_add", {
            "gameobject": gameobject,
            "type": type,
            "id": id,
            "resource": resource,
            "properties": properties or {},
        })

    @mcp.tool()
    def component_remove(gameobject: str, component_id: str) -> dict[str, Any]:
        """Remove a component from a game object."""
        return client.call("component_remove", {
            "gameobject": gameobject, "component_id": component_id,
        })

    @mcp.tool()
    def component_list_types() -> dict[str, Any]:
        """List all supported Defold component types."""
        return {"types": list(COMPONENT_TYPES)}
