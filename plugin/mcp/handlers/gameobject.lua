-- Game object handlers — Defold's "node" equivalent.

local util = require "mcp.lib.util"

local M = {}

local function unique_id(prefix)
  prefix = prefix or "go"
  return prefix .. "_" .. tostring(os.time()) .. "_" .. tostring(math.random(1000, 9999))
end

-- ============ Protobuf-text serializer for embedded component data ============
-- Defold .go files store embedded component bodies as escaped protobuf-text
-- strings inside the `data:` field. We need to:
--   1. Render the body as standard pb-text (key: value, nested {})
--   2. Wrap each line in quotes with internal quotes escaped
--   3. Use Defold's multi-string concatenation convention (one quoted segment
--      per line, plus a trailing "" sentinel)
--
-- Input format (a Lua table of component spec):
--   { id="sprite", type="sprite", data = {
--       default_animation = "player",
--       material = "/builtins/materials/sprite.material",
--       textures = { { sampler="texture_sampler", texture="/x.atlas" } },
--   } }

local function _is_array(t)
  if type(t) ~= "table" then return false end
  local n = 0
  for _ in pairs(t) do n = n + 1 end
  for i = 1, n do
    if t[i] == nil then return false end
  end
  return n > 0
end

-- Render a Lua value to one or more pb-text lines. Returns a list of lines
-- (no trailing newlines). `key` is the field name; pass nil for root.
local function _render_pb(key, value, indent)
  indent = indent or 0
  local pad = string.rep("  ", indent)
  local lines = {}
  if type(value) == "table" then
    if _is_array(value) then
      -- Array → emit one block per item, all under the same key
      for _, v in ipairs(value) do
        for _, l in ipairs(_render_pb(key, v, indent)) do
          table.insert(lines, l)
        end
      end
    else
      table.insert(lines, pad .. (key and (key .. " {") or "{"))
      for k, v in pairs(value) do
        for _, l in ipairs(_render_pb(k, v, indent + 1)) do
          table.insert(lines, l)
        end
      end
      table.insert(lines, pad .. "}")
    end
  elseif type(value) == "string" then
    -- Heuristic: identifiers in ALL_CAPS_OR_PB are enum literals, not strings.
    if value:match("^[A-Z_][A-Z0-9_]*$") then
      table.insert(lines, pad .. key .. ": " .. value)
    else
      table.insert(lines, pad .. key .. ': "' .. value .. '"')
    end
  elseif type(value) == "number" then
    table.insert(lines, pad .. key .. ": " .. tostring(value))
  elseif type(value) == "boolean" then
    table.insert(lines, pad .. key .. ": " .. (value and "true" or "false"))
  end
  return lines
end

-- Render a `data` table to the "quoted multi-line string" form used by .go files.
local function _render_embedded_data(data_tbl)
  if type(data_tbl) ~= "table" then return '""' end
  local body_lines = {}
  for k, v in pairs(data_tbl) do
    for _, l in ipairs(_render_pb(k, v, 0)) do
      table.insert(body_lines, l)
    end
  end
  if #body_lines == 0 then return '""' end
  local quoted = {}
  for _, line in ipairs(body_lines) do
    -- Escape backslashes, then quotes; append \n; wrap in quotes.
    local escaped = line:gsub('\\', '\\\\'):gsub('"', '\\"')
    table.insert(quoted, '"' .. escaped .. '\\n"')
  end
  table.insert(quoted, '""')  -- trailing sentinel
  return table.concat(quoted, "\n  ")
end

-- Render a full .go file from a list of component specs.
local function render_go_file(components)
  local out = {}
  for _, c in ipairs(components or {}) do
    if c.component then
      -- Component reference: external script/atlas/etc.
      table.insert(out, "components {")
      table.insert(out, '  id: "' .. (c.id or "comp") .. '"')
      table.insert(out, '  component: "' .. util.norm_resource_path(c.component) .. '"')
      -- Optional script-property overrides
      for k, v in pairs(c.properties or {}) do
        if type(v) == "number" then
          table.insert(out, '  properties {')
          table.insert(out, '    id: "' .. k .. '"')
          table.insert(out, '    value: "' .. tostring(v) .. '"')
          table.insert(out, '    type: PROPERTY_TYPE_NUMBER')
          table.insert(out, '  }')
        end
      end
      table.insert(out, "}")
    else
      -- Embedded component: full pb-text body inside data: "..."
      table.insert(out, "embedded_components {")
      table.insert(out, '  id: "' .. (c.id or "comp") .. '"')
      table.insert(out, '  type: "' .. (c.type or "script") .. '"')
      table.insert(out, '  data: ' .. _render_embedded_data(c.data or {}))
      table.insert(out, "}")
    end
  end
  return table.concat(out, "\n") .. "\n"
end

-- ============ Public ops ============

function M.create(body)
  local collection = util.norm_resource_path(body.collection or "")
  if collection == "" then
    return util.error_response("MISSING_PARAM",
      "params.collection is required. To create a standalone .go file, use op='create_file' on gameobject_manage.")
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
  local prop_name = property
  if not property:find("^__") and property:sub(1, 1) == ":" then
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
  -- Paginated walk of a collection's tree, with name/type filters.
  --
  -- params:
  --   collection:    res:// path to a .collection (required)
  --   name_pattern:  substring (case-sensitive) the id must contain (optional)
  --   type_filter:   exact match against the GO's type string (optional)
  --   component_type: only match GOs that have a component of this type
  --                   (e.g. "model", "collisionobject", "camera") (optional)
  --   max_depth:     walk depth cap (default 16)
  --   offset / limit: pagination over the filtered match list (defaults 0/200)
  --
  -- Returns:
  --   matches:    [{ id, type, path, depth, component_types: [...] }]
  --   total:      total filtered count (before slicing)
  --   has_more:   bool
  local collection = util.norm_resource_path(body.collection or "")
  if collection == "" then
    return util.error_response("MISSING_PARAM", "find needs 'collection'")
  end
  if not editor.resource_attributes(collection).exists then
    return util.error_response("NOT_FOUND", "Collection not found at " .. collection)
  end
  local pattern = body.name_pattern or ""
  local type_filter = body.type_filter or ""
  local component_type = body.component_type or ""
  local max_depth = body.max_depth or 16
  local offset = body.offset or 0
  local limit = body.limit or 200

  local function comp_types(node)
    if not editor.can_get(node, "components") then return {} end
    local out = {}
    for _, c in ipairs(editor.get(node, "components") or {}) do
      local t = util.try_get(c, "type")
      if t then table.insert(out, tostring(t)) end
    end
    return out
  end

  local all = {}
  local function walk(node, depth)
    if depth > max_depth then return end
    if not editor.can_get(node, "children") then return end
    for _, child in ipairs(editor.get(node, "children") or {}) do
      local id = tostring(util.try_get(child, "id") or "")
      local t  = tostring(util.try_get(child, "type") or "?")
      local ctypes = comp_types(child)
      local ok = true
      if pattern ~= "" and not id:find(pattern, 1, true) then ok = false end
      if ok and type_filter ~= "" and t ~= type_filter then ok = false end
      if ok and component_type ~= "" then
        local has = false
        for _, ct in ipairs(ctypes) do
          if ct == component_type then has = true; break end
        end
        if not has then ok = false end
      end
      if ok then
        table.insert(all, {
          id = id, type = t, depth = depth,
          path = tostring(child),
          component_types = ctypes,
        })
      end
      walk(child, depth + 1)
    end
  end
  walk(collection, 0)

  local total = #all
  local sliced = {}
  for i = offset + 1, math.min(total, offset + limit) do
    table.insert(sliced, all[i])
  end
  return {
    ok = true, collection = collection,
    matches = sliced, total = total,
    offset = offset, limit = limit,
    has_more = (offset + #sliced) < total,
  }
end

function M.manage(body)
  local op = body.op or ""
  local params = body.params or {}

  if op == "create_file" then
    -- Create a standalone .go file with structured components + embedded
    -- components. Fixes the gap where gameobject_create only adds GOs to a
    -- collection (can't produce a reusable prototype file).
    --
    -- params:
    --   path:       res:// path ending in .go (required)
    --   components: list of { id, component? (path) | type, data? }
    local path = util.norm_resource_path(params.path or "")
    if path == "" then return util.error_response("MISSING_PARAM", "create_file needs path") end
    if not path:match("%.go$") then
      return util.error_response("INVALID_PARAM", "create_file path must end in .go")
    end
    local content = render_go_file(params.components or {})
    editor.create_resources({ { path, content } })
    return { ok = true, path = path, component_count = #(params.components or {}) }

  elseif op == "delete" then
    local path = params.path or ""
    if path == "" then return util.error_response("MISSING_PARAM", "delete needs path") end
    local coll, id = path:match("^(.-)!/(.+)$")
    if not coll then
      return util.error_response("INVALID_PATH", "Expected /collection!/id form, got: " .. path)
    end
    local kids = editor.get(coll, "children") or {}
    for i, child in ipairs(kids) do
      if tostring(util.try_get(child, "id")) == id then
        editor.transact({ editor.tx.remove(coll, "children", i - 1) })
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
      op .. " requires reading + reconstructing the node spec; planned for v0.3")
  end
  return util.error_response("UNKNOWN_OP", "Unknown gameobject_manage op: " .. op)
end

-- Expose the .go renderer so other handlers can reuse it.
M._render_go_file = render_go_file

return M
