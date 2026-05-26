-- Input binding handler — edit /input/game.input_binding.

local util = require "mcp.lib.util"

local M = {}

local DEFAULT_PATH = "/input/game.input_binding"

local function read_file(path)
  local local_path = path:gsub("^/", "")
  local f = io.open(local_path, "r")
  if not f then return nil, "could not open " .. path end
  local content = f:read("*a")
  f:close()
  return content
end

local function write_file(path, content)
  local local_path = path:gsub("^/", "")
  local f, err = io.open(local_path, "w")
  if not f then return false, err end
  f:write(content)
  f:close()
  return true
end

function M.manage(body)
  local op = body.op or ""
  local params = body.params or {}
  local path = util.norm_resource_path(params.path or DEFAULT_PATH)

  if op == "list" then
    local content, err = read_file(path)
    if not content then return util.error_response("READ_ERROR", err) end
    local triggers = {}
    for kind, input, action in content:gmatch("(%w+)_trigger%s*{%s*input:%s*([%w_]+)%s*action:%s*\"([^\"]+)\"") do
      table.insert(triggers, { kind = kind, input = input, action = action })
    end
    return { ok = true, path = path, triggers = triggers }
  elseif op == "add_key" or op == "add_mouse" or op == "add_gamepad" or op == "add_touch" then
    local kind = op:sub(5)
    local input = params.input or ""
    local action = params.action or ""
    if input == "" or action == "" then
      return util.error_response("MISSING_PARAM", op .. " needs input + action")
    end
    local content, err = read_file(path)
    if not content then return util.error_response("READ_ERROR", err) end
    local block = string.format("%s_trigger {\n  input: %s\n  action: \"%s\"\n}\n", kind, input, action)
    content = content .. "\n" .. block
    local ok, werr = write_file(path, content)
    if not ok then return util.error_response("WRITE_ERROR", tostring(werr)) end
    return { ok = true, kind = kind, input = input, action = action }
  end
  return util.error_response("UNKNOWN_OP", "Unknown input_binding_manage op: " .. op)
end

return M
