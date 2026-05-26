-- Collection (.collection) handlers.

local util = require "mcp.lib.util"
local gameobject = require "mcp.handlers.gameobject"

local M = {}

local function walk(node, depth, max_depth, out)
  if depth > max_depth then return end
  if not editor.can_get(node, "children") then return end
  local kids = editor.get(node, "children") or {}
  for _, child in ipairs(kids) do
    local name = util.try_get(child, "id") or util.try_get(child, "name") or "?"
    local type_str = "unknown"
    if editor.can_get(child, "type") then
      type_str = tostring(editor.get(child, "type"))
    end
    table.insert(out, {
      name = tostring(name),
      type = type_str,
      depth = depth,
      child_count = editor.can_get(child, "children")
                    and #(editor.get(child, "children") or {}) or 0,
    })
    walk(child, depth + 1, max_depth, out)
  end
end

-- ============ Helpers for raw file-based add_instance ============
-- We avoid editor.transact for collection-level inserts because it doesn't
-- support adding embedded_instances reliably; instead we append text blocks
-- to the .collection file (still proto-text, just raw I/O).

local function _format_vec3(v, default_one)
  v = v or {}
  local def = default_one and 1.0 or 0.0
  return string.format("{ x: %s y: %s z: %s }",
    tostring(v.x or v[1] or def),
    tostring(v.y or v[2] or def),
    tostring(v.z or v[3] or def))
end

local function _format_quat(v)
  v = v or {}
  return string.format("{ x: %s y: %s z: %s w: %s }",
    tostring(v.x or v[1] or 0),
    tostring(v.y or v[2] or 0),
    tostring(v.z or v[3] or 0),
    tostring(v.w or v[4] or 1))
end

-- Render `children: "..."` lines (one per child id). Defold parent-child in
-- collections is expressed on the parent instance, not the child.
local function _children_block(children)
  if not children or #children == 0 then return "" end
  local out = {}
  for _, child_id in ipairs(children) do
    table.insert(out, '  children: "' .. tostring(child_id) .. '"')
  end
  return table.concat(out, "\n") .. "\n"
end

-- Render `component_properties { ... }` blocks for per-instance script
-- property overrides. `props` is a table mapping component id (the script's
-- component id, usually "script") to a property dict.
local function _detect_prop_type(v)
  if type(v) == "number" then return "PROPERTY_TYPE_NUMBER", tostring(v) end
  if type(v) == "boolean" then return "PROPERTY_TYPE_BOOLEAN", v and "true" or "false" end
  if type(v) == "string" then
    if v:match("^hash:") then return "PROPERTY_TYPE_HASH", v:sub(6) end
    if v:match("^url:") then return "PROPERTY_TYPE_URL", v:sub(5) end
    return "PROPERTY_TYPE_HASH", v
  end
  if type(v) == "table" then
    if v.w ~= nil then
      return "PROPERTY_TYPE_VECTOR4", string.format("%s,%s,%s,%s", v.x or 0, v.y or 0, v.z or 0, v.w)
    elseif v.z ~= nil then
      return "PROPERTY_TYPE_VECTOR3", string.format("%s,%s,%s", v.x or 0, v.y or 0, v.z or 0)
    end
  end
  return "PROPERTY_TYPE_NUMBER", "0"
end

local function _script_properties_block(props)
  if not props then return "" end
  local out = {}
  for comp_id, prop_dict in pairs(props) do
    table.insert(out, '  component_properties {')
    table.insert(out, '    id: "' .. tostring(comp_id) .. '"')
    for pname, pvalue in pairs(prop_dict) do
      local ptype, pstr = _detect_prop_type(pvalue)
      table.insert(out, '    properties {')
      table.insert(out, '      id: "' .. tostring(pname) .. '"')
      table.insert(out, '      value: "' .. pstr .. '"')
      table.insert(out, '      type: ' .. ptype)
      table.insert(out, '    }')
    end
    table.insert(out, '  }')
  end
  if #out == 0 then return "" end
  return table.concat(out, "\n") .. "\n"
end

local function _instance_block(kind, id, body)
  -- kind is "instances" (reference), "embedded_instances" (inline GO),
  -- or "collection_instances" (reference to a .collection).
  local pos = _format_vec3(body.position, false)
  local rot = _format_quat(body.rotation)
  local sca = _format_vec3(body.scale, true)
  local children = _children_block(body.children)
  local props = _script_properties_block(body.script_properties)
  if kind == "collection_instances" then
    local proto = util.norm_resource_path(body.collection or "")
    return string.format(
      "collection_instances {\n  id: \"%s\"\n  collection: \"%s\"\n%s%s  position %s\n  rotation %s\n  scale3 %s\n}\n",
      id, proto, children, props, pos, rot, sca
    )
  elseif kind == "instances" then
    local prototype = util.norm_resource_path(body.prototype or "")
    return string.format(
      "instances {\n  id: \"%s\"\n  prototype: \"%s\"\n%s%s  position %s\n  rotation %s\n  scale3 %s\n}\n",
      id, prototype, children, props, pos, rot, sca
    )
  else
    -- Embedded: render the GO body using gameobject's renderer, then escape it.
    local go_body = gameobject._render_go_file(body.components or {})
    local escaped_lines = {}
    for line in go_body:gmatch("([^\n]*)\n?") do
      if line ~= "" then
        local esc = line:gsub('\\', '\\\\'):gsub('"', '\\"')
        table.insert(escaped_lines, '  "' .. esc .. '\\n"')
      end
    end
    table.insert(escaped_lines, '  ""')
    return string.format(
      "embedded_instances {\n  id: \"%s\"\n  data:\n%s\n%s%s  position %s\n  rotation %s\n  scale3 %s\n}\n",
      id, table.concat(escaped_lines, '\n'), children, props, pos, rot, sca
    )
  end
end

function M.manage(body)
  local op = body.op or ""
  local params = body.params or {}

  if op == "create" then
    local path = util.norm_resource_path(params.path or "")
    if path == "" then
      return util.error_response("MISSING_PARAM", "create requires params.path")
    end
    local name = params.name or path:match("([^/]+)%.collection$") or "main"
    local content = string.format(
      "name: \"%s\"\nscale_along_z: 0\n", name
    )
    editor.create_resources({ { path, content } })
    return { ok = true, path = path, name = name }

  elseif op == "save_as" then
    return util.error_response("NOT_IMPLEMENTED",
      "Defold's editor API does not yet expose save-as; use filesystem_manage(op='write_text') to write a new file.")

  elseif op == "get_roots" then
    return util.error_response("NOT_IMPLEMENTED",
      "Listing open collections is not exposed by the editor API yet.")

  elseif op == "open" then
    return M.open({ path = params.path })

  elseif op == "save" then
    return M.save({})

  elseif op == "add_instance" then
    -- Append a reference instance to an existing .collection file.
    -- params: path (the collection), id, prototype (.go path),
    --         position?, rotation?, scale?
    local path = util.norm_resource_path(params.path or "")
    if path == "" then return util.error_response("MISSING_PARAM", "add_instance needs path") end
    local id = params.id or ""
    local proto = util.norm_resource_path(params.prototype or "")
    if id == "" or proto == "" then
      return util.error_response("MISSING_PARAM", "add_instance needs id + prototype")
    end
    local content, err = util.read_file(path)
    if not content then return util.error_response("READ_ERROR", err) end
    if content:sub(-1) ~= "\n" then content = content .. "\n" end
    content = content .. _instance_block("instances", id, params)
    local wok, werr = util.write_file(path, content)
    if not wok then return util.error_response("WRITE_ERROR", werr) end
    return { ok = true, path = path, id = id, prototype = proto }

  elseif op == "add_embedded" then
    -- Append an embedded GO instance to an existing .collection file.
    -- params: path, id, components (list), position?, rotation?, scale?,
    --         children? (list of sibling instance ids to parent under this one)
    local path = util.norm_resource_path(params.path or "")
    if path == "" then return util.error_response("MISSING_PARAM", "add_embedded needs path") end
    local id = params.id or ""
    if id == "" then return util.error_response("MISSING_PARAM", "add_embedded needs id") end
    if type(params.components) ~= "table" or #params.components == 0 then
      return util.error_response("MISSING_PARAM", "add_embedded needs non-empty components")
    end
    local content, err = util.read_file(path)
    if not content then return util.error_response("READ_ERROR", err) end
    if content:sub(-1) ~= "\n" then content = content .. "\n" end
    content = content .. _instance_block("embedded_instances", id, params)
    local wok, werr = util.write_file(path, content)
    if not wok then return util.error_response("WRITE_ERROR", werr) end
    return { ok = true, path = path, id = id, component_count = #params.components }

  elseif op == "add_collection_instance" then
    -- Append a collection reference instance (`collection_instances { ... }`).
    -- params: path (parent .collection), id, collection (the .collection to instance),
    --         position?, rotation?, scale?
    local path = util.norm_resource_path(params.path or "")
    if path == "" then return util.error_response("MISSING_PARAM", "add_collection_instance needs path") end
    local id = params.id or ""
    local coll = util.norm_resource_path(params.collection or "")
    if id == "" or coll == "" then
      return util.error_response("MISSING_PARAM", "add_collection_instance needs id + collection")
    end
    local content, err = util.read_file(path)
    if not content then return util.error_response("READ_ERROR", err) end
    if content:sub(-1) ~= "\n" then content = content .. "\n" end
    content = content .. _instance_block("collection_instances", id, params)
    local wok, werr = util.write_file(path, content)
    if not wok then return util.error_response("WRITE_ERROR", werr) end
    return { ok = true, path = path, id = id, collection = coll }

  elseif op == "set_parent" then
    -- Add a `children: "<child_id>"` line to an existing instance block.
    -- params: path, parent_id, child_id
    local path = util.norm_resource_path(params.path or "")
    local parent_id = params.parent_id or ""
    local child_id = params.child_id or ""
    if path == "" or parent_id == "" or child_id == "" then
      return util.error_response("MISSING_PARAM", "set_parent needs path + parent_id + child_id")
    end
    local content, err = util.read_file(path)
    if not content then return util.error_response("READ_ERROR", err) end
    -- Locate the parent block. Match `(embedded_)?instances {` containing id: "parent_id".
    local marker = 'id: "' .. parent_id .. '"'
    local id_pos = content:find(marker, 1, true)
    if not id_pos then return util.error_response("NOT_FOUND", "parent instance not found: " .. parent_id) end
    -- Find the closing `}` of that block (no nesting at top level of instance{}).
    local close_pos = content:find("\n}", id_pos, true)
    if not close_pos then return util.error_response("PARSE_ERROR", "could not find end of parent block") end
    -- Insert child line just before the closing brace, on its own line.
    local child_line = '  children: "' .. child_id .. '"\n'
    content = content:sub(1, close_pos) .. child_line .. content:sub(close_pos + 1)
    local wok, werr = util.write_file(path, content)
    if not wok then return util.error_response("WRITE_ERROR", werr) end
    return { ok = true, path = path, parent_id = parent_id, child_id = child_id }

  elseif op == "remove_instance" then
    local path = util.norm_resource_path(params.path or "")
    local id = params.id or ""
    if path == "" or id == "" then
      return util.error_response("MISSING_PARAM", "remove_instance needs path + id")
    end
    local content, err = util.read_file(path)
    if not content then return util.error_response("READ_ERROR", err) end
    -- Find any block of form `(embedded_)?instances { ... id: "<id>" ... }`
    -- We do a coarse scan: locate top-level `instances {` or `embedded_instances {`
    -- blocks and rebuild without the matching one.
    local out, i, removed = {}, 1, 0
    while true do
      local s = content:find("\n[%w_]*instances%s*{", i)
      if not s then
        table.insert(out, content:sub(i))
        break
      end
      table.insert(out, content:sub(i, s))  -- include newline
      -- Find matching closing brace by counting (instances blocks don't nest).
      local depth, j = 0, s + 1
      while j <= #content do
        local ch = content:sub(j, j)
        if ch == "{" then depth = depth + 1
        elseif ch == "}" then
          depth = depth - 1
          if depth == 0 then break end
        end
        j = j + 1
      end
      local block = content:sub(s + 1, j)
      if block:match('id:%s*"' .. id .. '"') then
        removed = removed + 1
        -- skip the trailing newline after the closing brace if any
        if content:sub(j + 1, j + 1) == "\n" then j = j + 1 end
      else
        table.insert(out, block)
      end
      i = j + 1
    end
    if removed == 0 then
      return util.error_response("NOT_FOUND", "no instance with id: " .. id)
    end
    local wok, werr = util.write_file(path, table.concat(out))
    if not wok then return util.error_response("WRITE_ERROR", werr) end
    return { ok = true, path = path, removed_id = id, removed_count = removed }
  end
  return util.error_response("UNKNOWN_OP", "Unknown collection_manage op: " .. op)
end

function M.get_hierarchy(body)
  local path = util.norm_resource_path(body.path or "")
  if path == "" then
    return util.error_response("MISSING_PARAM",
      "Provide params.path — the editor API needs an explicit collection path.")
  end
  if not editor.resource_attributes(path).exists then
    return util.error_response("NOT_FOUND", "Collection not found at " .. path)
  end
  local out = {}
  walk(path, 0, body.depth or 10, out)
  local offset = body.offset or 0
  local limit = body.limit or 100
  local sliced = {}
  for i = offset + 1, math.min(#out, offset + limit) do
    table.insert(sliced, out[i])
  end
  return { ok = true, root = path, total = #out, nodes = sliced, offset = offset, limit = limit }
end

function M.open(body)
  local path = util.norm_resource_path(body.path or "")
  if not editor.resource_attributes(path).exists then
    return util.error_response("NOT_FOUND", "Collection not found at " .. path)
  end
  return { ok = true, path = path, note = "Collection is accessible by path. UI tab open is manual." }
end

function M.save(body)
  editor.save()
  return { ok = true }
end

return M
