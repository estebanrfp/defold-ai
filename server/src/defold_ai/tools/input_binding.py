"""Input binding tools — edit /input/game.input_binding."""

from __future__ import annotations

from typing import Any

from fastmcp import FastMCP

from defold_ai.client import DefoldEditorClient


def register(mcp: FastMCP, client: DefoldEditorClient) -> None:
    @mcp.tool()
    def input_binding_manage(op: str, params: dict[str, Any] | None = None) -> dict[str, Any]:
        """Input binding (.input_binding) management.

        Defold uses a single .input_binding file (default: ``/input/game.input_binding``)
        with four trigger categories: ``key_trigger``, ``mouse_trigger``,
        ``gamepad_trigger``, ``touch_trigger``.

        Ops:
          • ``list``(path=""): list all triggers in the binding file
          • ``add_key``(path, input, action): bind a key input
              (e.g. ``input="KEY_W"``, ``action="move_forward"``)
          • ``add_mouse``(path, input, action): bind a mouse button
              (e.g. ``input="MOUSE_BUTTON_LEFT"``)
          • ``add_gamepad``(path, input, action): bind a gamepad input
              (e.g. ``input="GAMEPAD_LSTICK_LEFT"``)
          • ``add_touch``(path, input, action): bind a touch input
          • ``remove``(path, input, kind): remove a trigger
          • ``set_active_binding``(path): set the project's active input
            binding file (game.project setting)

        ``path`` defaults to ``/input/game.input_binding`` if empty.
        """
        return client.call("input_binding_manage", {
            "op": op, "params": params or {},
        })
