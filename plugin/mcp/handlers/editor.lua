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

function M.screenshot(body)
  -- Defold doesn't expose a programmatic editor screenshot API yet (as of 1.10.x).
  -- For now we return a stub indicating the feature is pending.
  -- Workaround: take a screenshot of the running game via OS clipboard.
  return util.error_response(
    "NOT_IMPLEMENTED",
    "editor_screenshot is not yet supported by Defold's editor scripting API. " ..
    "Build & run the project, then take a screenshot of the game window manually."
  )
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
