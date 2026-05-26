-- Shared utilities for defold-ai handlers.

local M = {}

-- Count entries in a (sparse) table.
function M.count_tools(t)
  local n = 0
  for _ in pairs(t) do n = n + 1 end
  return n
end

-- Persist the editor's HTTP URL so the Python MCP server can find it.
-- Note: io.* in editor scripts is restricted to the project directory in
-- recent Defold versions. We write to the project root as a fallback when
-- writing to $HOME is not permitted.
function M.write_url_file(url)
  -- Try $HOME first (editor scripts in 1.10.4+ have some absolute-path access
  -- for explicitly-listed safe locations).
  local home = os.getenv("HOME") or os.getenv("USERPROFILE")
  if home then
    local path = home .. "/.defold_ai_url"
    local f, err = io.open(path, "w")
    if f then
      f:write(url)
      f:close()
      return path
    end
  end
  -- Fallback: write into the project so the URL is at least discoverable.
  local f, err = io.open(".defold_ai_url", "w")
  if f then
    f:write(url)
    f:close()
    return ".defold_ai_url"
  end
  error("could not write URL file: " .. tostring(err))
end

-- Build a Vector3-like dict from {x, y, z} table or array.
function M.parse_vec3(v, default)
  default = default or { 0, 0, 0 }
  if type(v) ~= "table" then return default end
  if v.x ~= nil then return { v.x, v.y or 0, v.z or 0 } end
  return { v[1] or 0, v[2] or 0, v[3] or 0 }
end

-- Vector4 / quaternion. Default identity.
function M.parse_quat(v, default)
  default = default or { 0, 0, 0, 1 }
  if type(v) ~= "table" then return default end
  if v.x ~= nil then return { v.x, v.y or 0, v.z or 0, v.w or 1 } end
  return { v[1] or 0, v[2] or 0, v[3] or 0, v[4] or 1 }
end

-- Safe property getter — returns nil instead of throwing if not gettable.
function M.try_get(node, prop)
  if editor.can_get(node, prop) then
    return editor.get(node, prop)
  end
  return nil
end

-- Standardized error response for handler functions.
function M.error_response(code, message, extra)
  local r = { ok = false, error = code, message = message }
  if extra then
    for k, v in pairs(extra) do r[k] = v end
  end
  return r
end

-- Ensure a resource path looks like a Defold res:// path.
function M.norm_resource_path(path)
  if not path or path == "" then return path end
  if path:sub(1, 1) ~= "/" then
    path = "/" .. path
  end
  return path
end

return M
