# Changelog

All notable changes to **defold-ai** are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)
and this project follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).
Each release maps 1:1 to a git tag once published — `git log <prev>..<next>` is
the source of truth, this file is the human-readable summary.

## [Unreleased]

Planned next:

- `gameobject_manage(duplicate / rename / reparent)`.
- `collection_manage(save_as / get_roots)`.
- A reliable hot-reload path.
- Linux / Windows paths for `find_defold_toolchain` + `editor_screenshot(source="macos")`.
- `examples/applegame` runnable demo.

## [0.14.1] — 2026-05-27

### Added

- **`AGENTS.md`** at the repo root — a playbook of non-obvious Defold
  trampas collected while shipping AppleGame end-to-end through the MCP.
  Covers LuaJIT vs Lua 5.1 linter mismatch, editor-script sandbox rules,
  render quirks (camera.get_cameras userdata, auto_aspect_ratio), build
  pipeline (bob resolve + custom dmengine), GUI gotchas
  (ADJUST_MODE_FIT scaling a 6×6 box to half-screen), mouse-look spin
  on launch, and the proven screenshot workflow. Read it first when
  starting a new project — it documents failure modes you'd otherwise
  hit live. README now points to it explicitly so any LLM that ingests
  the repo finds it on first pass.

## [0.14.0] — 2026-05-27

Two crash-class fixes around `editor_screenshot(source="game")` discovered
while shipping the AppleGame demo end-to-end.

### Fixed

- **False-positive `EXTENSION_MISSING`**: the 404-detection branch did a
  naïve `resp:find("404")` over the entire response body. The britzl
  extension emits temp-file paths like
  `/var/folders/.../screenshot-1779840427-1.png` — the unix timestamp
  contains the literal substring `404`, and the handler rejected every
  successful capture. Replaced with a structural check on the JSON shape
  (`"path":"…"`) instead of substring scanning.
- **Silent `cp` failure → stale screenshot returned**: copying the PNG out
  of the sandbox (`/var/folders/...`) into the project root with `cp`
  silently no-op'd under some `editor.execute` sandbox configurations.
  The handler then `_file_size()`'d the *previous* run's leftover file
  and reported success. Switched the copy to `cat src > dst` (which
  reliably crosses the sandbox boundary), compared `src_size` vs
  `dest_size`, and now surface a proper `COPY_FAILED` error with
  `source_path` so the caller can fall back to reading the temp file
  directly.

### Changed

- `lib/util.lua`: `local _unpack = unpack or table.unpack` (the order
  matters — `unpack` is the LuaJIT-native form and the editor's Lua 5.1
  linter warns on `table.unpack` first even though LuaJIT supports both).

## [0.13.0] — 2026-05-27

`editor_screenshot(source="game")` finally just works end-to-end. The
custom dmengine (built once when the project has native dependencies)
loads the screenshot extension, which **self-registers a `/screenshot`
HTTP endpoint on the engine service** — no helper script, no file
trigger, no polling needed.

### Added

- **`project_run`** picks up the **custom build engine** when the project
  has native dependencies (a custom dmengine produced by the extender
  service lives at `build/<arch>-<os>/dmengine`). Also `chmod +x` the
  binary and resolve the absolute path so the launching shell finds it.
- **`project_manage(build)`** runs `bob resolve build` (instead of just
  `build`) when `game.project` has a `dependencies = ...` line, so the
  first build after a `editor_screenshot_install` call downloads and
  compiles the native extension automatically.

### Changed

- **`editor_screenshot(source="game")`** now:
  1. Discovers the engine-service port via `lsof` + `/ping`.
  2. `curl http://localhost:<port>/screenshot` — the extension writes a
     PNG to `/var/folders/.../defold-screenshot/screenshot-N.png` and
     replies `{ "path": "..." }`.
  3. Copies the PNG into the project at `.defold_ai_capture.png` and
     returns both `path` (project-relative) and `source_path`
     (absolute temp path) plus `size` and `engine_service_port`.

  The total flow is one MCP call + one HTTP roundtrip to the running
  engine, ~10 ms. No file polling, no helper Lua script, no autoload.

- **`editor_screenshot_install`** trimmed to just one job: append
  `britzl/defold-screenshot` to `[project] dependencies` in
  `game.project` (idempotent). No longer writes
  `/defold_ai/helper.script` or `/defold_ai/helper.go`, no longer
  modifies `main.collection`.

### Removed

- The file-polling handshake (trigger marker + output file) added in
  v0.12.0 — turned out the extension's own `/screenshot` endpoint
  is simpler and faster. The helper-script approach stays in the v0.12
  CHANGELOG entry as a historical note.

### Notes

This release closes the screenshot story for real. The flow is now:

```
editor_screenshot_install      ←  one call, adds dependency
project_manage(build)          ←  bob 'resolve build', ~15s first time
project_run                    ←  custom dmengine, /screenshot endpoint live
editor_screenshot(source=game) ←  PNG path returned in <50ms
```

## [0.12.0] — 2026-05-27

Game-side `editor_screenshot` lands. Cross-platform, no OS permissions.

### Added

- **`editor_screenshot_install`** — one-shot setup that:
  - writes `/defold_ai/helper.script` (polls `.defold_ai_capture_request`
    in the project root, calls `screenshot.png()` from the
    [britzl/defold-screenshot](https://github.com/britzl/defold-screenshot)
    extension, writes the PNG to `.defold_ai_capture.png`, clears the
    trigger);
  - writes `/defold_ai/helper.go` referencing that script;
  - appends `britzl/defold-screenshot` to `[project] dependencies` in
    `game.project` (idempotent — skipped if already present);
  - optionally (`auto_wire=true`) appends an instance of
    `/defold_ai/helper.go` to `/main/main.collection` so it loads on
    `project_run`.

  After install the user runs **Project > Fetch Libraries** in Defold
  once (to pull the native extension), then `project_run` and the
  game-side helper is live.

- **`editor_screenshot(source="game")`** — file-based handshake between
  editor and the running `dmengine`:
  1. Drop a trigger marker at `.defold_ai_capture_request`.
  2. Helper's `update()` notices, calls `screenshot.png()` async,
     writes the PNG to `.defold_ai_capture.png`, removes the trigger.
  3. Editor handler polls (100 ms steps, default 5 s timeout) for the
     PNG, returns `{ok, source, path, size, timeout}`.

  Cross-platform: macOS / Linux / Windows / iOS / Android / HTML5
  (anywhere the screenshot extension runs). No OS permissions, no
  `screencapture`, no JavaFX.

- **`editor_screenshot(source="auto")`** — try `"game"` first; on
  `SETUP_REQUIRED` / `ENGINE_NOT_RUNNING` / `TIMEOUT`, fall back to the
  macOS `screencapture` path. Best default for "I don't care how, just
  give me a PNG".

### Changed

- `editor_screenshot` `source` param now accepts `auto` / `game` /
  `macos` / `editor`. `target` (old name) stays accepted as an alias
  for backwards compat — `target="editor"` maps to `source="macos"`.

### Notes

This closes the long-standing gap that motivated v0.9-0.10's whole arc:
the editor can now ask the running game for a screenshot directly,
without depending on macOS Screen Recording permission. The helper
itself is generated on demand and the dependency is a tiny native
extension maintained by Björn Ritzl (one of the Defold core devs).

## [0.11.0] — 2026-05-27

Documentation pass — everything added in 0.4 → 0.10 is now reflected
in the user-facing docs.

### Changed

- **`docs/TOOLS.md`** rewritten end-to-end. The status table now lists
  every op of every tool (instead of just the tool names), the example
  walkthrough is replaced with a "build a 3D scene in ~10 MCP calls"
  flow that uses the new `render_manage` / `material_manage` /
  `camera_manage` / `particlefx_manage` preset APIs, and the
  "Defold API limitations" section is honest about what still doesn't
  work.
- **`README.md`** updated:
  - Hero subtitle calls out the v0.10.0 capabilities.
  - Boot-line example reflects the new tool count (35 vs the old 28).
  - Tools table groups resources + presets together
    (`material_manage` / `render_manage` / `camera_manage` /
    `particlefx_manage`) so newcomers see the preset libraries
    immediately.
  - Status section drops the "alpha, ~16 tools" framing — replaces it
    with the real shipped surface + known gaps from `[Unreleased]`.

## [0.10.0] — 2026-05-27

`editor_screenshot` ships — implemented via macOS `screencapture` with
honest error reporting when permissions are missing.

### Added

- **`editor_screenshot`** (no longer `NOT_IMPLEMENTED`):
    - ``target = "game" | "editor"``: which window to capture.
    - ``path``: where to write the PNG (default
      `/tmp/defold_ai_screenshot.png`).
    - Two capture modes, fallback automatically:
      1. **window** — discover the target window-id via `osascript`
         (`System Events`), capture just that window. Needs Accessibility
         permission for the shell.
      2. **full_screen** — fallback if osascript can't reach
         System Events. Captures the whole display.
    - Both modes need macOS **Screen Recording** permission for whatever
      process spawned the editor (Terminal / iTerm / Claude Code / ...).
      When the permission is missing, `screencapture` silently writes no
      file; the handler detects the absence and returns a structured
      `SCREENSHOT_DENIED` error with the exact System Settings path to
      fix it.
    - Returns `{ok, target, mode, path, size, process, window_id?}` on
      success.

### Notes

- Linux & Windows paths are stubbed — they fall back to the same shell
  approach but only macOS's `screencapture` is wired up. The handler
  fails cleanly on other OSes.
- A future iteration will inject a `game_helper.lua` that captures the
  render target from inside the running game — eliminating the OS
  permission dependency. Tracked under [Unreleased] above.

## [0.9.0] — 2026-05-27

### Changed

- **`gameobject_find`** — now paginated with richer filtering, ported
  from `godot-ai`'s `node_find` pattern:
    - New params: ``component_type`` (e.g. `"model"`, `"camera"`),
      ``max_depth`` (default 16), ``offset`` / ``limit`` (default
      0/200).
    - Each match now includes ``id``, ``type``, ``path``, ``depth`` and
      ``component_types`` (a list of component types the GO carries).
    - Response gained ``total``, ``offset``, ``limit``, ``has_more`` so
      callers can page through large scenes without grabbing everything
      into one response.
    - Existing callers keep working — ``name_pattern`` and
      ``type_filter`` remain the same.

### Known issues

- `editor_screenshot` is still unimplemented. macOS `screencapture`
  needs Screen Recording permission, and Defold's engine service
  (`http://localhost:8001`) returns the profiler HTML for unknown
  paths — there is no built-in `/capture` endpoint. The CHANGELOG
  Unreleased section tracks the planned `game_helper.lua` injection
  approach.

## [0.8.0] — 2026-05-27

Wraps Defold's camera component + the two follow rigs every project
re-implements by hand.

### Added

- **`camera_manage(create)`** — generate a bare camera `.go` with one
  embedded camera component. Accepts the usual `fov` / `near_z` / `far_z`
  / `orthographic` / `orthographic_zoom` / `auto_aspect_ratio` opts.
- **`camera_manage(apply_preset)`** — generate camera `.go` *and* the
  matching follow `.script` in one call. Presets:
    - `perspective_basic` / `orthographic_basic` — bare camera, no
      script.
    - `follow_3d` — third-person orbital. The generated script handles
      mouse-driven yaw/pitch + back/up offset. Parent the camera GO
      under your target instance so position follows automatically.
      Exposes `spring_len`, `height_offset`, `pitch_min/max` as
      `go.property` so they're tunable from collection overrides.
    - `follow_2d` — 2D camera that smoothly lerps to a `target` URL each
      frame. Exposes `target` (default `"/player"`) and `lerp`.
  The `camera` dict overrides the camera component opts (fov, far_z,
  etc.) on top of preset defaults.
- **`camera_manage(list_presets)`** — enumerate presets with one-line
  descriptions.

### Notes

- Defold's camera lives as a *component* inside a GO; the render script
  binds it via `camera.get_cameras()`. `camera_manage` always produces
  the GO + component pair so callers don't have to remember to wire it
  up by hand.

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

[Unreleased]: https://github.com/estebanrfp/defold-ai/compare/v0.13.0...HEAD
[0.13.0]: https://github.com/estebanrfp/defold-ai/compare/v0.12.0...v0.13.0
[0.12.0]: https://github.com/estebanrfp/defold-ai/compare/v0.11.0...v0.12.0
[0.11.0]: https://github.com/estebanrfp/defold-ai/compare/v0.10.0...v0.11.0
[0.10.0]: https://github.com/estebanrfp/defold-ai/compare/v0.9.0...v0.10.0
[0.9.0]: https://github.com/estebanrfp/defold-ai/compare/v0.8.0...v0.9.0
[0.8.0]: https://github.com/estebanrfp/defold-ai/compare/v0.7.0...v0.8.0
[0.7.0]: https://github.com/estebanrfp/defold-ai/compare/v0.6.0...v0.7.0
[0.6.0]: https://github.com/estebanrfp/defold-ai/compare/v0.5.0...v0.6.0
[0.5.0]: https://github.com/estebanrfp/defold-ai/compare/v0.4.0...v0.5.0
[0.4.0]: https://github.com/estebanrfp/defold-ai/compare/v0.3.0...v0.4.0
[0.3.0]: https://github.com/estebanrfp/defold-ai/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/estebanrfp/defold-ai/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/estebanrfp/defold-ai/releases/tag/v0.1.0
