# Defold AI — Install Guide

## Prerequisites

- **Defold 1.10.0 or newer** ([download](https://defold.com/download/)) — the HTTP server API was added in 1.10
- **Python 3.10+** (Python 3.12 recommended)
- **uv** — `curl -LsSf https://astral.sh/uv/install.sh | sh`
- **An MCP client** — [Claude Code](https://docs.anthropic.com/en/docs/claude-code), [Codex](https://openai.com/index/codex/), [Antigravity](https://www.antigravity.dev/), etc.

## 1. Clone defold-ai

```bash
git clone https://github.com/estebanrfp/defold-ai.git
cd defold-ai
```

## 2. Install the editor script in your Defold project

Copy the `plugin/mcp/` folder into your Defold project's root:

```bash
# From the defold-ai directory, with YOUR_DEFOLD_PROJECT_PATH set:
cp -R plugin/mcp /path/to/your_defold_project/
```

Verify your project now contains:

```
your_defold_project/
├── game.project
├── mcp/
│   ├── mcp.editor_script    # Bridge entry point
│   ├── handlers/
│   │   ├── editor.lua
│   │   ├── collection.lua
│   │   ├── gameobject.lua
│   │   ├── component.lua
│   │   ├── script.lua
│   │   ├── resource.lua
│   │   ├── filesystem.lua
│   │   ├── input_binding.lua
│   │   └── project.lua
│   └── lib/
│       └── util.lua
└── ...
```

## 3. Open the project in Defold

Launch Defold, open your project. The editor auto-discovers `.editor_script` files on load. You should see in the editor's Console panel:

```
[defold-ai] editor script loaded — 28 tools registered
[defold-ai] HTTP server at http://localhost:42137
```

(Port is dynamic per Defold instance.)

The script also writes the URL to `~/.defold_ai_url` so the Python server can find it automatically.

## 4. Install the Python MCP server

```bash
cd defold-ai/server
uv sync
```

This creates a `.venv/` and installs FastMCP + httpx.

## 5. Register with your MCP client

### Claude Code

```bash
claude mcp add --scope user --transport stdio defold-ai \
  -- uv --directory /absolute/path/to/defold-ai/server run defold-ai
```

Verify:

```bash
claude mcp list
# → defold-ai: stdio (uv ...) - ✓ Connected
```

### Manual (any MCP client)

Add this to your client's MCP config:

```jsonc
{
  "mcpServers": {
    "defold-ai": {
      "command": "uv",
      "args": [
        "--directory", "/absolute/path/to/defold-ai/server",
        "run", "defold-ai"
      ]
    }
  }
}
```

## 6. Test it

In a Claude Code session inside any project:

> *"Verify the Defold AI connection."*

Claude should call `ping` and `editor_state`, returning the editor's version + HTTP URL.

> *"Show me the hierarchy of /main/main.collection."*

Claude should call `collection_get_hierarchy` and list the game objects.

## Troubleshooting

### `Cannot reach Defold editor at http://localhost:XXXXX`

- Confirm Defold is running with your project open.
- Check the editor's Console — does it show the `[defold-ai] HTTP server at ...` line?
- Try setting `DEFOLD_AI_URL=http://localhost:XXXXX` (with the actual port from the console).
- Verify `~/.defold_ai_url` exists and contains the right URL.

### Editor script not loading

- Confirm the file is **`mcp.editor_script`** (not `.lua`) — Defold won't auto-discover otherwise.
- Confirm it's inside the project root, anywhere is fine but commonly under `mcp/` or `editor/`.
- Use **Project → Reload Editor Scripts** in the Defold menu.
- Check the Console for Lua errors.

### `NOT_IMPLEMENTED` errors

Some tools are limited by Defold's current API. See [TOOLS.md](TOOLS.md) for status. These are tracked for v0.2.

### `connected pads: 0` style issues for gamepad

Defold uses its own input binding system. Use `input_binding_manage(op="add_gamepad", ...)` to bind gamepad inputs. See [Defold's input docs](https://defold.com/manuals/input/) for input constant names like `GAMEPAD_LSTICK_LEFT`.

## Uninstall

```bash
# Remove from MCP client
claude mcp remove defold-ai

# Remove from Defold project
rm -rf /path/to/your_defold_project/mcp

# Remove local server (optional)
rm -rf defold-ai/
```
