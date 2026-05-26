"""HTTP client that forwards MCP tool calls to the Defold editor."""

from __future__ import annotations

import os
from pathlib import Path
from typing import Any

import httpx


URL_ENV = "DEFOLD_AI_URL"
URL_FILE = Path.home() / ".defold_ai_url"
DEFAULT_PROBE_PORTS = (9090, 9091, 9092, 42137, 42138)


def discover_editor_url() -> str | None:
    """Locate the Defold editor's HTTP server URL.

    Resolution order:
      1. ``DEFOLD_AI_URL`` environment variable
      2. ``~/.defold_ai_url`` file (written by the editor script on load)
      3. Probe common ports on localhost — last resort
    """
    env_url = os.environ.get(URL_ENV)
    if env_url:
        return env_url.rstrip("/")
    if URL_FILE.exists():
        url = URL_FILE.read_text(encoding="utf-8").strip()
        if url:
            return url.rstrip("/")
    # Probe — best-effort, may return None if nothing answers
    for port in DEFAULT_PROBE_PORTS:
        url = f"http://localhost:{port}"
        try:
            r = httpx.get(f"{url}/mcp/ping", timeout=0.3)
            if r.status_code < 500:
                return url
        except (httpx.HTTPError, OSError):
            continue
    return None


class DefoldEditorClient:
    """Thin HTTP wrapper around the editor's ``/mcp/<tool>`` routes."""

    def __init__(self, base_url: str | None = None, timeout: float = 30.0) -> None:
        self._explicit_url = base_url
        self._timeout = timeout
        self._client = httpx.Client(timeout=timeout)

    def _resolve_url(self) -> str:
        url = self._explicit_url or discover_editor_url()
        if not url:
            raise RuntimeError(
                "Could not locate the Defold editor's HTTP server. "
                "Open a Defold project containing the mcp.editor_script, "
                "or set DEFOLD_AI_URL=http://localhost:<port>."
            )
        return url

    def call(self, tool: str, params: dict[str, Any] | None = None) -> dict[str, Any]:
        """POST /mcp/<tool> with JSON params, return parsed JSON response.

        Raises ``RuntimeError`` on connection failure with actionable guidance.
        """
        base = self._resolve_url()
        url = f"{base}/mcp/{tool}"
        try:
            r = self._client.post(url, json=params or {})
        except httpx.ConnectError as exc:
            raise RuntimeError(
                f"Cannot reach Defold editor at {base}. "
                "Is the editor running with mcp.editor_script loaded?"
            ) from exc
        if r.status_code >= 400:
            try:
                return r.json()  # editor returns structured errors
            except ValueError:
                pass
            raise RuntimeError(f"Editor responded {r.status_code}: {r.text[:300]}")
        return r.json()

    def ping(self) -> dict[str, Any]:
        return self.call("ping", {})

    def close(self) -> None:
        self._client.close()
