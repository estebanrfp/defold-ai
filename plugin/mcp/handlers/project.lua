-- Project handlers — build, run, settings, logs, batch.

local util = require "mcp.lib.util"

local M = {}

-- In-memory log buffer — captured via on_build_started / on_target_launched hooks.
-- Editor scripts can't directly hook into the console, but we can log our own
-- actions and surface them for logs_read.
local LOG_BUFFER = {}
local MAX_LOG_LINES = 500

local function log_line(level, source, text)
  table.insert(LOG_BUFFER, { level = level, source = source, text = text, t = os.time() })
  while #LOG_BUFFER > MAX_LOG_LINES do
    table.remove(LOG_BUFFER, 1)
  end
  print("[" .. source .. "] " .. text)
end

function M.run(body)
  local mode = body.mode or "main"
  -- Defold's editor scripts cannot trigger the Build/Run menu directly.
  -- The recommended path is editor.bob() for headless build, but launching
  -- a debug session typically requires user action in the editor UI.
  log_line("info", "defold-ai", "project_run requested (mode=" .. mode .. ")")
  return {
    ok = true,
    note = "Defold's editor scripting API does not yet expose Run programmatically. " ..
           "Use Project > Build or press F5/Cmd+B in the editor.",
    mode = mode,
  }
end

function M.manage(body)
  local op = body.op or ""
  local params = body.params or {}
  if op == "stop" then
    log_line("info", "defold-ai", "project_manage stop requested")
    return { ok = true, note = "Stop must be triggered manually from the editor (Project > Stop or Cmd+.)" }
  elseif op == "build" then
    -- Try editor.bob if available; otherwise hint at UI.
    if editor and editor.bob then
      local ok, err = pcall(function()
        editor.bob({ build = true, archive = false }, "build", "resolve")
      end)
      if not ok then return util.error_response("BUILD_ERROR", tostring(err)) end
      return { ok = true, note = "Headless build via bob completed" }
    end
    return { ok = true, note = "editor.bob not available in this Defold version; use Project > Build" }
  elseif op == "settings_get" then
    local key = params.key or ""
    if key == "" then return util.error_response("MISSING_PARAM", "settings_get needs key") end
    -- Read game.project as INI
    local f = io.open("game.project", "r")
    if not f then return util.error_response("READ_ERROR", "could not read game.project") end
    local content = f:read("*a")
    f:close()
    local section, prop = key:match("^([^.]+)%.(.+)$")
    if not section then return util.error_response("INVALID_KEY", "key must be 'section.prop'") end
    local pattern = "%[" .. section .. "%]([^%[]*)"
    local section_body = content:match(pattern)
    if not section_body then return { ok = true, key = key, value = nil } end
    local value = section_body:match(prop .. "%s*=%s*([^\n]+)")
    return { ok = true, key = key, value = value and value:match("^%s*(.-)%s*$") }
  elseif op == "settings_set" then
    return util.error_response("NOT_IMPLEMENTED",
      "settings_set requires INI rewrite; planned for v0.2. Workaround: edit /game.project via filesystem_manage write_text.")
  elseif op == "info" then
    return {
      ok = true,
      project_root = ".",
      version = sys and sys.get_engine_info and sys.get_engine_info().version or "unknown",
    }
  end
  return util.error_response("UNKNOWN_OP", "Unknown project_manage op: " .. op)
end

function M.logs_read(body)
  local source = body.source or "editor"
  local count = body.count or 50
  local offset = body.offset or 0
  local out = {}
  local start_i = math.max(1, #LOG_BUFFER - offset - count + 1)
  local end_i = math.max(1, #LOG_BUFFER - offset)
  for i = start_i, end_i do
    local entry = LOG_BUFFER[i]
    if entry and (source == "all" or source == entry.source or
                 (source == "editor" and entry.source == "defold-ai")) then
      table.insert(out, entry)
    end
  end
  return { ok = true, source = source, lines = out, total_count = #LOG_BUFFER }
end

function M.batch_execute(body)
  local steps = body.steps or {}
  local results = {}
  for i, step in ipairs(steps) do
    -- Note: batch_execute is a no-op stub for v0.1 — most MCP clients prefer
    -- sequential calls anyway. Returns the request unchanged.
    table.insert(results, {
      index = i,
      tool = step.tool,
      ok = false,
      error = "NOT_IMPLEMENTED",
      message = "batch_execute will route to other handlers in v0.2.",
    })
  end
  return { ok = true, results = results }
end

-- Expose for other handlers to log into the same buffer.
M._log = log_line

return M
