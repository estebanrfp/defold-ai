"""Project-level tools: build, run, settings, logs."""

from __future__ import annotations

from typing import Any

from fastmcp import FastMCP

from defold_ai.client import DefoldEditorClient


def register(mcp: FastMCP, client: DefoldEditorClient) -> None:
    @mcp.tool()
    def project_run(mode: str = "main", scene: str = "") -> dict[str, Any]:
        """Build and run the project.

        Defold's primary launch path is the editor's Build menu. This tool
        triggers that programmatically via the editor command system.

        Args:
            mode: ``"main"`` (run the main collection) | ``"current"`` (run
                the currently edited collection) | ``"custom"`` (run a
                specific collection — requires ``scene``)
            scene: collection path for ``mode="custom"``
        """
        return client.call("project_run", {"mode": mode, "scene": scene})

    @mcp.tool()
    def project_manage(op: str, params: dict[str, Any] | None = None) -> dict[str, Any]:
        """Project lifecycle and settings (game.project).

        Ops:
          • ``stop``(): stop the running game (idempotent)
          • ``build``(): rebuild without running
          • ``settings_get``(key): read a game.project setting (e.g.
            ``"display.width"``, ``"bootstrap.main_collection"``)
          • ``settings_set``(key, value): write a game.project setting
          • ``info``(): project metadata (name, version, paths)
        """
        return client.call("project_manage", {"op": op, "params": params or {}})

    @mcp.tool()
    def logs_read(
        source: str = "editor",
        count: int = 50,
        offset: int = 0,
    ) -> dict[str, Any]:
        """Read recent log lines from the editor console or running game.

        Sources:
          • ``"editor"``: editor console (Lua print, errors, build output)
          • ``"game"``: stdout/stderr from the running game
          • ``"all"``: both, with a ``source`` field per line

        Args:
            count: max lines to return. Default 50.
            offset: lines to skip from the most recent.
        """
        return client.call("logs_read", {
            "source": source, "count": count, "offset": offset,
        })

    @mcp.tool()
    def batch_execute(steps: list[dict[str, Any]]) -> dict[str, Any]:
        """Run a sequence of tool calls in one round-trip. Each step is
        ``{tool: str, params: dict}``. Stops on first failure unless
        ``params.ignore_errors=True`` is set on individual steps."""
        return client.call("batch_execute", {"steps": steps})
