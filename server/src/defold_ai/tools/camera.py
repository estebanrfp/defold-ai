"""Camera tools — wraps Defold's `camera` component + common follow rigs."""

from __future__ import annotations

from typing import Any

from fastmcp import FastMCP

from defold_ai.client import DefoldEditorClient


def register(mcp: FastMCP, client: DefoldEditorClient) -> None:
    @mcp.tool()
    def camera_manage(op: str, params: dict[str, Any] | None = None) -> dict[str, Any]:
        """Camera (.go + camera component) authoring with follow-rig presets.

        Defold's camera lives as a component inside a GO; the render script
        binds it via ``camera.get_cameras()``. This tool generates the
        camera GO and the optional follow script in one call.

        Ops:
          • ``list_presets``(): enumerate built-in presets with descriptions.
          • ``create``(path, fov=1.2566, near_z=0.1, far_z=500,
            orthographic=False, orthographic_zoom=1.0, auto_aspect_ratio=True):
            Generate a bare camera .go with one camera component embedded.
            No follow script. Use ``apply_preset`` for rigs.
          • ``apply_preset``(path, preset, camera={}, overrides={}):
            Generate camera .go + matching script. Presets:
              - ``perspective_basic`` / ``orthographic_basic`` — bare camera
              - ``follow_3d`` — third-person orbital (mouse yaw/pitch, parent
                this GO to your target). Script exposes ``spring_len``,
                ``height_offset``, ``pitch_min/max`` as go.properties.
              - ``follow_2d`` — 2D camera that lerps to a ``target`` URL.
                Script exposes ``target`` (default ``"/player"``) and ``lerp``.
            ``camera`` overrides the camera component opts (fov, far_z, etc).
        """
        return client.call("camera_manage", {"op": op, "params": params or {}})
