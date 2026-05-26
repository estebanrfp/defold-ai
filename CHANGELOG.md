# Changelog

All notable changes to **defold-ai** are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)
and this project follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).
Each release maps 1:1 to a git tag once published — `git log <prev>..<next>` is
the source of truth, this file is the human-readable summary.

## [Unreleased]

Planned next:

- `camera_manage` — abstraction over `camera` component + follow rigs
  (`follow_2d` / `follow_3d` orbital).
- `editor_screenshot` — investigating the `dmengine` debug HTTP API.
- `gameobject_manage(duplicate / rename / reparent)`.
- `collection_manage(save_as / get_roots)`.
- A reliable hot-reload path (`editor_reload_plugin` invalidates
  `package.loaded` but Defold keeps a bytecode cache — workaround is a
  full editor restart).
- Windows paths for `find_defold_toolchain`.
- `examples/applegame` runnable demo.

## [0.7.0] — 2026-05-27

Render pipeline authoring. Stops users from copy-pasting Defold's
`builtins/render/default.render_script` every time they need a custom
pass.

### Added

- **`render_manage(create)`** — generate a `.render_script` + `.render`
  pair from a small DSL. Either pass a `preset` name or a custom
  `passes` list:

  ```jsonc
  {
    "op": "create",
    "params": {
      "path": "/main/game",
      "passes": [
        { "predicate": "sky",      "cull": "front", "depth_write": false, "blend": false },
        { "predicate": "model",    "cull": "back",  "depth_write": true,  "blend": false },
        { "predicate": "particle", "cull": "none",  "depth_write": false, "blend": true  },
        { "predicate": "gui",      "projection": "ortho_window", "blend": true },
        { "predicate": "debug_text","projection": "ortho_window", "blend": true }
      ],
      "activate": true
    }
  }
  ```

  When `activate=true`, also rewrites `[bootstrap] render = ...` in
  `game.project` so the new pipeline takes over on the next build.
- **Built-in presets** — `default_3d`, `default_3d_with_sky`,
  `default_2d`. The "with sky" preset is exactly what the AppleGame 3D
  demo needed: a `sky` predicate drawn first with depth-write off and
  front-face culling.
- **`render_manage(list_presets)`** — enumerate preset names.

## [0.6.0] — 2026-05-26

Ported the `material_manage` shape from `godot-ai` so users don't have
to hand-write Defold's protobuf-text for every shader binding.

### Added

- **`material_manage(create_full)`** — build a `.material` from
  structured input: `vertex_constants=[{name, type?, value}]`,
  `fragment_constants=[...]`, `samplers=[{name, wrap_u?, wrap_v?,
  filter_min?, filter_mag?, max_anisotropy?}]`, `tags=[]`,
  `vertex_space?`, `max_page_count?`. Replaces the previous workflow of
  calling `resource_manage(write)` with a hand-crafted protobuf-text
  blob.
- **`material_manage(apply_preset)`** — curated library:
  `model_lit_tint`, `model_unlit_tint`, `sky_gradient` (auto-creates
  `/assets/shaders/sky.{vp,fp}` if missing), `gui_basic`, `sprite_basic`,
  `tilemap_basic`. The `overrides` dict deep-merges into the preset
  blueprint, so tweaking just a tint or one constant is one short call.
- **`material_manage(list_presets)`** — enumerate available preset names.
- **`material_manage(set_constant)`** — edit a single constant in place
  (`kind="fragment"|"vertex"`). Replaces the block if present, appends
  otherwise. Removes the old `NOT_IMPLEMENTED` stub.
- **`material_manage(get)`** — parse a `.material` and return structured
  fields: name, tags, vertex/fragment programs, vertex_space, all
  constants (with `{x, y, z, w}` values), sampler names. Removes the old
  `NOT_IMPLEMENTED` stub.

### Changed

- `material_manage(create)` (the original minimal op) now also emits
  `max_page_count: 0` so the resulting file is a valid `.material`
  out-of-the-box. Marked as legacy in the docs — `create_full` /
  `apply_preset` are the new entry points.

### Docs

- README now shows the official Defold logo as the hero image
  (`docs/images/hero.webp`, 18 KB) — fixes the previous broken
  `docs/images/hero.png` link.

## [0.5.0] — 2026-05-26

Inspired by reading `godot-ai`'s particle handler. Defold's `.particlefx`
schema is very different from Godot's GPUParticles3D, but the *preset*
idea ports cleanly.

### Added

- **`particlefx_manage(apply_preset)`** — curated presets `rain`, `snow`,
  `smoke`, `sparkle`, `explosion`. Each preset writes a complete
  `.particlefx` keyed against a shared white tilesource at
  `/assets/particles/white.tilesource` (auto-created from
  `/assets/images/white.png` or whatever `DEFOLD_AI_WHITE_IMAGE` points
  at). Presets take an optional `overrides` table to tweak any field.
- **`particlefx_manage(list_presets)`** — enumerate available presets so
  clients can present a menu.

### Notes on Defold particlefx quirks (discovered while porting godot-ai)

- The `gravity` field doesn't exist on Defold emitters; vertical motion
  comes from the emitter's `rotation` quaternion and
  `EMITTER_KEY_PARTICLE_SPEED`. Presets rotate 180° around X so emission
  points -Y by default (rain/snow).
- `EMITTER_KEY_PARTICLE_LIFE_TIME` lives under `properties`, not
  `particle_properties` — Godot's tools/_meta_tool wires both to the same
  domain, but Defold keeps them separate.
- `particle_properties` entries do *not* accept a `spread` field
  (only `properties` do). Bob errors otherwise.
- Emitter texture field is `animation`, not `default_animation` (which is
  the sprite-component field — easy mis-port).

## [0.4.0] — 2026-05-26

Driven by friction points hit while iterating on AppleGame 3D
(sky shader attempt + dangling collection refs).

### Added

- **`script_patch`** now accepts every editable Defold text resource, not
  just Lua: `.collection`, `.go`, `.material`, `.vp`, `.fp`, `.atlas`,
  `.tilesource`, `.tilemap`, `.input_binding`, `.gui`, `.particlefx`,
  `.render`, `.font`, `.project`. Anchor-based string-replace is the
  natural tool for surgical edits to all of these — restricting it to
  Lua forced a fall-back to raw `sed` for the rest.

### Changed

- **`collection_manage(remove_instance)`** now auto-cleans dangling
  `children: "<id>"` lines from the surviving instance blocks after a
  remove. Without this, a removed GO that was a transform child of
  another instance left bob failing on the next build with the deeply
  confusing `Cannot invoke "GameObject$InstanceDesc$Builder.getId()"
  because "o2" is null`. Returns an extra `cleaned_child_refs` count for
  visibility.
- **`resource_manage(delete)`** is now idempotent: deleting a file that
  doesn't exist returns `{ok: true, note: "already absent (no-op)"}`,
  and the success/failure check now uses a post-delete `io.open` probe
  instead of trusting `os.remove`'s return — some Defold sandbox versions
  return `(nil, nil)` from `os.remove` even on a successful delete, which
  produced misleading `DELETE_ERROR: nil` responses.

### Fixed

- No more `DELETE_ERROR: nil` when the file actually got deleted.
- No more opaque `o2 is null` build errors after removing a parented GO
  from a collection.

## [0.3.0] — 2026-05-26

Driven by a 3D port of the same Godot voxel game (player rig with 6 cube
parts + tinted prototypes shared across scene objects). Every gap that
forced manual editing during the 2D port was already closed in 0.2.0;
this release closes the gaps that 3D / multi-instance scenes exposed.

### Added

- **`collection_manage(add_instance / add_embedded)`** now accepts:
  - `children` — list of sibling instance ids that become this instance's
    transform children. Emits the proper `children: "<id>"` lines on the
    parent (where Defold's `.collection` schema actually places them).
  - `script_properties` — `{component_id: {prop_name: value, ...}}` maps to a
    `component_properties { ... }` block on the instance. Type detection
    handles number / boolean / hash / url / vec3 / vec4 automatically. This
    is the missing piece that lets you re-use one prototype across many
    instances (e.g. a single `part.go` cube tinted six ways for a character
    rig) instead of one .go per colour.
- **`collection_manage(add_collection_instance)`** — append
  `collection_instances { ... }` entries that re-use a whole `.collection`
  as a sub-tree.
- **`collection_manage(set_parent)`** — append a `children: "<child_id>"`
  line to an existing parent instance block. Useful when the parent block
  was created before its children existed.

### Changed

- **`project_manage(settings_set)`** rewritten with a proper INI
  parser (sections preserved by name; per-section key list preserved by
  order). The 0.2.0 implementation used regex over the raw text and on
  certain inputs (e.g. setting a key whose name was a suffix of an
  existing one) silently corrupted `game.project` by inserting fragments
  like `state = 1`. The new parser is line-based and section-scoped, so
  unrelated keys are byte-for-byte preserved. Discovered by writing
  `render.clear_color_red` next to an unrelated `[script] shared_state`.

### Fixed

- `settings_set` no longer corrupts `game.project` when the new key
  shares a suffix with an existing one in a different section.

### Known issues

- **`editor_reload_plugin` is unreliable for module updates.** It clears
  `package.loaded["mcp.*"]`, but Defold appears to keep a bytecode cache
  past that hook so a freshly edited handler is sometimes ignored until a
  full editor restart. Workaround: restart Defold (`quit + open`) when a
  handler change doesn't take effect after one re-call. The MCP entry
  point (`mcp.editor_script`) is unaffected — it always needs a restart
  or *Project > Reload Editor Scripts*.

## [0.2.0] — 2026-05-26

Driven by a real port of a Godot voxel game to Defold (top-down adaptation).
Every gap that forced a fallback to raw filesystem editing during that port
became an issue and was closed here.

### Added

- **`gameobject_manage(create_file)`** — produce standalone `.go` files from
  structured component specs. Embedded components accept a `data` dict that is
  serialised to Defold's escaped protobuf-text format automatically, including
  nested blocks (`embedded_collision_shape { shapes { ... } }`, `textures`,
  etc.) and enum-vs-string disambiguation. Replaces hand-quoted
  `data: "key: \"val\"\n" ...` literals.
- **`collection_manage(add_instance / add_embedded / remove_instance)`** —
  append GO instances to an existing `.collection` file. `add_instance` takes a
  prototype path; `add_embedded` uses the same component schema as
  `gameobject_manage(create_file)`.
- **`atlas_manage`** — `add_image`, `remove_image`, `list_images`,
  `add_animation`, `set_margin`, `get` (previously returned
  `NOT_IMPLEMENTED`). `create` now also accepts an initial `images=[…]` list.
- **`tilesource_manage(create)`** — new handler. Builds a `.tilesource` from a
  PNG tilesheet with per-tile animations (named tile aliases).
- **`tilemap_manage(create)`** — new handler. Pre-bakes a `.tilemap` with an
  explicit cell list. Pre-baking avoids the `Out of tiles to render` /
  `tile out of range` runtime errors that come from mutating an empty
  `.tilemap` via `tilemap.set_tile()`.
- **`project_run`** — actually launches the game. Builds with bob, then spawns
  `dmengine` detached (`( … >> dmengine.log 2>&1 < /dev/null & )`) so the
  editor's HTTP thread doesn't block.
- **`project_manage(settings_set)`** — in-place edit of `game.project`.
  Preserves unrelated keys, creates the section if missing, replaces an
  existing key, otherwise appends.
- **`project_manage(stop)`** — actually stops the running game (SIGTERM to
  `dmengine`).
- **`logs_read(source="game")`** — tails `./dmengine.log` so callers don't need
  filesystem access.
- **`util.find_defold_toolchain`** — best-effort auto-discovery of the bundled
  JDK, `bob.jar` and `dmengine` paths on macOS / Linux (Windows is rough).
  Overridable via `DEFOLD_AI_JAVA` / `DEFOLD_AI_BOB_JAR` / `DEFOLD_AI_DMENGINE`.
- **`util.run_shell`** — `editor.execute` wrapper that captures combined
  stdout+stderr and recovers the original exit code via an appended
  `__EXIT_CODE=<n>` marker. Necessary because `editor.execute` raises on
  non-zero exit and discards the captured stream in that case.
- **`util.read_file` / `util.write_file`** — shared project-relative I/O
  helpers (used to live inline in handlers).
- **`project_manage(info)`** — now reports `project_root` (absolute),
  discovered `toolchain`, and a `sandbox_capabilities` probe
  (`io_popen` / `os_execute` / `editor_execute`) so callers know what's
  available without trial-and-error.

### Changed

- **`project_manage(build)`** — no longer returns the opaque
  `"Bob invocation failed"`. Shells out to bob via `editor.execute` wrapped in
  `/bin/sh -c "...; exit 0"`, parses `ERROR <file>:<line> <msg>` lines into a
  structured `errors: [{file, line, message}, ...]` array, and includes the
  last 2 KB of bob output as `output_tail` for context.
- **`batch_execute`** — proper routing through the tool registry instead of
  the v0.1 stub. Each step is `{tool, params, ignore_errors?}`; stops on first
  failure unless `ignore_errors` is set. Returns one normalised entry per step
  (with `index` and `tool` fields).
- **`mcp.editor_script`** — tool registry is now `{module, fn}` descriptors,
  resolved lazily via `require` on every request. `editor_reload_plugin` can
  now make handler edits live without restarting Defold (restart is still
  needed only when this entry-point file itself changes).
- **`editor.reload_plugin`** — actually clears the require-cache for `mcp.*`
  modules instead of returning a vacuous note. Returns the list of cleared
  module names.
- **`docs/TOOLS.md`** — rewritten to reflect new ops. Includes a full
  end-to-end example walking the AppleGame port (atlas → tilesource → tilemap
  → input bindings → script → `gameobject_create_file` → collection
  `add_instance` → `settings_set` → `project_run` → `logs_read`).
- **`server/src/defold_ai/tools/*.py`** — updated docstrings to reflect new
  ops; added `tilesource_manage` and `tilemap_manage` MCP tool definitions.

### Fixed

- Headless build no longer drops the bob error message on the floor.
- `editor.reload_plugin` no longer lies about reloading.
- `project_run` no longer returns `OK` while doing nothing.

### Known issues

- **Editor-script sandbox is stricter than runtime.** `os.execute` is blocked;
  `io.popen` is callable but typically returns nil. Use `editor.execute`
  (Defold 1.10+). `find_defold_toolchain` and `run_shell` already do.
- **Entry-point reload still requires Defold restart.** `editor_reload_plugin`
  hot-reloads handlers (`handlers/*.lua`, `lib/*.lua`) but not
  `mcp.editor_script` itself. Use Defold's *Project > Reload Editor Scripts*
  menu (or a full restart) when changing routes or boot code.
- **Windows path discovery is best-effort.** macOS + Linux globs cover the
  common installs; on Windows set `DEFOLD_AI_JAVA` / `DEFOLD_AI_BOB_JAR` /
  `DEFOLD_AI_DMENGINE` explicitly.
- **`gameobject_manage(duplicate / rename / reparent)`** still returns
  `NOT_IMPLEMENTED` — requires reading + reconstructing the node spec.

## [0.1.0] — 2026-05-26

Initial release.

### Added

- Python MCP server (`server/src/defold_ai`) built on FastMCP. Each tool
  forwards over HTTP to the editor's `/mcp/<tool>` route. URL discovery
  order: `DEFOLD_AI_URL` env → `~/.defold_ai_url` file → port probing.
- Defold editor script bridge (`plugin/mcp/mcp.editor_script`) using
  Defold 1.10+'s built-in `http.server` — no WebSocket layer.
- Handlers (`plugin/mcp/handlers/*.lua`):
  - `editor` — `state`, `screenshot` (stub), `manage`, `reload_plugin` (stub).
  - `collection` — `create`, `open`, `save`, `get_hierarchy`.
  - `gameobject` — `create` (in-collection), `set_property`,
    `get_properties`, `find`, `manage(delete / get_children)`.
  - `component` — `add` (script / sprite / model / mesh / sound / particlefx /
    factory / camera / collisionobject / label / tilemap / …), `remove`.
  - `script` — `create`, `attach`, `patch` (anchor-based string-replace),
    `manage(read / detach / find_symbols)`.
  - `resource` — generic `create / read / write / delete`.
  - `material` / `particlefx` / `atlas` — `create` only.
  - `filesystem` — `read_text`, `write_text`, `mkdir`, `rm`, `reimport`,
    `search`.
  - `input_binding` — `list`, `add_key`, `add_mouse`, `add_gamepad`,
    `add_touch`, `remove`.
  - `project` — `run` (stub), `manage(stop / build / settings_get / info)`,
    `logs_read` (editor-only buffer), `batch_execute` (stub).
- `docs/ARCHITECTURE.md` and `docs/TOOLS.md`.
- `examples/hello_cube` placeholder.

[Unreleased]: https://github.com/estebanrfp/defold-ai/compare/v0.7.0...HEAD
[0.7.0]: https://github.com/estebanrfp/defold-ai/compare/v0.6.0...v0.7.0
[0.6.0]: https://github.com/estebanrfp/defold-ai/compare/v0.5.0...v0.6.0
[0.5.0]: https://github.com/estebanrfp/defold-ai/compare/v0.4.0...v0.5.0
[0.4.0]: https://github.com/estebanrfp/defold-ai/compare/v0.3.0...v0.4.0
[0.3.0]: https://github.com/estebanrfp/defold-ai/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/estebanrfp/defold-ai/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/estebanrfp/defold-ai/releases/tag/v0.1.0
