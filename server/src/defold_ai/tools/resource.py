"""Resource tools — atlas, tilesource, material, font, particlefx, etc."""

from __future__ import annotations

from typing import Any

from fastmcp import FastMCP

from defold_ai.client import DefoldEditorClient


def register(mcp: FastMCP, client: DefoldEditorClient) -> None:
    @mcp.tool()
    def resource_manage(op: str, params: dict[str, Any] | None = None) -> dict[str, Any]:
        """Defold resource management.

        Ops:
          • ``create``(path, content): create a typed resource file
            (.atlas, .tilesource, .material, .font, .particlefx, .input_binding,
            .render, .display_profiles, .gui)
          • ``read``(path): read a resource file's source
          • ``write``(path, content): overwrite a resource file
          • ``list``(directory, filter): list resources in a folder, optionally
            filtered by extension (e.g. ``filter=".material"``)
          • ``delete``(path): delete a resource file

        For specific resource subdomains, prefer the dedicated tools when
        available (e.g. ``script_create`` for .script files).
        """
        return client.call("resource_manage", {"op": op, "params": params or {}})

    @mcp.tool()
    def material_manage(op: str, params: dict[str, Any] | None = None) -> dict[str, Any]:
        """Material resource ops.

        Ops:
          • ``create``(path, vertex_program, fragment_program, vertex_constants,
            fragment_constants, samplers): build a new .material
          • ``set_constant``(path, name, value): set/override a constant
          • ``get``(path): read a material's full definition
        """
        return client.call("material_manage", {"op": op, "params": params or {}})

    @mcp.tool()
    def particlefx_manage(op: str, params: dict[str, Any] | None = None) -> dict[str, Any]:
        """Particle FX (.particlefx) resource ops.

        Ops: ``create``, ``set_emitter``, ``add_emitter``, ``apply_preset``
        (presets: ``rain``, ``snow``, ``smoke``, ``sparkle``, ``explosion``).
        """
        return client.call("particlefx_manage", {"op": op, "params": params or {}})

    @mcp.tool()
    def atlas_manage(op: str, params: dict[str, Any] | None = None) -> dict[str, Any]:
        """Texture atlas (.atlas) resource ops.

        Ops: ``create``, ``add_image``, ``add_animation``, ``set_margin``,
        ``get``, ``list_images``.
        """
        return client.call("atlas_manage", {"op": op, "params": params or {}})
