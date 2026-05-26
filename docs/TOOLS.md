# Defold AI — Tool Reference

All tools forward to a Defold editor's HTTP server via `POST /mcp/<tool>`. Each tool returns a JSON response with an `ok` field plus tool-specific data, or `{ ok: false, error, message }` on failure.

## Tool index

### Editor

| Tool | Purpose | Status |
|------|---------|--------|
| `ping` | Liveness check | ✅ |
| `editor_state` | Version, HTTP URL, readiness | ✅ |
| `editor_screenshot` | Editor / game screenshot | ⚠️ Defold API gap |
| `editor_manage` | state, selection, logs_clear | ⚠️ Partial |
| `editor_reload_plugin` | Hot-reload the editor script | ⚠️ Auto in 1.10+ |

### Collection (Defold's "scene")

| Tool | Purpose | Status |
|------|---------|--------|
| `collection_manage` | create / save / open | ✅ create |
| `collection_get_hierarchy` | Walk the game-object tree | ✅ |
| `collection_open` | Open .collection | ✅ |
| `collection_save` | `editor.save()` | ✅ |

### Game objects

| Tool | Purpose | Status |
|------|---------|--------|
| `gameobject_create` | Add GO to collection (embedded or referenced) | ✅ |
| `gameobject_set_property` | `editor.tx.set` | ✅ |
| `gameobject_get_properties` | Bulk property read | ✅ |
| `gameobject_find` | Search by name/type | ✅ basic |
| `gameobject_manage` | delete, duplicate, rename, reparent | ✅ delete |

### Components

| Tool | Purpose | Status |
|------|---------|--------|
| `component_add` | Add component to GO (script/sprite/model/mesh/sound/particlefx/factory/camera/collisionobject/label/tilemap) | ✅ |
| `component_remove` | Remove by id | ✅ |
| `component_list_types` | Enumerate supported types | ✅ |

### Scripts

| Tool | Purpose | Status |
|------|---------|--------|
| `script_create` | Create .script / .gui_script / .render_script / .lua | ✅ |
| `script_attach` | Attach .script to GO | ✅ |
| `script_patch` | Anchor-based string-replace edit | ✅ |
| `script_manage` | read / detach / find_symbols | ✅ |

### Resources

| Tool | Purpose | Status |
|------|---------|--------|
| `resource_manage` | Generic file resource create/read/write | ✅ |
| `material_manage` | .material create + edit | ⚠️ create only |
| `particlefx_manage` | .particlefx create + presets | ⚠️ create only |
| `atlas_manage` | .atlas create + add images | ⚠️ create only |
| `filesystem_manage` | read_text / write_text / mkdir / rm | ✅ |

### Input

| Tool | Purpose | Status |
|------|---------|--------|
| `input_binding_manage` | Edit `game.input_binding` | ✅ add only |

### Project

| Tool | Purpose | Status |
|------|---------|--------|
| `project_run` | Build & run | ⚠️ Defold API gap (manual F5) |
| `project_manage` | stop / build / settings | ⚠️ Partial |
| `logs_read` | Editor / game logs | ⚠️ Defold-AI-only logs |
| `batch_execute` | Sequence of tool calls in one round-trip | ⚠️ Stub |

## Status legend

- ✅ — Fully functional
- ⚠️ — Limited by Defold's current editor scripting API or planned for v0.2
- ❌ — Blocked, no API path

## Defold API limitations vs. Godot

Defold's editor script API (as of 1.10.x) is **less comprehensive than Godot's plugin API**. The following are Defold-side gaps that block parity:

1. **No editor screenshot API** — must run game and screenshot externally
2. **No programmatic Build/Run** — `editor.bob()` works for headless builds, but launching the game from a script isn't exposed
3. **No selection API** — can't read or set the currently-selected nodes
4. **No console clear** — print is append-only
5. **No live game introspection** during runtime — must use Defold's debug protocol separately

These will be addressed as Defold's API expands. For now we expose what's possible and provide clear `NOT_IMPLEMENTED` errors with workarounds for what isn't.

## Example: creating a cube via tool calls

```jsonc
// 1. Verify editor is reachable
POST /mcp/ping
→ { "ok": true, "version": "0.1.0" }

// 2. Create a game object in /main/main.collection
POST /mcp/gameobject_create
{
  "collection": "/main/main.collection",
  "id": "Cube1",
  "position": { "x": 0, "y": 0, "z": 0 }
}
→ { "ok": true, "path": "/main/main.collection!/Cube1", "id": "Cube1" }

// 3. Add a model component to it
POST /mcp/component_add
{
  "gameobject": "/main/main.collection!/Cube1",
  "type": "model",
  "id": "view",
  "properties": {
    "mesh": "/builtins/assets/meshes/cube.dae",
    "material": "/builtins/materials/model.material"
  }
}
→ { "ok": true, "gameobject": "...", "component_id": "view" }

// 4. Save
POST /mcp/collection_save
→ { "ok": true }
```
