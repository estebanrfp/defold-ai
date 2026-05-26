-- Collection (.collection) handlers.

local util = require "mcp.lib.util"

local M = {}

-- Walk children of a collection node recursively.
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

function M.manage(body)
  local op = body.op or ""
  local params = body.params or {}
  if op == "create" then
    local path = util.norm_resource_path(params.path or "")
    if path == "" then
      return util.error_response("MISSING_PARAM", "create requires params.path")
    end
    -- Generate a minimal valid .collection text.
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
  -- The editor API doesn't expose a programmatic "open" for a tab; the file
  -- becomes accessible via path-based editor.get/transact regardless. We
  -- treat this as a no-op success when the file exists.
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
