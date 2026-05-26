-- Editor-level handlers: state, screenshot, manage, reload.

local util = require "mcp.lib.util"

local M = {}

function M.state(body)
  local current_collection = ""
  -- Best-effort: editor scripts can't always know which collection is open.
  -- We expose what we can.
  return {
    ok = true,
    version = sys and sys.get_engine_info and sys.get_engine_info().version or "unknown",
    http_url = http.server.url,
    readiness = "ready",
    current_collection = current_collection,
  }
end

-- Best-effort screenshot of either the editor window or the running game
-- window. Defold has no editor-side capture API (as of 1.12.x); we shell out
-- to the host OS instead.
--
-- macOS: uses `screencapture`; needs Screen Recording permission for Terminal
--   (or whatever process owns the editor-script HTTP server). When permission
--   is missing the OS silently writes no file and `screencapture` exits 0 —
--   we detect the absence and return SCREENSHOT_DENIED with a clear path to
--   grant permission.
-- Linux / Windows: not yet implemented.
--
-- params:
--   target: "game" (default — uses dmengine window) | "editor"
--   path:   absolute path to write the PNG (default: /tmp/defold_ai_screenshot.png)
function M.screenshot(body)
  body = body or {}
  local target = body.target or "game"
  local out_path = body.path or "/tmp/defold_ai_screenshot.png"
  local proc = (target == "editor") and "Defold" or "dmengine"

  -- Best-effort: clear any stale output so we can detect a silent failure.
  os.remove(out_path)

  -- macOS path: try window-targeted capture first, fall back to full screen.
  -- Either approach requires Screen Recording permission for whatever process
  -- spawned the editor — usually Terminal, iTerm, or your MCP client.
  local discover_cmd = string.format(
    [[osascript -e 'tell application "System Events"
       set procs to (every process whose name contains "%s")
       if procs is {} then return ""
       set the_proc to item 1 of procs
       tell the_proc
         if (count of windows) is 0 then return ""
         return id of first window
       end tell
     end tell' 2>/dev/null]],
    proc)
  local id_out = util.run_shell(discover_cmd) or ""
  local window_id = id_out:gsub("%s+$", "")
  local mode = "window"
  local cap_cmd
  if window_id ~= "" then
    cap_cmd = "screencapture -l " .. window_id .. " -x -t png '" .. out_path .. "' 2>&1"
  else
    -- Either osascript can't see the window or the user hasn't approved
    -- accessibility for the shell. Fall back to full-screen capture; it'll
    -- still need Screen Recording permission, but doesn't need Accessibility.
    mode = "full_screen"
    cap_cmd = "screencapture -x -t png '" .. out_path .. "' 2>&1"
  end
  local cap_out = util.run_shell(cap_cmd) or ""
  local f = io.open(out_path, "rb")
  if not f then
    -- macOS silently exits 0 on permission denial; the absence of a file is
    -- the only reliable signal. Surface an actionable error.
    return util.error_response("SCREENSHOT_DENIED",
      "screencapture wrote no file. macOS blocked the call. Grant Screen " ..
      "Recording permission to whatever process spawned the editor (usually " ..
      "Terminal / iTerm / your MCP client) under System Settings > Privacy & " ..
      "Security > Screen Recording, then restart that process.",
      {
        target = target, mode = mode, window_id = window_id,
        screencapture_output = cap_out,
        host_os = util.detect_os and util.detect_os() or "darwin",
      })
  end
  local size = f:seek("end") or 0
  f:close()
  return {
    ok = true, target = target, mode = mode, path = out_path,
    window_id = (window_id ~= "" and window_id or nil),
    size = size, process = proc,
  }
end

function M.manage(body)
  local op = body.op or ""
  local params = body.params or {}
  if op == "state" then
    return M.state(body)
  elseif op == "selection_get" then
    -- Editor scripts don't currently expose the active selection.
    return util.error_response("NOT_IMPLEMENTED", "selection_get not exposed by Defold API yet")
  elseif op == "logs_clear" then
    -- print is sequential; can't clear retroactively, but we acknowledge.
    return { ok = true, note = "Editor console clear is not programmatic in Defold; user can clear via the UI." }
  end
  return util.error_response("UNKNOWN_OP", "Unknown editor_manage op: " .. op)
end

function M.reload_plugin(body)
  -- Invalidate cached `require` entries for our handler modules so the next
  -- HTTP request reloads them from disk. Defold won't re-run the entry-point
  -- script without "Project > Reload Editor Scripts", but module-level edits
  -- inside handlers/ + lib/ become live immediately after this call.
  local reloaded = {}
  for name, _ in pairs(package.loaded or {}) do
    if name:find("^mcp%.") then
      package.loaded[name] = nil
      table.insert(reloaded, name)
    end
  end
  return {
    ok = true,
    reloaded_modules = reloaded,
    note = "Module require-cache cleared. Restart Defold (or use Project > Reload Editor Scripts) for entry-point changes.",
  }
end

return M
