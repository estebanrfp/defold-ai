# Defold AI — Tool Reference

All tools forward to a Defold editor's HTTP server via `POST /mcp/<tool>`. Each tool returns a JSON response with an `ok` field plus tool-specific data, or `{ ok: false, error, message }` on failure.

> **Latest:** v0.10.0 — `editor_screenshot` real, `gameobject_find` paginated, `camera_manage` with follow rigs, `render_manage` DSL, `material_manage(create_full + apply_preset)`, `particlefx_manage(apply_preset)` library. See [CHANGELOG.md](../CHANGELOG.md) for the version-by-version detail.

## Tool index

### Editor

| Tool | Purpose | Status |
|------|---------|--------|
| `ping` | Liveness check | ✅ |
| `editor_state` | Version, HTTP URL, readiness | ✅ |
| `editor_screenshot` | Capture game/editor window (macOS via `screencapture`) | ✅ macOS (needs Screen Recording permission) |
| `editor_manage` | state / selection / logs_clear | ⚠️ Partial (Defold gap) |
| `editor_reload_plugin` | Invalidate handler require-cache | ⚠️ Unreliable; restart for entry-point edits |

### Collection (Defold's "scene")

| Tool | Purpose | Status |
|------|---------|--------|
| `collection_manage` | create / open / save / add_instance / add_embedded / add_collection_instance / set_parent / remove_instance (auto-cleans `children:` refs) | ✅ |
| `collection_get_hierarchy` | Walk the game-object tree (paginated) | ✅ |
| `collection_open` | Open .collection | ✅ |
| `collection_save` | `editor.save()` | ✅ |

### Game objects

| Tool | Purpose | Status |
|------|---------|--------|
| `gameobject_create` | Add GO to an open collection (embedded or referenced) | ✅ |
| `gameobject_set_property` | `editor.tx.set` | ✅ |
| `gameobject_get_properties` | Bulk property read | ✅ |
| `gameobject_find` | Paginated search by `name_pattern` / `type_filter` / `component_type` + `max_depth` / `offset` / `limit`; returns `id, type, path, depth, component_types` per match | ✅ |
| `gameobject_manage` | `create_file` (standalone `.go` with structured embedded components) / delete / get_children (+ planned duplicate / rename / reparent) | ✅ partial |

### Components

| Tool | Purpose | Status |
|------|---------|--------|
| `component_add` | Add component to GO (script / sprite / model / mesh / sound / particlefx / factory / camera / collisionobject / label / tilemap) | ✅ |
| `component_remove` | Remove by id | ✅ |
| `component_list_types` | Enumerate supported types | ✅ |

### Scripts

| Tool | Purpose | Status |
|------|---------|--------|
| `script_create` | Create `.script` / `.gui_script` / `.render_script` / `.lua` | ✅ |
| `script_attach` | Attach `.script` to GO | ✅ |
| `script_patch` | Anchor-based string-replace on any Defold text resource (`.script`, `.collection`, `.go`, `.material`, `.atlas`, `.tilesource`, `.tilemap`, `.gui`, ...) | ✅ |
| `script_manage` | read / detach / find_symbols | ✅ |

### Resources

| Tool | Purpose | Status |
|------|---------|--------|
| `resource_manage` | Generic file resource `create` / `read` / `write` / `delete` (idempotent) | ✅ |
| `material_manage` | `create_full` (structured constants/samplers/tags) / `apply_preset` (`model_lit_tint`, `model_unlit_tint`, `sky_gradient`, `gui_basic`, `sprite_basic`, `tilemap_basic`) / `set_constant` / `get` / `list_presets` | ✅ |
| `render_manage` | `create` (`.render` + `.render_script` from a passes-DSL with `activate=True` option) / `list_presets` (`default_3d`, `default_3d_with_sky`, `default_2d`) | ✅ |
| `particlefx_manage` | `create` / `apply_preset` (`rain`, `snow`, `smoke`, `sparkle`, `explosion`) / `list_presets` | ✅ |
| `camera_manage` | `create` (bare camera GO) / `apply_preset` (`perspective_basic`, `orthographic_basic`, `follow_3d`, `follow_2d`) — generates GO + follow `.script` together | ✅ |
| `atlas_manage` | `create` / `add_image` / `remove_image` / `list_images` / `add_animation` / `set_margin` / `get` | ✅ |
| `tilesource_manage` | `create` `.tilesource` with per-tile named animations | ✅ |
| `tilemap_manage` | `create` `.tilemap` with pre-baked cells | ✅ |
| `filesystem_manage` | `read_text` / `write_text` / `mkdir` / `rm` / `search` / `reimport` | ✅ |

### Input

| Tool | Purpose | Status |
|------|---------|--------|
| `input_binding_manage` | Edit `game.input_binding` — `list` / `add_key` / `add_mouse` / `add_gamepad` / `add_touch` | ✅ |

### Project

| Tool | Purpose | Status |
|------|---------|--------|
| `project_run` | Headless `bob` build + spawn `dmengine` (stdout/stderr → `./dmengine.log`) | ✅ |
| `project_manage` | `stop` (SIGTERMs `dmengine`) / `build` (structured `errors[]` + `output_tail`) / `settings_get` / `settings_set` (INI-aware) / `info` | ✅ |
| `logs_read` | Editor logs + `dmengine.log` tail when `source="game"` | ✅ |
| `batch_execute` | Sequence of tool calls in one round-trip | ✅ |

## Status legend

- ✅ — Fully functional
- ⚠️ — Partial; returns `NOT_IMPLEMENTED` with a clear workaround
- ❌ — Blocked by Defold's editor scripting API

## Defold API limitations

Defold's editor script API (as of 1.12.x) is **less comprehensive than Godot's plugin API**. The following Defold gaps still affect the surface:

1. **No first-party editor-side capture API** — `editor_screenshot` shells out to macOS `screencapture` (needs Screen Recording permission). A future iteration will inject a `game_helper.lua` at `project_run` time to expose a capture endpoint from inside the running game.
2. **`editor.bob` returns opaque errors** — defold-ai works around this by shelling out to `bob.jar` (auto-discovered) for the build and parsing the bob output. See `project_run` / `project_manage(op="build")`.
3. **No selection API** — can't read or set the currently-selected nodes.
4. **No console clear** — print is append-only.
5. **`editor_reload_plugin` is unreliable** — Defold appears to cache compiled handler bytecode past `package.loaded` invalidation. Restart the editor when changing handler files; runtime handler edits *sometimes* take effect on the next request, sometimes don't.

## End-to-end example: build a 3D scene in ~10 MCP calls

This is what defold-ai is for. Every step below is one MCP tool call — no manual file editing, no clicking around the editor UI.

```jsonc
// 1. Sanity check
POST /mcp/ping
→ { "ok": true, "version": "0.10.0" }

// 2. A custom render pipeline that draws a sky pass first
POST /mcp/render_manage
{ "op": "create",
  "params": { "path": "/main/game",
              "preset": "default_3d_with_sky",
              "activate": true } }
→ { "ok": true, "render": "/main/game.render",
    "script": "/main/game.render_script",
    "passes": 6, "activated": true }

// 3. Procedural sky gradient material (auto-writes the shaders too)
POST /mcp/material_manage
{ "op": "apply_preset",
  "params": { "path": "/assets/materials/sky.material",
              "preset": "sky_gradient" } }

// 4. Lit-tint material for voxel blocks
POST /mcp/material_manage
{ "op": "apply_preset",
  "params": { "path": "/assets/materials/block.material",
              "preset": "model_lit_tint" } }

// 5. A reusable block prototype — cube mesh + collision + tint script
POST /mcp/gameobject_manage
{ "op": "create_file",
  "params": { "path": "/world/block.go",
              "components": [
                { "id": "script",
                  "component": "/world/block.script" },
                { "id": "model", "type": "model",
                  "data": { "mesh": "/builtins/assets/meshes/cube.dae",
                            "material": "/assets/materials/block.material",
                            "textures": "/assets/images/white.png" } },
                { "id": "collision", "type": "collisionobject",
                  "data": { "type": "COLLISION_OBJECT_TYPE_STATIC",
                            "mass": 0, "group": "world", "mask": "player",
                            "embedded_collision_shape": {
                              "shapes": [{ "shape_type": "TYPE_BOX",
                                           "index": 0, "count": 3,
                                           "position": {"x":0,"y":0,"z":0},
                                           "rotation": {"x":0,"y":0,"z":0,"w":1} }],
                              "data": [0.5, 0.5, 0.5] } } }
              ] } }

// 6. Third-person orbital camera + script in one call
POST /mcp/camera_manage
{ "op": "apply_preset",
  "params": { "path": "/main/camera.go", "preset": "follow_3d" } }

// 7. Rain particle system (procedural — emits down at 400/s for ~1s lifetime)
POST /mcp/particlefx_manage
{ "op": "apply_preset",
  "params": { "path": "/world/rain.particlefx", "preset": "rain" } }

// 8. WASD input bindings
POST /mcp/input_binding_manage
{ "op": "add_key",
  "params": { "path": "/input/game.input_binding",
              "input": "KEY_W", "action": "move_up" } }
// ... add_key for KEY_S / KEY_A / KEY_D / KEY_SPACE etc.

// 9. Bump physics + draw call budgets before we render thousands of blocks
POST /mcp/project_manage
{ "op": "settings_set",
  "params": { "key": "model.max_count", "value": 8000 } }
POST /mcp/project_manage
{ "op": "settings_set",
  "params": { "key": "graphics.max_draw_calls", "value": 8192 } }

// 10. Headless build + launch dmengine
POST /mcp/project_run
→ { "ok": true, "stage": "launched", "engine": "/.../dmengine" }

// 11. Tail the running game log
POST /mcp/logs_read
{ "source": "game", "count": 20 }

// 12. (macOS) Screenshot the running game window
POST /mcp/editor_screenshot
{ "target": "game" }
→ { "ok": true, "target": "game", "mode": "window",
    "path": "/tmp/defold_ai_screenshot.png", "size": 42117 }
```

The first time this runs end-to-end on a clean project it takes ~3 seconds (build is ~1 s; everything else is sub-100 ms per call).
