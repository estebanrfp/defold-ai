"""Editor-level tools: state, screenshot, manage, reload."""

from __future__ import annotations

from typing import Any

from fastmcp import FastMCP

from defold_ai.client import DefoldEditorClient


def register(mcp: FastMCP, client: DefoldEditorClient) -> None:
    @mcp.tool()
    def editor_state() -> dict[str, Any]:
        """Get current Defold editor state: version, readiness, current
        collection, play state. Useful as a connection sanity check."""
        return client.call("editor_state", {})

    @mcp.tool()
    def editor_screenshot(source: str = "viewport", max_resolution: int = 800) -> dict[str, Any]:
        """Capture a screenshot of the editor scene view or the running game.

        Args:
            source: ``"viewport"`` (editor scene) or ``"game"`` (running game)
            max_resolution: longest-edge resolution. Default 800.
        """
        return client.call("editor_screenshot", {
            "source": source,
            "max_resolution": max_resolution,
        })

    @mcp.tool()
    def editor_manage(op: str, params: dict[str, Any] | None = None) -> dict[str, Any]:
        """Editor rollup: state | selection_get | selection_set | quit | logs_clear.

        Args:
            op: operation name
            params: per-op parameters (see docs/TOOLS.md)
        """
        return client.call("editor_manage", {"op": op, "params": params or {}})

    @mcp.tool()
    def editor_reload_plugin() -> dict[str, Any]:
        """Reload the Defold AI editor script (after editing handlers)."""
        return client.call("editor_reload_plugin", {})

    @mcp.tool()
    def ping() -> dict[str, Any]:
        """Simple liveness check — returns ``{"ok": true, "version": ...}``."""
        return client.call("ping", {})
