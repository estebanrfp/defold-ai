# Changelog

All notable changes to **defold-ai** are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)
and this project follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).
Each release maps 1:1 to a git tag once published — `git log <prev>..<next>` is
the source of truth, this file is the human-readable summary.

## [Unreleased]

Planned next:

- `material_manage(set_constant / get)` — structured `.material` edits.
- `particlefx_manage(apply_preset)` — `rain / snow / smoke / sparkle / explosion`.
- `gameobject_manage(duplicate / rename / reparent)`.
- `collection_manage(save_as / get_roots)` once Defold exposes the API.
- `editor_screenshot` — pending Defold editor-script API.
- Windows discovery paths for `find_defold_toolchain` (currently best-effort).
- An `examples/applegame` folder so the README walkthrough is runnable.

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

[Unreleased]: https://github.com/estebanrfp/defold-ai/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/estebanrfp/defold-ai/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/estebanrfp/defold-ai/releases/tag/v0.1.0
