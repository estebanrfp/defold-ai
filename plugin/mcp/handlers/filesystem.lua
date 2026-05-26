-- Filesystem handlers — read/write text files within the Defold project.

local util = require "mcp.lib.util"

local M = {}

local function res_to_local(path)
  return path:gsub("^/", "")
end

function M.manage(body)
  local op = body.op or ""
  local params = body.params or {}
  if op == "read_text" then
    local path = util.norm_resource_path(params.path or "")
    local f, err = io.open(res_to_local(path), "r")
    if not f then return util.error_response("READ_ERROR", tostring(err)) end
    local content = f:read("*a")
    f:close()
    local _, lc = content:gsub("\n", "")
    return { ok = true, path = path, content = content, size = #content, line_count = lc + 1 }
  elseif op == "write_text" then
    local path = util.norm_resource_path(params.path or "")
    local content = params.content or ""
    local dir = res_to_local(path):match("^(.*)/[^/]+$")
    if dir and dir ~= "" then
      pcall(function() editor.create_directory("/" .. dir) end)
    end
    local f, err = io.open(res_to_local(path), "w")
    if not f then return util.error_response("WRITE_ERROR", tostring(err)) end
    f:write(content)
    f:close()
    return { ok = true, path = path, size = #content }
  elseif op == "mkdir" then
    editor.create_directory(util.norm_resource_path(params.path or ""))
    return { ok = true }
  elseif op == "rm" then
    local ok, err = os.remove(res_to_local(util.norm_resource_path(params.path or "")))
    if not ok then return util.error_response("RM_ERROR", tostring(err)) end
    return { ok = true }
  elseif op == "reimport" then
    return { ok = true, note = "Defold auto-reimports on save." }
  elseif op == "search" then
    return util.error_response("NOT_IMPLEMENTED", "search planned for v0.2.")
  end
  return util.error_response("UNKNOWN_OP", "Unknown filesystem_manage op: " .. op)
end

return M
