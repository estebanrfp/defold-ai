-- Script (.script, .gui_script, .render_script, .lua) handlers.

local util = require "mcp.lib.util"

local M = {}

local SCRIPT_EXTENSIONS = {
  [".script"] = true, [".gui_script"] = true,
  [".render_script"] = true, [".lua"] = true,
}

local function valid_script_path(path)
  for ext, _ in pairs(SCRIPT_EXTENSIONS) do
    if path:sub(-#ext) == ext then return true end
  end
  return false
end

function M.create(body)
  local path = util.norm_resource_path(body.path or "")
  if path == "" or not valid_script_path(path) then
    return util.error_response("INVALID_PATH",
      "Path must end in .script, .gui_script, .render_script, or .lua")
  end
  local content = body.content or ""
  editor.create_resources({ { path, content } })
  return { ok = true, path = path, size = #content }
end

function M.attach(body)
  local gameobject = body.gameobject or ""
  local script_path = util.norm_resource_path(body.script_path or "")
  if gameobject == "" or script_path == "" then
    return util.error_response("MISSING_PARAM", "attach needs gameobject + script_path")
  end
  if not editor.resource_attributes(script_path).exists then
    return util.error_response("NOT_FOUND", "Script not found: " .. script_path)
  end
  local id = body.id or ""
  if id == "" then
    id = "script_" .. tostring(math.random(1000, 9999))
  end
  editor.transact({
    editor.tx.add(gameobject, "components", {
      type = "component-reference",
      id = id,
      path = script_path,
    }),
  })
  editor.save()
  return { ok = true, gameobject = gameobject, component_id = id, script = script_path }
end

function M.patch(body)
  local path = util.norm_resource_path(body.path or "")
  local old_text = body.old_text or ""
  local new_text = body.new_text or ""
  local replace_all = body.replace_all == true

  if not valid_script_path(path) then
    return util.error_response("INVALID_PATH",
      "Path must end in .script, .gui_script, .render_script, or .lua")
  end

  -- Read via io (path resolution: convert res:// to project-relative)
  local relative = path:gsub("^/", "")
  local f, err = io.open(relative, "r")
  if not f then return util.error_response("READ_ERROR", tostring(err)) end
  local content = f:read("*a")
  f:close()

  local count
  if replace_all then
    local replaced
    replaced, count = string.gsub(content, old_text:gsub("[%(%)%.%%%+%-%*%?%[%]%^%$]", "%%%1"), new_text:gsub("%%", "%%%%"))
    if count == 0 then
      return util.error_response("OLD_TEXT_NOT_FOUND", "No matches for old_text")
    end
    content = replaced
  else
    local first = content:find(old_text, 1, true)
    if not first then
      return util.error_response("OLD_TEXT_NOT_FOUND", "old_text not found in file")
    end
    local second = content:find(old_text, first + #old_text, true)
    if second then
      return util.error_response("MULTIPLE_MATCHES",
        "old_text appears more than once; set replace_all=true or provide more context")
    end
    content = content:sub(1, first - 1) .. new_text .. content:sub(first + #old_text)
    count = 1
  end

  local out, write_err = io.open(relative, "w")
  if not out then return util.error_response("WRITE_ERROR", tostring(write_err)) end
  out:write(content)
  out:close()
  return { ok = true, path = path, replacements = count, size = #content }
end

function M.manage(body)
  local op = body.op or ""
  local params = body.params or {}
  if op == "read" then
    local path = util.norm_resource_path(params.path or "")
    if not valid_script_path(path) then
      return util.error_response("INVALID_PATH", "read requires a .script/.gui_script/.render_script/.lua path")
    end
    local relative = path:gsub("^/", "")
    local f, err = io.open(relative, "r")
    if not f then return util.error_response("READ_ERROR", tostring(err)) end
    local content = f:read("*a")
    f:close()
    local _, line_count = content:gsub("\n", "")
    return { ok = true, path = path, content = content, size = #content, line_count = line_count + 1 }
  elseif op == "detach" then
    local go = params.gameobject or ""
    local cid = params.component_id or ""
    if go == "" or cid == "" then
      return util.error_response("MISSING_PARAM", "detach needs gameobject + component_id")
    end
    local comps = editor.get(go, "components") or {}
    for i, c in ipairs(comps) do
      if tostring(util.try_get(c, "id")) == cid then
        editor.transact({ editor.tx.remove(go, "components", i - 1) })
        editor.save()
        return { ok = true, detached = cid }
      end
    end
    return util.error_response("NOT_FOUND", "Component not found: " .. cid)
  elseif op == "find_symbols" then
    -- Simple regex-based: list function names + go.property declarations.
    local path = util.norm_resource_path(params.path or "")
    local relative = path:gsub("^/", "")
    local f, err = io.open(relative, "r")
    if not f then return util.error_response("READ_ERROR", tostring(err)) end
    local content = f:read("*a")
    f:close()
    local functions, properties = {}, {}
    for fn in content:gmatch("function%s+([%w_:%.]+)%s*%(") do
      table.insert(functions, fn)
    end
    for p in content:gmatch("go%.property%s*%(\"([%w_]+)\"") do
      table.insert(properties, p)
    end
    return { ok = true, path = path, functions = functions, properties = properties }
  end
  return util.error_response("UNKNOWN_OP", "Unknown script_manage op: " .. op)
end

return M
