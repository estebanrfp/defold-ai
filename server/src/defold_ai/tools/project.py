"""Project-level tools: build, run, settings, logs."""

from __future__ import annotations

from typing import Any

from fastmcp import FastMCP

from defold_ai.client import DefoldEditorClient


def register(mcp: FastMCP, client: DefoldEditorClient) -> None:
    @mcp.tool()
    def project_run(mode: str = "main", scene: str = "", variant: str = "debug") -> dict[str, Any]:
        """Headless build + launch dmengine for the running game.

        Pipeline:
          1. Locate Defold's bundled JDK + bob.jar (auto-discovery covers macOS,
             Linux, Windows; override with ``DEFOLD_AI_JAVA`` / ``DEFOLD_AI_BOB_JAR``).
          2. Run ``bob --variant=<variant> build`` and parse its output for
             compile errors — returns a structured ``BUILD_ERROR`` with
             ``errors=[{file,line,message}, ...]`` if any.
          3. On success, spawn dmengine detached; stdout/stderr go to
             ``./dmengine.log`` in the project. Tail via ``logs_read(source="game")``.

        Args:
            mode: reserved — accepted for symmetry with future "custom" launches.
            scene: collection path (currently unused; bob always builds the project root).
            variant: ``"debug"`` (default) or ``"release"``.
        """
        return client.call("project_run", {"mode": mode, "scene": scene, "variant": variant})

    @mcp.tool()
    def project_manage(op: str, params: dict[str, Any] | None = None) -> dict[str, Any]:
        """Project lifecycle and settings (game.project).

        Ops:
          • ``stop``(): SIGTERM any running dmengine processes (idempotent).
          • ``build``(variant="debug"): headless bob build with structured
            ``BUILD_ERROR`` output — includes ``errors=[{file,line,message}]``
            and a tail of the bob output for context.
          • ``settings_get``(key): read a game.project setting (e.g.
            ``"display.width"``, ``"bootstrap.main_collection"``).
          • ``settings_set``(key, value): edit game.project in place. Creates
            the section if missing; replaces existing key; otherwise appends.
            Preserves the rest of the file byte-for-byte.
          • ``info``(): project metadata (root, version, discovered toolchain).
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
