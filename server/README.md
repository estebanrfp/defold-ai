# defold-ai server

Python MCP server that bridges MCP clients (Claude Code, Codex, etc.) to a running Defold editor via the editor's built-in HTTP server.

## Install

```bash
cd server
uv sync
```

## Run (stdio)

```bash
uv run defold-ai
```

## Configuration

The server discovers the running Defold editor's HTTP URL via (in order):

1. `DEFOLD_AI_URL` environment variable, e.g. `http://localhost:42137`
2. `~/.defold_ai_url` file (written by the editor script when it loads)
3. Fallback: tries common ports (9090, 9091...) — last resort

## Register with Claude Code

```bash
claude mcp add --scope user --transport stdio defold-ai \
  -- uv --directory /absolute/path/to/defold-ai/server run defold-ai
```

## Architecture

This server does **not** implement business logic. It receives MCP tool calls, forwards them as HTTP POST `/mcp/<tool>` to the Defold editor's HTTP server, and returns the JSON response. The real work happens in the editor script (`plugin/mcp/mcp.editor_script`).
