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

local function _capture_via_game(body)
  body = body or {}
  local timeout_s = body.timeout or 5
  local out_path = _project_path(OUTPUT_FILENAME)
  local trigger  = _project_path(TRIGGER_FILENAME)

  -- 1. Pre-check: helper must be installed
  if not _file_exists(_project_path("defold_ai/helper.script")) then
    return util.error_response("SETUP_REQUIRED",
      "Game-side helper not installed. Call editor_screenshot_install once " ..
      "to write /defold_ai/helper.* + add britzl/defold-screenshot dep " ..
      "to game.project. Then project_run again so the helper is active.",
      { missing = "/defold_ai/helper.script" })
  end

  -- 2. Pre-check: dmengine must be running (the helper polls the trigger)
  local ps_out = util.run_shell("pgrep -x dmengine") or ""
  if ps_out:gsub("%s+", "") == "" then
    return util.error_response("ENGINE_NOT_RUNNING",
      "dmengine is not running. Call project_run first, then this screenshot.")
  end

  -- 3. Clear stale output, drop the trigger marker
  os.remove(out_path)
  local t = io.open(trigger, "w")
  if not t then
    return util.error_response("WRITE_ERROR",
      "Could not write trigger file at " .. trigger ..
      " — is the project directory writable?")
  end
  t:write(tostring(os.time()))
  t:close()

  -- 4. Poll for output (100 ms steps). The helper writes the PNG and clears
  --    the trigger when done.
  local deadline = os.time() + timeout_s
  while os.time() <= deadline do
    util.run_shell("sleep 0.1")
    if _file_exists(out_path) and not _file_exists(trigger) then
      local size = _file_size(out_path) or 0
      return {
        ok = true, source = "game", path = out_path, size = size,
        timeout = timeout_s,
      }
    end
  end

  -- Cleanup the marker so the next request starts fresh.
  os.remove(trigger)
  return util.error_response("TIMEOUT",
    "Game helper did not produce a screenshot within " .. timeout_s ..
    "s. Check that (a) the helper is in main.collection and (b) the project " ..
    "has britzl/defold-screenshot in its dependencies + has been rebuilt.")
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
-- One-shot setup: writes /defold_ai/helper.script, /defold_ai/helper.go and
-- adds the britzl/defold-screenshot dep to game.project if missing. Optionally
-- (auto_wire=true) appends the helper instance to bootstrap.main_collection
-- so it loads automatically on project_run.

local _HELPER_SCRIPT = [[
-- Generated by defold-ai editor_screenshot_install.
-- Polls a trigger file written by the editor; when present, calls
-- screenshot.png() (britzl/defold-screenshot ext) and writes the PNG
-- bytes to a sibling output file. The editor handler then reads it back.

local TRIGGER = ".defold_ai_capture_request"
local OUTPUT  = ".defold_ai_capture.png"

function init(self)
    print("[defold-ai helper] active; polling for capture requests")
    if screenshot == nil then
        print("[defold-ai helper] WARNING: 'screenshot' module missing — " ..
              "add britzl/defold-screenshot to game.project dependencies.")
    end
    self.busy = false
end

local function _attempt_capture(self)
    if not screenshot then
        os.remove(TRIGGER)
        self.busy = false
        return
    end
    screenshot.png(function(_, image_bytes, w, h)
        local f = io.open(OUTPUT, "wb")
        if f then
            f:write(image_bytes)
            f:close()
            print(("[defold-ai helper] captured %dx%d (%d bytes)"):format(
                w, h, #image_bytes))
        else
            print("[defold-ai helper] could not write " .. OUTPUT)
        end
        os.remove(TRIGGER)
        self.busy = false
    end)
end

function update(self, dt)
    if self.busy then return end
    local f = io.open(TRIGGER, "rb")
    if not f then return end
    f:close()
    self.busy = true
    _attempt_capture(self)
end
]]

local _HELPER_GO = [[
components {
  id: "script"
  component: "/defold_ai/helper.script"
}
]]

local _DEP_URL = "https://github.com/britzl/defold-screenshot/archive/master.zip"

function M.screenshot_install(body)
  body = body or {}
  local results = { ok = true, created = {}, edited = {} }

  -- 1. /defold_ai/helper.script
  local script_path = "defold_ai/helper.script"
  if not _file_exists(script_path) then
    editor.create_resources({ { "/" .. script_path, _HELPER_SCRIPT } })
    table.insert(results.created, "/" .. script_path)
  end

  -- 2. /defold_ai/helper.go
  local go_path = "defold_ai/helper.go"
  if not _file_exists(go_path) then
    editor.create_resources({ { "/" .. go_path, _HELPER_GO } })
    table.insert(results.created, "/" .. go_path)
  end

  -- 3. game.project [project] dependencies
  local gp = util.read_file("game.project") or ""
  if not gp:find(_DEP_URL, 1, true) then
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
    results.note = "Open Defold > Project > Fetch Libraries to pull the extension, " ..
                   "then project_run again to make the helper active."
  end

  -- 4. Optionally wire the helper into main.collection
  if body.auto_wire then
    local main_path = "main/main.collection"
    local content = util.read_file(main_path)
    if content and not content:find('prototype:%s*"/defold_ai/helper%.go"') then
      if content:sub(-1) ~= "\n" then content = content .. "\n" end
      content = content ..
        'instances {\n' ..
        '  id: "defold_ai_helper"\n' ..
        '  prototype: "/defold_ai/helper.go"\n' ..
        '  position { x: 0 y: 0 z: 0 }\n' ..
        '  rotation { x: 0 y: 0 z: 0 w: 1 }\n' ..
        '  scale3 { x: 1 y: 1 z: 1 }\n' ..
        '}\n'
      util.write_file(main_path, content)
      table.insert(results.edited, "/" .. main_path .. " (+defold_ai_helper instance)")
    end
  else
    results.next_step = "Add an instance of /defold_ai/helper.go to your " ..
      "main.collection (or pass auto_wire=true to have install do it for you)."
  end

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
