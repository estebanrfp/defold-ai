# Defold AI — Architecture

## High-level

```
┌─────────────────────────────────────────────────────────┐
│  MCP client (Claude Code / Codex / Antigravity / ...)    │
└────────────────────────┬────────────────────────────────┘
                         │ MCP stdio (JSON-RPC)
                         v
┌─────────────────────────────────────────────────────────┐
│  Python server (server/src/defold_ai)                   │
│   • FastMCP server                                      │
│   • Each @mcp.tool() forwards to /mcp/<tool>            │
│   • Discovers editor URL from env / file / probe        │
└────────────────────────┬────────────────────────────────┘
                         │ HTTP POST /mcp/<tool> + JSON
                         v
┌─────────────────────────────────────────────────────────┐
│  Defold editor (running)                                │
│   • Built-in http.server (Defold 1.10+)                 │
│   • plugin/mcp/mcp.editor_script registers routes       │
│   • Each route dispatches to a handler in handlers/     │
│   • Handlers call editor.transact + editor.tx.* + io.*  │
└─────────────────────────────────────────────────────────┘
```

## Why no WebSocket?

godot-ai uses a WebSocket bridge because Godot plugins don't have a built-in HTTP server — they need an external Python process to act as HTTP server and forward messages to the plugin via WebSocket.

Defold has a built-in HTTP server **inside the editor itself** (Defold 1.10+, see [`http.server` docs](https://defold.com/ref/stable/editor/#http.server)), with the `http.server.route(...)` API. We can register routes directly in the editor script, eliminating the WebSocket layer. The Python MCP server is just a stdio↔HTTP proxy.

This means **fewer moving parts** and **no extra port management** beyond what Defold already does.

## URL discovery

Defold assigns the HTTP server a dynamic port per editor instance. The Python server needs to know this URL. Three discovery paths in order:

1. **Environment variable** `DEFOLD_AI_URL` — explicit, highest priority
2. **`~/.defold_ai_url` file** — written by the editor script on load
3. **Port probing** on localhost — last resort

Mechanism (3) is unreliable; (2) is the default UX. The editor script does:

```lua
local home = os.getenv("HOME")
local f = io.open(home .. "/.defold_ai_url", "w")
f:write(http.server.url)
f:close()
```

Python client reads it on every request (cheap — single file read). If the user opens multiple Defold projects simultaneously, the most-recently-loaded editor "wins" the file.

## Editor script structure

```
plugin/mcp/
├── mcp.editor_script         # Entry point — registers routes + boots
├── lib/
│   └── util.lua              # Shared helpers (path normalize, error responses)
└── handlers/
    ├── editor.lua            # editor_state, screenshot, manage, reload
    ├── collection.lua        # collection_manage, get_hierarchy
    ├── gameobject.lua        # gameobject_create, set/get properties
    ├── component.lua         # component_add, remove
    ├── script.lua            # script_create, attach, patch, manage
    ├── resource.lua          # resource_manage + material/particlefx/atlas
    ├── filesystem.lua        # filesystem_manage
    ├── input_binding.lua     # input_binding_manage
    └── project.lua           # project_run, manage, logs_read
```

The entry point (`mcp.editor_script`) **must** end with `.editor_script` extension (not `.lua`) — Defold's editor auto-discovers `.editor_script` files anywhere in the project tree.

## Transaction-based mutations

Every editor mutation goes through `editor.transact({ ... })` with one or more `editor.tx.*` steps. This gives us:

- **Atomicity**: all steps succeed or none
- **Undo/redo**: each transaction is a single Ctrl+Z entry
- **Persistence**: `editor.save()` after the transaction flushes to disk

Example, from `handlers/gameobject.lua`:

```lua
editor.transact({
  editor.tx.add(collection, "children", {
    type = "go",
    id = "Player",
    position = { 0, 0, 0 },
    components = {
      { type = "model", id = "view",
        mesh = "/builtins/assets/meshes/cube.dae",
        material = "/builtins/materials/model.material" },
    }
  })
})
editor.save()
```

## Error responses

Handlers return Lua tables. The entry point's `dispatch()` wraps them:

- `ok=true` → HTTP 200 with the table as JSON
- `ok=false` + `error=CODE` + `message=...` → HTTP 200 with the structured error (the client unpacks it)
- Lua errors via `pcall` → HTTP 500 with `error=HANDLER_ERROR`
- Unknown tool → HTTP 404 with `error=UNKNOWN_TOOL`

Error codes:

| Code | Meaning |
|------|---------|
| `MISSING_PARAM` | Required parameter not provided |
| `INVALID_PARAM` | Parameter has wrong type or value |
| `NOT_FOUND` | Resource/path doesn't exist |
| `NOT_ALLOWED` | Operation not allowed in current editor state |
| `INVALID_PATH` | Path format invalid for the operation |
| `READ_ERROR` / `WRITE_ERROR` | Filesystem I/O failure |
| `OLD_TEXT_NOT_FOUND` | (script_patch) anchor text missing |
| `MULTIPLE_MATCHES` | (script_patch) anchor text appears > once |
| `NOT_IMPLEMENTED` | Defold API gap or planned feature |
| `UNKNOWN_OP` | Op string not recognized by a rollup tool |
| `UNKNOWN_TOOL` | Tool not registered |
| `HANDLER_ERROR` | Lua error inside a handler (with traceback in `message`) |
