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
        """Material (.material) resource ops with curated presets.

        Ops:
          • ``create``(path, vertex_program?, fragment_program?):
            Minimal create — wires VP/FP only (no constants/samplers).
            Kept for back-compat; prefer ``create_full`` or ``apply_preset``.
          • ``create_full``(path, vertex_program, fragment_program, name?,
            tags=["model"], vertex_space?, vertex_constants=[], fragment_constants=[],
            samplers=[], max_page_count=0):
            Build a complete .material from structured input. Constants are
            dicts ``{name, type?, value: {x, y, z, w}}``; samplers
            ``{name, wrap_u?, wrap_v?, filter_min?, filter_mag?, max_anisotropy?}``.
          • ``apply_preset``(path, preset, overrides={}):
            Generate a ready-to-use .material from a curated library. Built-in
            presets: ``model_lit_tint``, ``model_unlit_tint``, ``sky_gradient``
            (auto-creates ``/assets/shaders/sky.{vp,fp}`` if missing),
            ``gui_basic``, ``sprite_basic``, ``tilemap_basic``. The
            ``overrides`` table is deep-merged into the preset blueprint, so
            you can tweak just the tint or one constant without re-specifying.
          • ``set_constant``(path, name, value, kind="fragment", type="CONSTANT_TYPE_USER"):
            Edit a single constant in place. Replaces the block if present,
            appends otherwise. ``value`` is a vec4 dict.
          • ``get``(path):
            Inspect a .material — returns name, tags, vp/fp, vertex_space,
            vertex_constants, fragment_constants, samplers.
          • ``list_presets``():
            Enumerate available preset names.
        """
        return client.call("material_manage", {"op": op, "params": params or {}})

    @mcp.tool()
    def particlefx_manage(op: str, params: dict[str, Any] | None = None) -> dict[str, Any]:
        """Particle FX (.particlefx) resource ops.

        Ops:
          • ``create``(path): write a minimal one-emitter `.particlefx`.
          • ``apply_preset``(path, preset, overrides=None): generate a
            ready-to-render `.particlefx` from a curated preset library.
            Built-in presets: ``rain``, ``snow``, ``smoke``, ``sparkle``,
            ``explosion``. The shared white tilesource is auto-created at
            ``/assets/particles/white.tilesource`` (needs an existing
            ``/assets/images/white.png`` or ``DEFOLD_AI_WHITE_IMAGE`` env var).
            ``overrides`` lets you tweak any preset field without writing
            the whole `.particlefx` from scratch.
          • ``list_presets``(): return the available preset names.
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
    def render_manage(op: str, params: dict[str, Any] | None = None) -> dict[str, Any]:
        """Render pipeline (.render + .render_script) authoring.

        Defold's default render script does opaque models → tiles → particles → GUI.
        For 3D projects that need a sky pass, depth tweaks, or any pipeline
        customisation, this tool generates the pair from a small DSL.

        Ops:
          • ``list_presets``(): enumerate built-in presets.
          • ``create``(path, preset?, passes?, activate=False):
            Generate a `.render_script` + `.render` pair at `path` (the
            extension is added if missing). Pick a `preset`
            (``default_3d`` | ``default_3d_with_sky`` | ``default_2d``)
            or pass a custom `passes` list:
            ``[{predicate, cull?: "back"|"front"|"none", depth_write?,
                depth_test?, blend?, projection?: "camera"|"ortho_window",
                custom_setup?: "raw lua"}]``
            When ``activate=True``, also rewrites
            ``[bootstrap] render = ...`` in game.project so the new pipeline
            is picked up on the next build.
        """
        return client.call("render_manage", {"op": op, "params": params or {}})

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
