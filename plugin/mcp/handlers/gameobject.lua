-- Game object handlers — Defold's "node" equivalent.

local util = require "mcp.lib.util"

local M = {}

-- Generate a unique id by appending an integer.
local function unique_id(prefix)
  prefix = prefix or "go"
  return prefix .. "_" .. tostring(os.time()) .. "_" .. tostring(math.random(1000, 9999))
end

function M.create(body)
  local collection = util.norm_resource_path(body.collection or "")
  if collection == "" then
    return util.error_response("MISSING_PARAM", "params.collection is required (e.g. /main/main.collection)")
  end
  if not editor.resource_attributes(collection).exists then
    return util.error_response("NOT_FOUND", "Collection not found at " .. collection)
  end
  if not editor.can_add(collection, "children") then
    return util.error_response("NOT_ALLOWED", "Cannot add children to " .. collection)
  end
  local id = body.id or ""
  if id == "" then id = unique_id() end

  local go_spec = {
    id = id,
    position = util.parse_vec3(body.position),
    rotation = util.parse_quat(body.rotation),
    scale    = util.parse_vec3(body.scale, { 1, 1, 1 }),
  }
  if body.reference and body.reference ~= "" then
    go_spec.type = "go-reference"
    go_spec.path = util.norm_resource_path(body.reference)
  else
    go_spec.type = "go"
    go_spec.components = body.components or {}
  end

  editor.transact({ editor.tx.add(collection, "children", go_spec) })
  editor.save()

  local out_path = collection .. "!/" .. id
  return { ok = true, path = out_path, id = id }
end

function M.set_property(body)
  local path = body.path or ""
  local property = body.property or ""
  if path == "" or property == "" then
    return util.error_response("MISSING_PARAM", "set_property needs both 'path' and 'property'")
  end
  -- Script-property overrides use the __ prefix in transactions.
  local prop_name = property
  if not property:find("^__") and property:sub(1, 1) == ":" then
    -- explicit "::prop" syntax forced as override
    prop_name = "__" .. property:sub(2)
  end
  editor.transact({ editor.tx.set(path, prop_name, body.value) })
  editor.save()
  return { ok = true, path = path, property = prop_name, value = body.value }
end

function M.get_properties(body)
  local path = body.path or ""
  if path == "" then
    return util.error_response("MISSING_PARAM", "get_properties needs 'path'")
  end
  local out = {}
  for _, prop in ipairs({ "id", "position", "rotation", "scale", "type", "children", "components" }) do
    if editor.can_get(path, prop) then
      local ok, val = pcall(editor.get, path, prop)
      if ok then out[prop] = val end
    end
  end
  return { ok = true, path = path, properties = out }
end

function M.find(body)
  local collection = util.norm_resource_path(body.collection or "")
  if collection == "" then
    return util.error_response("MISSING_PARAM", "find needs 'collection'")
  end
  local pattern = body.name_pattern or ""
  local type_filter = body.type_filter or ""
  local matches = {}
  local function walk(node)
    if editor.can_get(node, "children") then
      for _, child in ipairs(editor.get(node, "children") or {}) do
        local name = util.try_get(child, "id") or ""
        local match = (pattern == "" or string.find(tostring(name), pattern) ~= nil)
        if match then
          table.insert(matches, { name = tostring(name), node = tostring(child) })
        end
        walk(child)
      end
    end
  end
  walk(collection)
  return { ok = true, matches = matches }
end

function M.manage(body)
  local op = body.op or ""
  local params = body.params or {}
  if op == "delete" then
    -- Delete via removing from the parent collection's children list.
    local path = params.path or ""
    if path == "" then return util.error_response("MISSING_PARAM", "delete needs path") end
    -- We expect path like "/main/main.collection!/go_id"
    local coll, id = path:match("^(.-)!/(.+)$")
    if not coll then
      return util.error_response("INVALID_PATH", "Expected /collection!/id form, got: " .. path)
    end
    local kids = editor.get(coll, "children") or {}
    for i, child in ipairs(kids) do
      if tostring(util.try_get(child, "id")) == id then
        editor.transact({ editor.tx.remove(coll, "children", i - 1) })  -- 0-based
        editor.save()
        return { ok = true, deleted = path }
      end
    end
    return util.error_response("NOT_FOUND", "GO id not found in collection: " .. id)
  elseif op == "get_children" then
    local path = params.path or ""
    if path == "" then return util.error_response("MISSING_PARAM", "get_children needs path") end
    local kids = editor.get(path, "children") or {}
    local out = {}
    for _, c in ipairs(kids) do
      table.insert(out, {
        id = tostring(util.try_get(c, "id") or "?"),
        type = tostring(util.try_get(c, "type") or "?"),
      })
    end
    return { ok = true, children = out }
  elseif op == "duplicate" or op == "rename" or op == "reparent" then
    return util.error_response("NOT_IMPLEMENTED",
      op .. " requires reading + reconstructing the node spec; planned for v0.2")
  end
  return util.error_response("UNKNOWN_OP", "Unknown gameobject_manage op: " .. op)
end

return M
