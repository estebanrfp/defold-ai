-- Resource handlers — atlas, material, particlefx, font, etc.

local util = require "mcp.lib.util"

local M = {}

function M.manage(body)
  local op = body.op or ""
  local params = body.params or {}
  if op == "create" then
    local path = util.norm_resource_path(params.path or "")
    local content = params.content or ""
    if path == "" then
      return util.error_response("MISSING_PARAM", "create needs path")
    end
    editor.create_resources({ { path, content } })
    return { ok = true, path = path, size = #content }
  elseif op == "read" then
    local path = util.norm_resource_path(params.path or "")
    local relative = path:gsub("^/", "")
    local f, err = io.open(relative, "r")
    if not f then return util.error_response("READ_ERROR", tostring(err)) end
    local content = f:read("*a")
    f:close()
    return { ok = true, path = path, content = content, size = #content }
  elseif op == "write" then
    local path = util.norm_resource_path(params.path or "")
    local content = params.content or ""
    local relative = path:gsub("^/", "")
    local f, err = io.open(relative, "w")
    if not f then return util.error_response("WRITE_ERROR", tostring(err)) end
    f:write(content)
    f:close()
    return { ok = true, path = path, size = #content }
  elseif op == "delete" then
    local path = params.path or ""
    -- Defold doesn't expose programmatic resource deletion via editor.tx.
    -- Best-effort via filesystem.
    local relative = path:gsub("^/", "")
    local ok, err = os.remove(relative)
    if not ok then
      return util.error_response("DELETE_ERROR", tostring(err))
    end
    return { ok = true, deleted = path }
  elseif op == "list" then
    -- Use io.popen on POSIX would be blocked. Use editor.resource_attributes
    -- to walk known paths. Defold doesn't expose tree listing from editor
    -- scripts directly — limited support.
    return util.error_response("NOT_IMPLEMENTED",
      "Resource listing via editor scripts is limited. Use filesystem_manage(op='search') with name/type filters.")
  end
  return util.error_response("UNKNOWN_OP", "Unknown resource_manage op: " .. op)
end

-- ============ Material ============
function M.material_manage(body)
  local op = body.op or ""
  local params = body.params or {}
  if op == "create" then
    local path = util.norm_resource_path(params.path or "")
    if path == "" then
      return util.error_response("MISSING_PARAM", "create needs path")
    end
    local vp = params.vertex_program or "/builtins/materials/model.vp"
    local fp = params.fragment_program or "/builtins/materials/model.fp"
    -- Minimal .material text format (Protobuf text format)
    local content = string.format(
      "name: \"%s\"\nvertex_program: \"%s\"\nfragment_program: \"%s\"\n",
      path:match("([^/]+)%.material$") or "material", vp, fp
    )
    editor.create_resources({ { path, content } })
    return { ok = true, path = path }
  elseif op == "set_constant" or op == "get" then
    return util.error_response("NOT_IMPLEMENTED",
      op .. " requires structured .material edit; planned for v0.2. " ..
      "Workaround: use resource_manage(op='read'/'write') to edit the .material text directly.")
  end
  return util.error_response("UNKNOWN_OP", "Unknown material_manage op: " .. op)
end

-- ============ Particle FX ============
function M.particlefx_manage(body)
  local op = body.op or ""
  local params = body.params or {}
  if op == "create" then
    local path = util.norm_resource_path(params.path or "")
    if path == "" then
      return util.error_response("MISSING_PARAM", "create needs path")
    end
    -- Minimal empty particlefx (one default emitter)
    local content =
      "emitters {\n" ..
      "  id: \"emitter\"\n" ..
      "  mode: PLAY_MODE_LOOP\n" ..
      "  duration: 1.0\n" ..
      "  space: EMISSION_SPACE_WORLD\n" ..
      "}\n"
    editor.create_resources({ { path, content } })
    return { ok = true, path = path }
  elseif op == "apply_preset" then
    return util.error_response("NOT_IMPLEMENTED",
      "Preset library coming in v0.2 (rain, snow, smoke, sparkle, explosion).")
  end
  return util.error_response("UNKNOWN_OP", "Unknown particlefx_manage op: " .. op)
end

-- ============ Atlas ============
function M.atlas_manage(body)
  local op = body.op or ""
  local params = body.params or {}
  if op == "create" then
    local path = util.norm_resource_path(params.path or "")
    if path == "" then
      return util.error_response("MISSING_PARAM", "create needs path")
    end
    local content = "margin: 0\nextrude_borders: 2\ninner_padding: 0\n"
    editor.create_resources({ { path, content } })
    return { ok = true, path = path }
  end
  return util.error_response("NOT_IMPLEMENTED",
    "Atlas op '" .. op .. "' not yet implemented. Use resource_manage(read/write) for raw edits.")
end

return M
