-- Editor-level handlers: state, screenshot, manage, reload.

local util = require "mcp.lib.util"

local M = {}

-- ---------------------------------------------------------------- state ----

function M.state(body)
  return {
    ok = true,
    version = sys and sys.get_engine_info and sys.get_engine_info().version or "unknown",
    http_url = http.server.url,
    readiness = "ready",
    current_collection = "",
  }
end

-- --------------------------------------------------------- screenshot -----
--
-- Three modes — pick with `source`:
--
--   "game"   (default): file-based trigger between editor and the running
--             dmengine. Requires the helper to be installed first via
--             `editor_screenshot_install`. Uses the britzl/defold-screenshot
--             native extension. Cross-platform, no OS permissions needed.
--   "macos"  (or "editor"): macOS `screencapture` of the dmengine/Defold
--             window. Needs Screen Recording permission for the process
--             spawning the editor. Works without project changes.
--   "auto"   try `"game"` first; on TIMEOUT or SETUP_REQUIRED, fall back to
--             `"macos"`.

local TRIGGER_FILENAME = ".defold_ai_capture_request"
local OUTPUT_FILENAME  = ".defold_ai_capture.png"

local function _project_path(filename)
  -- The editor's cwd is the project root; dmengine inherits it too.
  return filename
end

local function _file_exists(path)
  local f = io.open(path, "rb")
  if f then f:close() return true end
  return false
end

local function _file_size(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local s = f:seek("end") or 0
  f:close()
  return s
end

-- ---------------------------------------------------------- game capture ----

-- Find the engine service port of a running dmengine. Defold's HTTP engine
-- service listens on port 8001 by default but binds elsewhere when the port
-- is taken. We probe `lsof` for any dmengine TCP listener that answers /ping.
local function _find_engine_service_port()
  local out = util.run_shell(
    "lsof -i -P -n -sTCP:LISTEN -a -c dmengine 2>/dev/null") or ""
  for port_str in out:gmatch(":(%d+)%s*%(LISTEN%)") do
    local probe = util.run_shell(
      "curl -s -o /dev/null -w '%{http_code}' --max-time 1 http://localhost:" ..
      port_str .. "/ping 2>/dev/null") or ""
    if probe:gsub("%s+", "") == "200" then return tonumber(port_str) end
  end
  return nil
end

-- Capture via the running dmengine's HTTP engine service. Requires the
-- britzl/defold-screenshot extension in game.project (call
-- editor_screenshot_install to add it). The extension registers a
-- /screenshot endpoint on the engine service that writes a PNG to a
-- temp file and replies with `{ path = "..." }`.
local function _capture_via_game(body)
  body = body or {}
  local timeout_s = body.timeout or 5
  local out_path = body.path  -- optional copy destination

  -- 1. Engine must be running
  local port = _find_engine_service_port()
  if not port then
    return util.error_response("ENGINE_NOT_RUNNING",
      "No dmengine engine-service was found. Call project_run first.")
  end

  -- 2. Hit the /screenshot endpoint (added by britzl/defold-screenshot ext)
  local resp = util.run_shell(
    string.format("curl -s --max-time %d http://localhost:%d/screenshot",
                  timeout_s, port)) or ""
  if resp == "" then
    return util.error_response("TIMEOUT",
      "Engine service did not reply within " .. timeout_s ..
      "s. The dmengine may be hung; check project_run logs.")
  end
  if resp:find("404") or resp:find("Not Found") then
    return util.error_response("EXTENSION_MISSING",
      "/screenshot endpoint not found on the engine service. " ..
      "Run editor_screenshot_install to add britzl/defold-screenshot " ..
      "to game.project, then build + project_run again.",
      { response_tail = resp:sub(1, 200) })
  end

  -- 3. Parse the JSON reply { "path": "/var/folders/.../screenshot-...png" }
  local path = resp:match('"path"%s*:%s*"([^"]+)"')
  if not path then
    return util.error_response("INVALID_RESPONSE",
      "Could not parse /screenshot reply",
      { response = resp:sub(1, 300) })
  end

  -- 4. The extension writes to /var/folders/.../defold-screenshot/ which is
  --    outside the project sandbox — io.open can't read it from the editor
  --    script. Copy it into the project via /bin/sh so it's visible to
  --    the editor and any tool downstream.
  local final_path = out_path or ".defold_ai_capture.png"
  -- Escape single quotes for safe shell substitution.
  local src_esc = path:gsub("'", "'\\''")
  local dst_esc = final_path:gsub("'", "'\\''")
  local cp_out = util.run_shell("cp '" .. src_esc .. "' '" .. dst_esc .. "'") or ""
  -- io.open works on project-relative paths.
  local size = _file_size(final_path) or 0
  if size == 0 then
    -- Fallback: stat the source file via shell.
    local stat_out = util.run_shell("stat -f %z '" .. src_esc .. "'") or ""
    size = tonumber(stat_out:match("%d+")) or 0
  end

  return {
    ok = true, source = "game", path = final_path,
    source_path = path, size = size,
    engine_service_port = port,
  }
end

-- ---------------------------------------------------------- macOS capture ----

local function _capture_via_macos(body)
  body = body or {}
  local target = body.target or "game"
  local out_path = body.path or "/tmp/defold_ai_screenshot.png"
  local proc = (target == "editor") and "Defold" or "dmengine"

  os.remove(out_path)
  local discover_cmd = string.format(
    [[osascript -e 'tell application "System Events"
       set procs to (every process whose name contains "%s")
       if procs is {} then return ""
       set the_proc to item 1 of procs
       tell the_proc
         if (count of windows) is 0 then return ""
         return id of first window
       end tell
     end tell' 2>/dev/null]], proc)
  local id_out = util.run_shell(discover_cmd) or ""
  local window_id = id_out:gsub("%s+$", "")
  local mode = "window"
  local cap_cmd
  if window_id ~= "" then
    cap_cmd = "screencapture -l " .. window_id .. " -x -t png '" .. out_path .. "' 2>&1"
  else
    mode = "full_screen"
    cap_cmd = "screencapture -x -t png '" .. out_path .. "' 2>&1"
  end
  local cap_out = util.run_shell(cap_cmd) or ""
  if not _file_exists(out_path) then
    return util.error_response("SCREENSHOT_DENIED",
      "screencapture wrote no file. macOS blocked the call. Grant Screen " ..
      "Recording permission to whatever process spawned the editor under " ..
      "System Settings > Privacy & Security > Screen Recording, then " ..
      "restart that process.",
      { target = target, mode = mode, window_id = window_id,
        screencapture_output = cap_out })
  end
  return {
    ok = true, source = "macos", target = target, mode = mode,
    path = out_path, window_id = (window_id ~= "" and window_id or nil),
    size = _file_size(out_path) or 0,
  }
end

function M.screenshot(body)
  body = body or {}
  local source = body.source or "game"
  if source == "auto" then
    local r = _capture_via_game(body)
    if r.ok then return r end
    if r.error == "SETUP_REQUIRED" or r.error == "ENGINE_NOT_RUNNING" or r.error == "TIMEOUT" then
      local fb = _capture_via_macos(body)
      fb.game_attempt = r
      return fb
    end
    return r
  elseif source == "game" then
    return _capture_via_game(body)
  elseif source == "macos" or source == "editor" then
    return _capture_via_macos(body)
  else
    return util.error_response("INVALID_PARAM",
      "source must be one of: auto | game | macos | editor (got: " .. source .. ")")
  end
end

-- ------------------------------------------------- screenshot_install -----
--
-- One-shot setup: appends `britzl/defold-screenshot` to `[project]
-- dependencies` in game.project. The extension self-registers a
-- `/screenshot` HTTP endpoint on the engine service when the game runs —
-- no game-side helper script needed.
--
-- After install:
--   1. project_manage(op="build")  — bob runs `resolve build`
--      automatically (game.project now has a dependency).
--   2. project_run                 — the custom dmengine loads with the
--      native ext baked in; /screenshot becomes available on port 8001.
--   3. editor_screenshot(source="game") — returns a PNG path immediately.

local _DEP_URL = "https://github.com/britzl/defold-screenshot/archive/master.zip"

function M.screenshot_install(body)
  body = body or {}
  local results = { ok = true, edited = {} }

  local gp = util.read_file("game.project") or ""
  if gp:find(_DEP_URL, 1, true) then
    results.already_installed = true
    results.note = "Dependency already in game.project. " ..
                   "Run project_run to make /screenshot available."
    return results
  end

  if gp:find("\ndependencies") then
    gp = gp:gsub("(\ndependencies%s*=%s*[^\n]*)", "%1," .. _DEP_URL, 1)
  elseif gp:find("%[project%]") then
    gp = gp:gsub("(%[project%][^%[]*)", "%1dependencies = " .. _DEP_URL .. "\n", 1)
  else
    gp = gp .. "\n[project]\ndependencies = " .. _DEP_URL .. "\n"
  end
  util.write_file("game.project", gp)
  table.insert(results.edited, "game.project (+dependencies)")
  results.dependency_added = _DEP_URL
  results.note = "Dependency added. Run project_run (which triggers " ..
                 "bob 'resolve build' automatically) and the /screenshot " ..
                 "endpoint will be live on the engine service."
  return results
end

-- ---------------------------------------------------------- manage --------

function M.manage(body)
  local op = body.op or ""
  local params = body.params or {}
  if op == "state" then
    return M.state(body)
  elseif op == "selection_get" then
    return util.error_response("NOT_IMPLEMENTED",
      "selection_get not exposed by Defold editor scripting API")
  elseif op == "logs_clear" then
    return { ok = true, note = "Editor console clear is not programmatic; use the UI." }
  end
  return util.error_response("UNKNOWN_OP", "Unknown editor_manage op: " .. op)
end

-- ---------------------------------------------------------- reload_plugin --

function M.reload_plugin(body)
  local reloaded = {}
  for name, _ in pairs(package.loaded or {}) do
    if name:find("^mcp%.") then
      package.loaded[name] = nil
      table.insert(reloaded, name)
    end
  end
  return {
    ok = true, reloaded_modules = reloaded,
    note = "Module require-cache cleared. Restart Defold (or use Project > " ..
           "Reload Editor Scripts) for entry-point changes.",
  }
end

return M
