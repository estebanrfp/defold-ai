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

        Ops:
          • ``create``(path, images=[], margin=0, extrude_borders=2, inner_padding=0):
            Create a new .atlas. Pass ``images=["/path/a.png", ...]`` to seed.
          • ``add_image``(path, image, sprite_trim_mode="SPRITE_TRIM_MODE_OFF"):
            Append one image. Idempotent — no-op if already present.
          • ``remove_image``(path, image): Remove an image entry.
          • ``list_images``(path): Return all image entries in order.
          • ``add_animation``(path, id, images=[...], fps=30, playback="PLAYBACK_LOOP_FORWARD"):
            Bundle multiple images into a named flipbook animation.
          • ``set_margin``(path, margin): Edit the top-level margin field.
          • ``get``(path): Full atlas summary (margin / extrude / images).
        """
        return client.call("atlas_manage", {"op": op, "params": params or {}})

    @mcp.tool()
    def tilesource_manage(op: str, params: dict[str, Any] | None = None) -> dict[str, Any]:
        """Tile source (.tilesource) resource ops.

        Ops:
          • ``create``(path, image, tile_width=32, tile_height=32,
                     tile_margin=0, tile_spacing=0, extrude_borders=2,
                     material_tag="tile",
                     animations=[{id, start_tile, end_tile?, playback?, fps?}, ...]):
            Create a .tilesource pointing at a PNG tilesheet. Each animation
            entry becomes a named tile alias (e.g. ``"grass" → tile 1``).
        """
        return client.call("tilesource_manage", {"op": op, "params": params or {}})

    @mcp.tool()
    def tilemap_manage(op: str, params: dict[str, Any] | None = None) -> dict[str, Any]:
        """Tilemap (.tilemap) resource ops.

        Ops:
          • ``create``(path, tile_set, layer_id="ground",
                     material="/builtins/materials/tile_map.material",
                     cells=[{x, y, tile, h_flip?, v_flip?, rotate90?}, ...]):
            Pre-bake a .tilemap with explicit cells. Note: tile indices are
            0-based here (0 = first tile in the tilesource). This avoids the
            common "Out of tiles to render" / "tile out of range" pitfalls of
            mutating an empty .tilemap at runtime.
        """
        return client.call("tilemap_manage", {"op": op, "params": params or {}})
