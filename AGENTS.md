# AGENTS.md — defold-ai

Notes for LLM-driven agents (Claude Code, Cursor, Cline, OpenAI Codex…) when
operating this MCP server against a Defold project. These are **non-obvious
trampas** discovered shipping real games end-to-end through the MCP. They
are not in Defold's docs — they're failure modes you only learn by stepping
on them. Read this first if you're authoring a new project with the agent.

The MCP itself is described in `README.md` / `docs/TOOLS.md`. Everything
below is operational know-how layered on top.

---

## 1. Connection sanity

1. Open Defold with the project (it must contain
   `plugin/mcp/mcp.editor_script`, otherwise the HTTP bridge never starts).
2. Verify with `editor_state` — should return `version`, `http_url`,
   `readiness: "ready"`. If it errors, the editor isn't reachable; the URL
   file at `~/.defold_ai_url` may be stale. Rewrite it from a shell.

---

## 2. Lua compatibility (LuaJIT 2.1 + Lua 5.1 strict linter)

Defold runs **LuaJIT 2.1** for both runtime AND editor scripts. The editor's
script linter, however, validates against **stock Lua 5.1** — so syntactic
extensions LuaJIT supports still produce hard build errors in the editor
even when `bob` CLI accepts them.

| Don't write             | Write instead                              |
|-------------------------|--------------------------------------------|
| `a ~ b` (bitwise xor)   | `bit.bxor(a, b)` — `bit` is a global       |
| `a >> n`                | `bit.rshift(a, n)`                         |
| `a << n`                | `bit.lshift(a, n)`                         |
| `a & b`, `a \| b`       | `bit.band(a, b)`, `bit.bor(a, b)`          |
| `a // b`                | `math.floor(a / b)`                        |
| `table.unpack(t)`       | `local _unpack = unpack or table.unpack` ¹ |
| `goto label` / `::lbl::`| Refactor: helper returning `false` to skip |
| `?:` ternary            | `if/else`                                  |

¹ The order matters: `unpack` first. The editor's Lua 5.1 linter warns on
`table.unpack` first even though LuaJIT supports both.

Real cases that bit us:
- `(h ~ (h >> 13))` in `world.script` crashed bob with `')' expected near '~'`
- `table.unpack(...)` in an editor handler raised `attempt to call nil`
- `goto continue` in a loop body: editor refused to load the script

---

## 3. Editor-script sandbox (Defold 1.10+)

The editor script sandbox is **stricter than the runtime sandbox**.

| API             | Status in editor scripts                            |
|-----------------|-----------------------------------------------------|
| `os.execute`    | Blocked — raises "attempt to call nil"              |
| `io.popen`      | Callable but returns nil from the handle. Don't use.|
| `os.getenv`     | Available                                            |
| `io.open` (rel) | Available — paths inside the project only           |
| `io.open` (abs) | Outside project = "outside of project directory"    |
| `editor.execute`| **Preferred** for any shell-out (bob, cp, ls, etc.) |

`editor.execute` notes:
- Raises on non-zero exit AND discards captured stdout on raise. Wrap your
  command in `/bin/sh -c "...; exit 0"` and append a sentinel like
  `__EXIT_CODE=$?` to surface the original status. (`util.run_shell` in
  this repo does that for you.)
- Passing `{"cp", "/absolute/outside/project", "..."}` fails with
  "Can't access … outside of project directory". For cross-sandbox copies
  use either `/bin/sh -c "cp '...' '...'"` or — more reliably — `cat src > dst`.
  In one config we hit, even the shelled `cp` no-op'd silently (returning
  success but doing nothing). `cat > ` consistently crosses the boundary.

---

## 4. Build pipeline gotchas

- **Dependencies trigger a different bob invocation.** When `game.project`
  has a `dependencies = …` line, you must run `bob resolve build`, not just
  `bob build`. Otherwise the build fails with "Missing libraries folder".
  `project_manage(build)` detects this automatically; if you shell out
  manually, remember the `resolve` verb.
- **Native extensions produce a custom dmengine.** After
  `editor_screenshot_install` (or any other dependency add) + a build,
  the engine binary you should launch is
  `build/<arch>-<os>/dmengine`, **not** the unpacked stock one. The custom
  one has your extensions linked in. `project_run` picks this up.
  Remember to `chmod +x` it and pass the absolute path — relative paths
  through `editor.execute` don't always resolve.
- **JDK version**: Defold ships its own JDK at
  `/Applications/Defold.app/Contents/Resources/packages/jdk-*/bin/java`.
  System Java fails with `UnsupportedClassVersionError` (class file 69+).

---

## 5. Render & 3D quirks

- **`camera.get_cameras()` returns userdata, not a Lua array.** Iterate
  with `pairs`, not `ipairs`. The latter silently produces an empty loop
  and your render script binds nothing → the screen stays at clear_color.
- **`camera.auto_aspect_ratio = 0`** silently renders nothing through
  `render.set_camera(cam, { use_frustum = true })`. Leave it at 1 unless
  you have a reason not to.
- **The default render script is 2D.** A 3D project needs a custom
  `.render` + `.render_script` with a `model` predicate drawn between
  sky and tile passes. `render_manage` ships a `default_3d` preset.
- **Inverted-sphere skyboxes are flaky in 1.12.x.** Built-in
  `sphere.dae` has ~8 segments so each face covers a huge FOV;
  combined with the default `model.vp` interpolation that lets
  `normalize(vec3(0))` happen at one vertex, you get a solid-white
  quad covering half the view. Use a clear_color or a cubemap instead,
  or write a sky shader that derives direction from view-projection
  rather than vertex position.

---

## 6. GUI gotchas

- **`TYPE_BOX` at position (0,0) with `ADJUST_MODE_FIT`** can scale to
  half the screen. Real example from this repo's debugging history: a
  6×6-pixel crosshair "at the center" (because the author placed it at
  0,0 expecting screen-center) became a full-quadrant white slab when
  the window stretched. Use absolute pixel positions matching the
  design resolution (e.g. `(640, 360)` for a 1280×720 design) and
  `ADJUST_MODE_ZOOM` for HUD elements that must keep aspect.
- **Score labels with `xanchor=LEFT, yanchor=TOP, pivot=NW, position(20,-20)`**
  go to (20, screen_h - 20). The negative Y is the offset from the top
  edge, not a coordinate.

---

## 7. Input / camera gotchas

- **Mouse-look on launch grabs whatever the OS cursor was doing.** When
  the dmengine window opens, if the cursor was hovering inside it, the
  first frame already reports a big `dx/dy` and the camera spins to a
  random orientation before the player can react. Solution: gate the
  mouse handler behind a "first user click" flag (`mouse_armed`),
  separate from `mouse_locked`.
- **Kinematic player physics needs `contact_point_response` handling.**
  Defold won't separate kinematic-vs-static automatically — you must
  apply the contact normal yourself. The pattern is in
  `examples/applegame/player/player.script` if/when we ship it.

---

## 8. Screenshot workflow (battle-tested)

The reliable path for `editor_screenshot(source="game")`:

1. **One-time install per project**: call `editor_screenshot_install`.
   It appends `britzl/defold-screenshot` to the `dependencies` line in
   `game.project`.
2. **Build**: `project_manage(build)` runs `bob resolve build` because
   the dependency is now present. The build produces a custom dmengine
   at `build/arm64-osx/dmengine` (macOS arm64).
3. **Run**: `project_run` launches the custom dmengine. The extension
   self-registers a `/screenshot` HTTP endpoint on the engine service
   (default port 8001).
4. **Capture**: `editor_screenshot(source="game")` curls the endpoint,
   parses the JSON reply, and copies the PNG from
   `/var/folders/.../defold-screenshot/` into the project root.

If you get `EXTENSION_MISSING` immediately after step 3, the dmengine
that's actually running is the **stock** one, not your custom build —
something killed the custom-engine detection. Check the dmengine log
header for `INFO:SCREENSHOT: Screenshot debug endpoint registered`. If
that line is missing, the extension wasn't linked in. Rebuild.

If you get `COPY_FAILED`, the file is still at `source_path` — read it
from there as a fallback.

---

## 9. The big-picture lesson

LLM-driven Defold development hits these trampas more often than
LLM-driven Godot/Unity development because the per-quirk volume of
training-data examples is much smaller. Most failures you'll encounter
will be in this document. If you hit a new one, add it here — that's
how the next session arrives smarter than this one did.
