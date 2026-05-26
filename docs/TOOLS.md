# Defold AI — Tool Reference

All tools forward to a Defold editor's HTTP server via `POST /mcp/<tool>`. Each tool returns a JSON response with an `ok` field plus tool-specific data, or `{ ok: false, error, message }` on failure.

## Tool index

### Editor

| Tool | Purpose | Status |
|------|---------|--------|
| `ping` | Liveness check | ✅ |
| `editor_state` | Version, HTTP URL, readiness | ✅ |
| `editor_screenshot` | Editor / game screenshot | ❌ Defold API gap |
| `editor_manage` | state, selection, logs_clear | ⚠️ Partial |
| `editor_reload_plugin` | Hot-reload the editor script | ⚠️ Manual via Project > Reload Editor Scripts |

### Collection (Defold's "scene")

| Tool | Purpose | Status |
|------|---------|--------|
| `collection_manage` | create / open / save / add_instance / add_embedded / remove_instance | ✅ |
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
| `gameobject_manage` | create_file / delete / get_children (+ planned duplicate/rename/reparent) | ✅ |

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
| `resource_manage` | Generic file resource create/read/write/delete | ✅ |
| `material_manage` | .material create + edit | ⚠️ create only |
| `particlefx_manage` | .particlefx create + presets | ⚠️ create only |
| `atlas_manage` | .atlas create / add_image / remove_image / list_images / add_animation / set_margin / get | ✅ |
| `tilesource_manage` | .tilesource create with per-tile animations | ✅ |
| `tilemap_manage` | .tilemap create with pre-baked cells | ✅ |
| `filesystem_manage` | read_text / write_text / mkdir / rm | ✅ |

### Input

| Tool | Purpose | Status |
|------|---------|--------|
| `input_binding_manage` | Edit `game.input_binding` (list, add_key, add_mouse, add_gamepad, add_touch) | ✅ |

### Project

| Tool | Purpose | Status |
|------|---------|--------|
| `project_run` | Headless bob build + launch dmengine (stdout/stderr → ./dmengine.log) | ✅ |
| `project_manage` | stop / build (structured errors) / settings_get / settings_set / info | ✅ |
| `logs_read` | Editor logs + tail of dmengine.log when `source="game"` | ✅ |
| `batch_execute` | Sequence of tool calls in one round-trip (proper routing) | ✅ |

## Status legend

- ✅ — Fully functional
- ⚠️ — Partial; returns `NOT_IMPLEMENTED` with a workaround for missing ops
- ❌ — Blocked by Defold's editor scripting API

## Defold API limitations vs. Godot

Defold's editor script API (as of 1.12.x) is **less comprehensive than Godot's plugin API**. The following are Defold-side gaps that still block parity:

1. **No editor screenshot API** — must run the game and screenshot externally.
2. **Programmatic Build/Run not exposed by `editor.*`** — defold-ai works around this by shelling out to `bob.jar` (auto-discovered) for the build and spawning `dmengine` for the run; see `project_run` / `project_manage(op="build")`.
3. **No selection API** — can't read or set the currently-selected nodes.
4. **No console clear** — print is append-only.
5. **No live game introspection** during runtime — Defold's debug protocol must be used separately.

These will be addressed as Defold's API expands. For now we expose what's possible and provide clear `NOT_IMPLEMENTED` errors with workarounds for what isn't.

## End-to-end example: a top-down player + tilemap world

This walks the AppleGame port (see `examples/applegame`) — everything below is one MCP-only flow with no manual file editing.

```jsonc
// 1. Verify editor is reachable
POST /mcp/ping → { "ok": true, "version": "0.2.0" }

// 2. Create the spritesheet atlas
POST /mcp/atlas_manage
{ "op": "create",
  "params": { "path": "/assets/sprites.atlas",
              "images": ["/assets/images/player.png",
                         "/assets/images/tree.png",
                         "/assets/images/apple.png"] } }

// 3. Create the tile source (5 named tiles in a single sheet)
POST /mcp/tilesource_manage
{ "op": "create",
  "params": { "path": "/assets/terrain.tilesource",
              "image": "/assets/images/tiles.png",
              "tile_width": 32, "tile_height": 32,
              "animations": [{"id":"grass","start_tile":1},
                             {"id":"dirt","start_tile":2},
                             {"id":"stone","start_tile":3},
                             {"id":"water","start_tile":4}] } }

// 4. Pre-bake the world map (cells generated client-side)
POST /mcp/tilemap_manage
{ "op": "create",
  "params": { "path": "/world/terrain.tilemap",
              "tile_set": "/assets/terrain.tilesource",
              "cells": [{"x":0,"y":0,"tile":0}, /* ... thousands ... */] } }

// 5. Configure inputs
POST /mcp/input_binding_manage
{ "op": "add_key",
  "params": { "path": "/input/game.input_binding",
              "input": "KEY_W", "action": "move_up" } }
// ...repeat for KEY_S / KEY_A / KEY_D / arrows / space

// 6. Create the player script
POST /mcp/script_create
{ "path": "/player/player.script",
  "content": "go.property(\"speed\", 220)\n..." }

// 7. Create the player .go (sprite + collisionobject + script reference)
POST /mcp/gameobject_manage
{ "op": "create_file",
  "params": { "path": "/player/player.go",
              "components": [
                {"id":"script", "component":"/player/player.script"},
                {"id":"sprite", "type":"sprite",
                 "data": {"default_animation":"player",
                          "material":"/builtins/materials/sprite.material",
                          "blend_mode":"BLEND_MODE_ALPHA",
                          "textures":[{"sampler":"texture_sampler",
                                       "texture":"/assets/sprites.atlas"}]}},
                {"id":"collision","type":"collisionobject",
                 "data": {"type":"COLLISION_OBJECT_TYPE_KINEMATIC",
                          "group":"player","mask":"world"}}
              ] } }

// 8. Wire player + world + camera into main.collection
POST /mcp/collection_manage
{ "op": "add_instance",
  "params": { "path": "/main/main.collection",
              "id": "player", "prototype": "/player/player.go" } }

// 9. Bump the tile budget for our large map
POST /mcp/project_manage
{ "op": "settings_set",
  "params": { "key": "tilemap.max_tile_count", "value": 10000 } }

// 10. Build + run
POST /mcp/project_run
→ { "ok": true, "stage": "launched", "engine": "/.../dmengine", ... }

// 11. Tail the game log
POST /mcp/logs_read { "source": "game", "count": 20 }
```
