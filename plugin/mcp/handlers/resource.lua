-- Resource handlers — atlas, tilesource, tilemap, material, particlefx, font.

local util = require "mcp.lib.util"

local M = {}

-- ============ Generic resource ops ============

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
    local content, err = util.read_file(path)
    if not content then return util.error_response("READ_ERROR", err) end
    return { ok = true, path = path, content = content, size = #content }
  elseif op == "write" then
    local path = util.norm_resource_path(params.path or "")
    local content = params.content or ""
    local ok, err = util.write_file(path, content)
    if not ok then return util.error_response("WRITE_ERROR", err) end
    return { ok = true, path = path, size = #content }
  elseif op == "delete" then
    local path = params.path or ""
    local relative = path:gsub("^/", "")
    -- Idempotent: if the file no longer exists, treat as success. Some sandbox
    -- versions return (nil, nil) from os.remove even on a successful delete,
    -- so we double-check via io.open before reporting an error.
    local pre_exists = io.open(relative, "r")
    if pre_exists then pre_exists:close() end
    if not pre_exists then
      return { ok = true, deleted = path, note = "already absent (no-op)" }
    end
    local ok, err = os.remove(relative)
    local post_exists = io.open(relative, "r")
    if post_exists then post_exists:close() end
    if post_exists then
      return util.error_response("DELETE_ERROR",
        "File still exists after os.remove: " .. tostring(err or "unknown"))
    end
    return { ok = true, deleted = path }
  elseif op == "list" then
    return util.error_response("NOT_IMPLEMENTED",
      "Resource listing via editor scripts is limited. Use filesystem_manage(op='search') with name/type filters.")
  end
  return util.error_response("UNKNOWN_OP", "Unknown resource_manage op: " .. op)
end

-- ============ Material ============
--
-- Defold .material is protobuf-text with this shape:
--   name: "..."
--   tags: "..."   (repeated)
--   vertex_program: "..."
--   fragment_program: "..."
--   vertex_space: VERTEX_SPACE_WORLD | VERTEX_SPACE_LOCAL
--   vertex_constants { name, type, value { x, y, z, w } }    (repeated)
--   fragment_constants { name, type, value { x, y, z, w } }  (repeated)
--   samplers { name, wrap_u, wrap_v, filter_min, filter_mag, max_anisotropy }
--   max_page_count: N

-- ---------- Tiny serializer for the structured create_full path ----------

local function _v4(v, default)
  v = v or default
  return string.format("{ x: %s y: %s z: %s w: %s }",
    tostring(v.x or v[1] or 0), tostring(v.y or v[2] or 0),
    tostring(v.z or v[3] or 0), tostring(v.w or v[4] or 1))
end

local function _const_block(kind, c)
  -- kind = "vertex_constants" | "fragment_constants"
  -- c = { name, type? (default CONSTANT_TYPE_USER), value? (vec4) }
  local t = c.type or "CONSTANT_TYPE_USER"
  local v = _v4(c.value, { 0, 0, 0, 1 })
  return string.format(
    "%s {\n  name: \"%s\"\n  type: %s\n  value %s\n}\n",
    kind, c.name, t, v
  )
end

local function _sampler_block(s)
  -- s = { name, wrap_u?, wrap_v?, filter_min?, filter_mag?, max_anisotropy? }
  local lines = { "samplers {", '  name: "' .. s.name .. '"' }
  table.insert(lines, "  wrap_u: " .. (s.wrap_u or "WRAP_MODE_CLAMP_TO_EDGE"))
  table.insert(lines, "  wrap_v: " .. (s.wrap_v or "WRAP_MODE_CLAMP_TO_EDGE"))
  table.insert(lines, "  filter_min: " .. (s.filter_min or "FILTER_MODE_MIN_LINEAR"))
  table.insert(lines, "  filter_mag: " .. (s.filter_mag or "FILTER_MODE_MAG_LINEAR"))
  table.insert(lines, "  max_anisotropy: " .. tostring(s.max_anisotropy or 1.0))
  table.insert(lines, "}")
  return table.concat(lines, "\n") .. "\n"
end

local function _render_material(spec)
  -- spec = { name, vp, fp, tags=[], vertex_space?, vertex_constants=[],
  --         fragment_constants=[], samplers=[], max_page_count? }
  local out = {}
  table.insert(out, string.format('name: "%s"', spec.name))
  for _, tag in ipairs(spec.tags or {}) do
    table.insert(out, string.format('tags: "%s"', tag))
  end
  table.insert(out, string.format('vertex_program: "%s"', spec.vp))
  table.insert(out, string.format('fragment_program: "%s"', spec.fp))
  if spec.vertex_space then
    table.insert(out, "vertex_space: " .. spec.vertex_space)
  end
  local body = table.concat(out, "\n") .. "\n"
  for _, c in ipairs(spec.vertex_constants or {}) do
    body = body .. _const_block("vertex_constants", c)
  end
  for _, c in ipairs(spec.fragment_constants or {}) do
    body = body .. _const_block("fragment_constants", c)
  end
  for _, s in ipairs(spec.samplers or {}) do
    body = body .. _sampler_block(s)
  end
  body = body .. "max_page_count: " .. tostring(spec.max_page_count or 0) .. "\n"
  return body
end

-- ---------- Curated presets (ported from godot-ai's material library) ----------

-- Standard matrix-bind vertex constants for the builtin model shader.
local _STD_MTX = {
  { name = "mtx_worldview", type = "CONSTANT_TYPE_WORLDVIEW" },
  { name = "mtx_view",      type = "CONSTANT_TYPE_VIEW" },
  { name = "mtx_proj",      type = "CONSTANT_TYPE_PROJECTION" },
  { name = "mtx_normal",    type = "CONSTANT_TYPE_NORMAL" },
}

-- The single tex0 sampler used by every preset that needs a texture.
local _TEX0 = {
  { name = "tex0",
    wrap_u = "WRAP_MODE_REPEAT", wrap_v = "WRAP_MODE_REPEAT",
    filter_min = "FILTER_MODE_MIN_LINEAR", filter_mag = "FILTER_MODE_MAG_LINEAR" },
}

local PRESETS = {
  -- A lit, tintable model material based on the builtin model.vp/.fp pair.
  -- Useful for voxel blocks, props and player rigs.
  model_lit_tint = function()
    return {
      name = "model_lit_tint", tags = { "model" },
      vp = "/builtins/materials/model.vp",
      fp = "/builtins/materials/model.fp",
      vertex_space = "VERTEX_SPACE_WORLD",
      vertex_constants = {
        _STD_MTX[1], _STD_MTX[2], _STD_MTX[3], _STD_MTX[4],
        { name = "light", value = { 0.6, 1.0, 0.4, 1.0 } },
      },
      fragment_constants = {
        { name = "tint", value = { 1, 1, 1, 1 } },
      },
      samplers = _TEX0,
    }
  end,

  -- Same builtin shader but with the light direction set so it acts as a
  -- top-down "noon" lighting. The fragment shader still multiplies tint, so
  -- you can leave the white texture and just override the tint constant
  -- per-instance via model.set_constant.
  model_unlit_tint = function()
    -- The builtin model.fp does run a diffuse term, so "unlit" here means
    -- "very bright ambient" (clamps the diffuse term to ~white). For a true
    -- unlit shader use the sprite material instead.
    return {
      name = "model_unlit_tint", tags = { "model" },
      vp = "/builtins/materials/model.vp",
      fp = "/builtins/materials/model.fp",
      vertex_space = "VERTEX_SPACE_WORLD",
      vertex_constants = {
        _STD_MTX[1], _STD_MTX[2], _STD_MTX[3], _STD_MTX[4],
        { name = "light", value = { 0, 1, 0, 1 } },
      },
      fragment_constants = {
        { name = "tint", value = { 1, 1, 1, 1 } },
      },
      samplers = _TEX0,
    }
  end,

  -- Sky-dome gradient. Assumes /assets/shaders/sky.{vp,fp} exist
  -- (writes them if missing — see _ensure_sky_shaders).
  sky_gradient = function()
    return {
      name = "sky_gradient", tags = { "sky" },
      vp = "/assets/shaders/sky.vp",
      fp = "/assets/shaders/sky.fp",
      vertex_space = "VERTEX_SPACE_LOCAL",
      vertex_constants = {
        { name = "mtx_worldview", type = "CONSTANT_TYPE_WORLDVIEW" },
        { name = "mtx_proj",      type = "CONSTANT_TYPE_PROJECTION" },
      },
      fragment_constants = {
        { name = "top_color",     value = { 0.38, 0.55, 0.85, 1 } },
        { name = "horizon_color", value = { 0.78, 0.85, 0.92, 1 } },
        { name = "bottom_color", value = { 0.18, 0.18, 0.22, 1 } },
      },
    }
  end,

  -- Alias to the GUI builtin.
  gui_basic = function()
    return {
      _passthrough = "/builtins/materials/gui.material",
      name = "gui_basic",
    }
  end,

  -- Alias to the sprite builtin.
  sprite_basic = function()
    return {
      _passthrough = "/builtins/materials/sprite.material",
      name = "sprite_basic",
    }
  end,

  -- Alias to the tilemap builtin.
  tilemap_basic = function()
    return {
      _passthrough = "/builtins/materials/tile_map.material",
      name = "tilemap_basic",
    }
  end,
}

local function _ensure_sky_shaders()
  -- Write the sky shader pair if either file is missing. Self-contained so
  -- callers don't have to remember to bootstrap.
  local vp_path = "/assets/shaders/sky.vp"
  local fp_path = "/assets/shaders/sky.fp"
  if not util.read_file(vp_path) then
    editor.create_resources({ { vp_path,
      "#version 140\n\n" ..
      "in highp vec4 position;\n" ..
      "out highp vec3 var_local_pos;\n\n" ..
      "uniform vs_uniforms {\n" ..
      "    mediump mat4 mtx_worldview;\n" ..
      "    mediump mat4 mtx_proj;\n" ..
      "};\n\n" ..
      "void main() {\n" ..
      "    var_local_pos = position.xyz;\n" ..
      "    gl_Position = mtx_proj * mtx_worldview * vec4(position.xyz, 1.0);\n" ..
      "}\n" } })
  end
  if not util.read_file(fp_path) then
    editor.create_resources({ { fp_path,
      "#version 140\n\n" ..
      "in highp vec3 var_local_pos;\n" ..
      "out vec4 out_fragColor;\n\n" ..
      "uniform fs_uniforms {\n" ..
      "    mediump vec4 top_color;\n" ..
      "    mediump vec4 horizon_color;\n" ..
      "    mediump vec4 bottom_color;\n" ..
      "};\n\n" ..
      "void main() {\n" ..
      "    vec3 dir = normalize(var_local_pos);\n" ..
      "    float t = dir.y;\n" ..
      "    vec3 col;\n" ..
      "    if (t > 0.0) {\n" ..
      "        col = mix(horizon_color.rgb, top_color.rgb, pow(t, 0.7));\n" ..
      "    } else {\n" ..
      "        col = mix(horizon_color.rgb, bottom_color.rgb, -t);\n" ..
      "    }\n" ..
      "    out_fragColor = vec4(col, 1.0);\n" ..
      "}\n" } })
  end
end

-- Merge `overrides` into the preset blueprint. Tables go deep; scalars replace.
local function _merge(base, overrides)
  if type(overrides) ~= "table" then return base end
  for k, v in pairs(overrides) do
    if type(v) == "table" and type(base[k]) == "table" then
      base[k] = _merge(base[k], v)
    else
      base[k] = v
    end
  end
  return base
end

-- ---------- find/replace helper for set_constant ----------

local function _find_constant_block(content, kind, name)
  -- Returns (start, end) of a `<kind> { ... name: "<name>" ... }` block.
  local i = 1
  while true do
    local s = content:find(kind .. "%s*{", i)
    if not s then return nil end
    local depth, j = 0, s
    while j <= #content do
      local ch = content:sub(j, j)
      if ch == "{" then depth = depth + 1
      elseif ch == "}" then
        depth = depth - 1
        if depth == 0 then break end
      end
      j = j + 1
    end
    local block = content:sub(s, j)
    if block:match('name:%s*"' .. name .. '"') then
      return s, j
    end
    i = j + 1
  end
end

-- ---------- Public op ----------

function M.material_manage(body)
  local op = body.op or ""
  local params = body.params or {}

  if op == "list_presets" then
    local names = {}
    for k, _ in pairs(PRESETS) do table.insert(names, k) end
    table.sort(names)
    return { ok = true, presets = names }

  elseif op == "create" then
    -- Legacy minimal create (kept for back-compat). Use create_full for real
    -- constants/samplers/tags.
    local path = util.norm_resource_path(params.path or "")
    if path == "" then return util.error_response("MISSING_PARAM", "create needs path") end
    local vp = params.vertex_program or "/builtins/materials/model.vp"
    local fp = params.fragment_program or "/builtins/materials/model.fp"
    local content = string.format(
      "name: \"%s\"\nvertex_program: \"%s\"\nfragment_program: \"%s\"\nmax_page_count: 0\n",
      path:match("([^/]+)%.material$") or "material", vp, fp
    )
    editor.create_resources({ { path, content } })
    return { ok = true, path = path, mode = "minimal" }

  elseif op == "create_full" then
    local path = util.norm_resource_path(params.path or "")
    if path == "" then return util.error_response("MISSING_PARAM", "create_full needs path") end
    if not params.vertex_program or not params.fragment_program then
      return util.error_response("MISSING_PARAM",
        "create_full needs vertex_program + fragment_program")
    end
    local spec = {
      name = params.name or path:match("([^/]+)%.material$") or "material",
      tags = params.tags or { "model" },
      vp = util.norm_resource_path(params.vertex_program),
      fp = util.norm_resource_path(params.fragment_program),
      vertex_space = params.vertex_space,
      vertex_constants = params.vertex_constants or {},
      fragment_constants = params.fragment_constants or {},
      samplers = params.samplers or {},
      max_page_count = params.max_page_count or 0,
    }
    local content = _render_material(spec)
    editor.create_resources({ { path, content } })
    return { ok = true, path = path, mode = "full", size = #content }

  elseif op == "apply_preset" then
    local path = util.norm_resource_path(params.path or "")
    local preset_name = params.preset or ""
    if path == "" or preset_name == "" then
      return util.error_response("MISSING_PARAM", "apply_preset needs path + preset")
    end
    local builder = PRESETS[preset_name]
    if not builder then
      local names = {}
      for k, _ in pairs(PRESETS) do table.insert(names, k) end
      return util.error_response("UNKNOWN_PRESET",
        "preset '" .. preset_name .. "' not found. Available: " .. table.concat(names, ", "))
    end
    local spec = _merge(builder(), params.overrides or {})
    -- Passthrough presets: write a tiny .material that just imports the
    -- builtin. Caller can override `name` / `tags` for clarity.
    if spec._passthrough then
      local content = string.format(
        'name: "%s"\nvertex_program: "%s.vp"\nfragment_program: "%s.fp"\nmax_page_count: 0\n',
        spec.name,
        spec._passthrough:gsub("%.material$", ""),
        spec._passthrough:gsub("%.material$", "")
      )
      editor.create_resources({ { path, content } })
      return { ok = true, path = path, preset = preset_name, mode = "passthrough" }
    end
    -- Some presets need accompanying shader files; ensure they exist first.
    if preset_name == "sky_gradient" then _ensure_sky_shaders() end
    local content = _render_material(spec)
    editor.create_resources({ { path, content } })
    return { ok = true, path = path, preset = preset_name }

  elseif op == "set_constant" then
    -- Edit a single constant in an existing .material.
    -- params: path, name, value ({x,y,z,w}), kind ("fragment"|"vertex", default "fragment").
    local path = util.norm_resource_path(params.path or "")
    local name = params.name or ""
    if path == "" or name == "" then
      return util.error_response("MISSING_PARAM", "set_constant needs path + name")
    end
    local content, err = util.read_file(path)
    if not content then return util.error_response("READ_ERROR", err) end
    local kind = (params.kind == "vertex") and "vertex_constants" or "fragment_constants"
    local s, e = _find_constant_block(content, kind, name)
    if not s then
      -- Append as a new block at the end.
      content = content .. "\n" .. _const_block(kind, {
        name = name, type = params.type or "CONSTANT_TYPE_USER",
        value = params.value or { 0, 0, 0, 1 },
      })
    else
      -- Replace the existing block.
      local replacement = _const_block(kind, {
        name = name, type = params.type or "CONSTANT_TYPE_USER",
        value = params.value or { 0, 0, 0, 1 },
      }):gsub("\n$", "")
      content = content:sub(1, s - 1) .. replacement .. content:sub(e + 1)
    end
    local ok, werr = util.write_file(path, content)
    if not ok then return util.error_response("WRITE_ERROR", werr) end
    return { ok = true, path = path, name = name, kind = kind, value = params.value }

  elseif op == "get" then
    local path = util.norm_resource_path(params.path or "")
    if path == "" then return util.error_response("MISSING_PARAM", "get needs path") end
    local content, err = util.read_file(path)
    if not content then return util.error_response("READ_ERROR", err) end
    local function find_blocks(kind)
      local out, i = {}, 1
      while true do
        local s = content:find(kind .. "%s*{", i)
        if not s then break end
        local depth, j = 0, s
        while j <= #content do
          local ch = content:sub(j, j)
          if ch == "{" then depth = depth + 1
          elseif ch == "}" then depth = depth - 1; if depth == 0 then break end end
          j = j + 1
        end
        local block = content:sub(s, j)
        local name = block:match('name:%s*"([^"]+)"')
        local x = tonumber(block:match("x:%s*(%-?%d*%.?%d+)"))
        local y = tonumber(block:match("y:%s*(%-?%d*%.?%d+)"))
        local z = tonumber(block:match("z:%s*(%-?%d*%.?%d+)"))
        local w = tonumber(block:match("w:%s*(%-?%d*%.?%d+)"))
        if name then
          table.insert(out, { name = name, value = { x = x, y = y, z = z, w = w } })
        end
        i = j + 1
      end
      return out
    end
    local tags = {}
    for t in content:gmatch('tags:%s*"([^"]+)"') do table.insert(tags, t) end
    local samplers = {}
    for n in content:gmatch('samplers%s*{%s*name:%s*"([^"]+)"') do
      table.insert(samplers, n)
    end
    return {
      ok = true, path = path,
      name = content:match('name:%s*"([^"]+)"'),
      tags = tags,
      vertex_program = content:match('vertex_program:%s*"([^"]+)"'),
      fragment_program = content:match('fragment_program:%s*"([^"]+)"'),
      vertex_space = content:match("vertex_space:%s*([%w_]+)"),
      vertex_constants = find_blocks("vertex_constants"),
      fragment_constants = find_blocks("fragment_constants"),
      samplers = samplers,
    }
  end
  return util.error_response("UNKNOWN_OP", "Unknown material_manage op: " .. op)
end

-- ============ Particle FX ============

-- Curated presets, ported in spirit from godot-ai. Defold particle.fx is a
-- billboard-sprite system (not GPUParticles3D-style mesh) so the presets
-- target an EMITTER_TYPE_BOX (or SPHERE) with a `tile_source` pointing at a
-- 1x1 white texture; tint is applied via PARTICLE_KEY_RED/GREEN/BLUE/ALPHA
-- keyframe curves.
--
-- The white tile source is shared (`/assets/particles/white.tilesource`) and
-- created on-demand by `_ensure_white_tilesource` so callers don't have to
-- pre-prepare assets.
local PRESETS = {
  rain = {
    duration = 1.0, mode = "PLAY_MODE_LOOP", space = "EMISSION_SPACE_WORLD",
    type = "EMITTER_TYPE_BOX",
    box_extents = { x = 10, y = 0.1, z = 10 },
    spawn_rate = 400, particle_life = 1.0,
    initial_speed = 18, gravity = -2.0,
    scale_xy = { 0.04, 0.4 },  -- {width, height} streak
    color = { r = 0.7, g = 0.85, b = 1.0, a = 0.7 },
    blend = "BLEND_MODE_ALPHA",
  },
  snow = {
    duration = 1.0, mode = "PLAY_MODE_LOOP", space = "EMISSION_SPACE_WORLD",
    type = "EMITTER_TYPE_BOX",
    box_extents = { x = 10, y = 0.1, z = 10 },
    spawn_rate = 90, particle_life = 5.0,
    initial_speed = 1.2, gravity = -0.6,
    scale_xy = { 0.12, 0.12 },
    color = { r = 1.0, g = 1.0, b = 1.0, a = 0.9 },
    blend = "BLEND_MODE_ALPHA",
  },
  smoke = {
    duration = 1.0, mode = "PLAY_MODE_LOOP", space = "EMISSION_SPACE_WORLD",
    type = "EMITTER_TYPE_SPHERE",
    sphere_radius = 0.4,
    spawn_rate = 40, particle_life = 3.0,
    initial_speed = 1.0, gravity = 0.5,
    scale_xy = { 0.7, 0.7 },
    color = { r = 0.3, g = 0.3, b = 0.3, a = 0.6 },
    blend = "BLEND_MODE_ALPHA",
  },
  sparkle = {
    duration = 0.5, mode = "PLAY_MODE_LOOP", space = "EMISSION_SPACE_WORLD",
    type = "EMITTER_TYPE_SPHERE",
    sphere_radius = 0.2,
    spawn_rate = 60, particle_life = 0.8,
    initial_speed = 3.0, gravity = -8.0,
    scale_xy = { 0.08, 0.08 },
    color = { r = 1.0, g = 0.95, b = 0.4, a = 1.0 },
    blend = "BLEND_MODE_ADD",
  },
  explosion = {
    duration = 0.15, mode = "PLAY_MODE_ONCE", space = "EMISSION_SPACE_WORLD",
    type = "EMITTER_TYPE_SPHERE",
    sphere_radius = 0.3,
    spawn_rate = 800, particle_life = 0.6,
    initial_speed = 12, gravity = 0,
    scale_xy = { 0.2, 0.2 },
    color = { r = 1.0, g = 0.5, b = 0.1, a = 1.0 },
    blend = "BLEND_MODE_ADD",
  },
}

local function _white_tilesource_path() return "/assets/particles/white.tilesource" end

-- Locate an existing white image in the project. Callers can override with
-- preset.image or DEFOLD_AI_WHITE_IMAGE; otherwise we look for the conventional
-- /assets/images/white.png. Returns nil if nothing usable was found.
local function _find_white_image()
  local override = os.getenv("DEFOLD_AI_WHITE_IMAGE")
  if override and override ~= "" then return override end
  for _, candidate in ipairs({
    "/assets/images/white.png",
    "/assets/particles/white.png",
    "/assets/white.png",
  }) do
    if editor.resource_attributes(candidate).exists then return candidate end
  end
  return nil
end

-- Create the small shared tilesource that wraps the white texture; emitters
-- bind to its single "white" animation. Returns the image path used.
local function _ensure_white_tilesource()
  local img = _find_white_image()
  if not img then
    error("particle presets need a white.png — create one at /assets/images/white.png " ..
          "or set DEFOLD_AI_WHITE_IMAGE")
  end
  local existing = editor.resource_attributes(_white_tilesource_path())
  if existing.exists then return img end
  local ts_content =
    'image: "' .. img .. '"\n' ..
    'tile_width: 1\ntile_height: 1\n' ..
    'tile_margin: 0\ntile_spacing: 0\n' ..
    'collision: ""\nmaterial_tag: "tile"\ncollision_groups: "default"\n' ..
    'animations {\n  id: "white"\n  start_tile: 1\n  end_tile: 1\n' ..
    '  playback: PLAYBACK_NONE\n  fps: 30\n' ..
    '  flip_horizontal: 0\n  flip_vertical: 0\n}\n' ..
    'extrude_borders: 0\ninner_padding: 0\n' ..
    'sprite_trim_mode: SPRITE_TRIM_MODE_OFF\n'
  editor.create_resources({ { _white_tilesource_path(), ts_content } })
  return img
end

-- Build the proto-text body for a particlefx emitter from a preset table.
local function _render_emitter(preset)
  local lines = {
    'emitters {',
    '  id: "emitter"',
    '  mode: ' .. preset.mode,
    '  duration: ' .. preset.duration,
    '  space: ' .. preset.space,
    '  position { x: 0 y: 0 z: 0 }',
    -- Rotate 180° around X so emission direction points -Y (down) for rain/snow.
    '  rotation { x: 1 y: 0 z: 0 w: 0 }',
    '  tile_source: "' .. _white_tilesource_path() .. '"',
    '  animation: "white"',
    '  material: "/builtins/materials/particlefx.material"',
    '  blend_mode: ' .. preset.blend,
    '  particle_orientation: PARTICLE_ORIENTATION_DEFAULT',
    '  inherit_velocity: 0.0',
    '  max_particle_count: 2000',
    '  type: ' .. preset.type,
    '  start_delay: 0.0',
    '  size_mode: SIZE_MODE_MANUAL',
  }
  if preset.type == "EMITTER_TYPE_BOX" then
    table.insert(lines, '  properties { key: EMITTER_KEY_SIZE_X points { x: 0 y: ' .. preset.box_extents.x .. ' t_x: 1 t_y: 0 } spread: 0 }')
    table.insert(lines, '  properties { key: EMITTER_KEY_SIZE_Y points { x: 0 y: ' .. preset.box_extents.y .. ' t_x: 1 t_y: 0 } spread: 0 }')
    table.insert(lines, '  properties { key: EMITTER_KEY_SIZE_Z points { x: 0 y: ' .. preset.box_extents.z .. ' t_x: 1 t_y: 0 } spread: 0 }')
  elseif preset.type == "EMITTER_TYPE_SPHERE" then
    table.insert(lines, '  properties { key: EMITTER_KEY_SIZE_X points { x: 0 y: ' .. preset.sphere_radius .. ' t_x: 1 t_y: 0 } spread: 0 }')
  end
  -- Spawn rate (emitter property)
  table.insert(lines, '  properties { key: EMITTER_KEY_SPAWN_RATE points { x: 0 y: ' .. preset.spawn_rate .. ' t_x: 1 t_y: 0 } spread: 0 }')
  -- Particle life span
  table.insert(lines, '  properties { key: EMITTER_KEY_PARTICLE_LIFE_TIME points { x: 0 y: ' .. preset.particle_life .. ' t_x: 1 t_y: 0 } spread: 0 }')
  -- Initial particle speed (downward via emitter rotation; preset.gravity_dir
  -- selects the orientation in _render_emitter)
  table.insert(lines, '  properties { key: EMITTER_KEY_PARTICLE_SPEED points { x: 0 y: ' .. preset.initial_speed .. ' t_x: 1 t_y: 0 } spread: 0 }')
  -- Initial particle size (curve at constant 1 — PARTICLE_KEY_SCALE multiplies)
  table.insert(lines, '  properties { key: EMITTER_KEY_PARTICLE_SIZE points { x: 0 y: 1 t_x: 1 t_y: 0 } spread: 0 }')
  -- Per-particle curves (no `spread` on particle_properties — only on properties).
  table.insert(lines, '  particle_properties { key: PARTICLE_KEY_SCALE points { x: 0 y: ' .. preset.scale_xy[1] .. ' t_x: 1 t_y: 0 } }')
  local c = preset.color
  table.insert(lines, '  particle_properties { key: PARTICLE_KEY_RED   points { x: 0 y: ' .. c.r .. ' t_x: 1 t_y: 0 } }')
  table.insert(lines, '  particle_properties { key: PARTICLE_KEY_GREEN points { x: 0 y: ' .. c.g .. ' t_x: 1 t_y: 0 } }')
  table.insert(lines, '  particle_properties { key: PARTICLE_KEY_BLUE  points { x: 0 y: ' .. c.b .. ' t_x: 1 t_y: 0 } }')
  table.insert(lines, '  particle_properties { key: PARTICLE_KEY_ALPHA points { x: 0 y: ' .. c.a .. ' t_x: 1 t_y: 0 } }')
  table.insert(lines, '}')
  return table.concat(lines, '\n') .. '\n'
end

function M.particlefx_manage(body)
  local op = body.op or ""
  local params = body.params or {}
  if op == "create" then
    local path = util.norm_resource_path(params.path or "")
    if path == "" then
      return util.error_response("MISSING_PARAM", "create needs path")
    end
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
    local path = util.norm_resource_path(params.path or "")
    local preset_name = params.preset or ""
    if path == "" or preset_name == "" then
      return util.error_response("MISSING_PARAM", "apply_preset needs path + preset")
    end
    local preset = PRESETS[preset_name]
    if not preset then
      local available = {}
      for k, _ in pairs(PRESETS) do table.insert(available, k) end
      return util.error_response("UNKNOWN_PRESET",
        "Unknown preset: " .. preset_name .. ". Available: " .. table.concat(available, ", "))
    end
    -- Merge overrides
    if type(params.overrides) == "table" then
      for k, v in pairs(params.overrides) do preset[k] = v end
    end
    _ensure_white_tilesource()
    local content = _render_emitter(preset)
    editor.create_resources({ { path, content } })
    return { ok = true, path = path, preset = preset_name }
  elseif op == "list_presets" then
    local out = {}
    for k, _ in pairs(PRESETS) do table.insert(out, k) end
    table.sort(out)
    return { ok = true, presets = out }
  end
  return util.error_response("UNKNOWN_OP", "Unknown particlefx_manage op: " .. op)
end

-- ============ Atlas helpers ============
-- An .atlas file is Defold protobuf-text. Per-image entries look like:
--   images {
--     image: "/path/to/x.png"
--     sprite_trim_mode: SPRITE_TRIM_MODE_OFF
--   }

local function _parse_image_blocks(content)
  local out = {}
  local i = 1
  while true do
    local s, e = content:find("images%s*{", i)
    if not s then break end
    local close = content:find("}", e + 1, true)
    if not close then break end
    local body = content:sub(s, close)
    local img = body:match('image:%s*"([^"]+)"')
    table.insert(out, { image = img, body = body, range = { s, close } })
    i = close + 1
  end
  return out
end

local function _has_image(content, image_path)
  for _, blk in ipairs(_parse_image_blocks(content)) do
    if blk.image == image_path then return true end
  end
  return false
end

-- ============ Atlas ============
function M.atlas_manage(body)
  local op = body.op or ""
  local params = body.params or {}
  local path = util.norm_resource_path(params.path or "")

  if op == "create" then
    if path == "" then return util.error_response("MISSING_PARAM", "create needs path") end
    local margin = params.margin or 0
    local extrude = params.extrude_borders or 2
    local inner = params.inner_padding or 0
    local content = string.format(
      "margin: %d\nextrude_borders: %d\ninner_padding: %d\n", margin, extrude, inner
    )
    local images = params.images or {}
    for _, img in ipairs(images) do
      content = content .. string.format(
        'images {\n  image: "%s"\n  sprite_trim_mode: SPRITE_TRIM_MODE_OFF\n}\n',
        util.norm_resource_path(img)
      )
    end
    editor.create_resources({ { path, content } })
    return { ok = true, path = path, image_count = #images }

  elseif op == "add_image" then
    if path == "" then return util.error_response("MISSING_PARAM", "add_image needs path") end
    local image = util.norm_resource_path(params.image or "")
    if image == "" then return util.error_response("MISSING_PARAM", "add_image needs image") end
    local content, err = util.read_file(path)
    if not content then return util.error_response("READ_ERROR", err) end
    if _has_image(content, image) then
      return { ok = true, path = path, image = image, note = "already present (no-op)" }
    end
    if content:sub(-1) ~= "\n" then content = content .. "\n" end
    local trim = params.sprite_trim_mode or "SPRITE_TRIM_MODE_OFF"
    content = content .. string.format(
      'images {\n  image: "%s"\n  sprite_trim_mode: %s\n}\n', image, trim
    )
    local wok, werr = util.write_file(path, content)
    if not wok then return util.error_response("WRITE_ERROR", werr) end
    return { ok = true, path = path, image = image }

  elseif op == "remove_image" then
    if path == "" then return util.error_response("MISSING_PARAM", "remove_image needs path") end
    local image = util.norm_resource_path(params.image or "")
    if image == "" then return util.error_response("MISSING_PARAM", "remove_image needs image") end
    local content, err = util.read_file(path)
    if not content then return util.error_response("READ_ERROR", err) end
    local target
    for _, blk in ipairs(_parse_image_blocks(content)) do
      if blk.image == image then target = blk; break end
    end
    if not target then return util.error_response("NOT_FOUND", "image not in atlas: " .. image) end
    local s, e = target.range[1], target.range[2]
    local nl_after = content:sub(e + 1, e + 1) == "\n" and 1 or 0
    content = content:sub(1, s - 1) .. content:sub(e + 1 + nl_after)
    local wok, werr = util.write_file(path, content)
    if not wok then return util.error_response("WRITE_ERROR", werr) end
    return { ok = true, path = path, removed = image }

  elseif op == "list_images" then
    if path == "" then return util.error_response("MISSING_PARAM", "list_images needs path") end
    local content, err = util.read_file(path)
    if not content then return util.error_response("READ_ERROR", err) end
    local out = {}
    for _, blk in ipairs(_parse_image_blocks(content)) do
      table.insert(out, blk.image)
    end
    return { ok = true, path = path, images = out, count = #out }

  elseif op == "add_animation" then
    if path == "" then return util.error_response("MISSING_PARAM", "add_animation needs path") end
    local id = params.id or ""
    local images = params.images or {}
    if id == "" or #images == 0 then
      return util.error_response("MISSING_PARAM", "add_animation needs id + non-empty images")
    end
    local content, err = util.read_file(path)
    if not content then return util.error_response("READ_ERROR", err) end
    if content:sub(-1) ~= "\n" then content = content .. "\n" end
    local fps = params.fps or 30
    local playback = params.playback or "PLAYBACK_LOOP_FORWARD"
    local block = { 'animations {', '  id: "' .. id .. '"' }
    for _, img in ipairs(images) do
      table.insert(block, '  images {')
      table.insert(block, '    image: "' .. util.norm_resource_path(img) .. '"')
      table.insert(block, '    sprite_trim_mode: SPRITE_TRIM_MODE_OFF')
      table.insert(block, '  }')
    end
    table.insert(block, '  playback: ' .. playback)
    table.insert(block, '  fps: ' .. tostring(fps))
    table.insert(block, '  flip_horizontal: 0')
    table.insert(block, '  flip_vertical: 0')
    table.insert(block, '}\n')
    content = content .. table.concat(block, "\n")
    local wok, werr = util.write_file(path, content)
    if not wok then return util.error_response("WRITE_ERROR", werr) end
    return { ok = true, path = path, id = id, image_count = #images }

  elseif op == "set_margin" then
    if path == "" then return util.error_response("MISSING_PARAM", "set_margin needs path") end
    local content, err = util.read_file(path)
    if not content then return util.error_response("READ_ERROR", err) end
    local m = params.margin or 0
    if content:find("margin:") then
      content = content:gsub("margin:%s*%-?%d+", "margin: " .. m)
    else
      content = "margin: " .. m .. "\n" .. content
    end
    local wok, werr = util.write_file(path, content)
    if not wok then return util.error_response("WRITE_ERROR", werr) end
    return { ok = true, path = path, margin = m }

  elseif op == "get" then
    if path == "" then return util.error_response("MISSING_PARAM", "get needs path") end
    local content, err = util.read_file(path)
    if not content then return util.error_response("READ_ERROR", err) end
    local images = {}
    for _, blk in ipairs(_parse_image_blocks(content)) do
      table.insert(images, blk.image)
    end
    return {
      ok = true, path = path,
      margin = tonumber((content:match("margin:%s*(%-?%d+)"))) or 0,
      extrude_borders = tonumber((content:match("extrude_borders:%s*(%-?%d+)"))) or 0,
      inner_padding = tonumber((content:match("inner_padding:%s*(%-?%d+)"))) or 0,
      images = images,
    }
  end
  return util.error_response("UNKNOWN_OP", "Unknown atlas_manage op: " .. op)
end

-- ============ Tilesource ============
function M.tilesource_manage(body)
  local op = body.op or ""
  local params = body.params or {}
  local path = util.norm_resource_path(params.path or "")

  if op == "create" then
    if path == "" then return util.error_response("MISSING_PARAM", "create needs path") end
    local image = util.norm_resource_path(params.image or "")
    if image == "" then return util.error_response("MISSING_PARAM", "create needs image (the tilesheet PNG)") end
    local tw = params.tile_width or 32
    local th = params.tile_height or 32
    local margin = params.tile_margin or 0
    local spacing = params.tile_spacing or 0
    local extrude = params.extrude_borders or 2
    local material_tag = params.material_tag or "tile"
    local lines = {
      'image: "' .. image .. '"',
      'tile_width: ' .. tw,
      'tile_height: ' .. th,
      'tile_margin: ' .. margin,
      'tile_spacing: ' .. spacing,
      'collision: "' .. image .. '"',
      'material_tag: "' .. material_tag .. '"',
      'collision_groups: "default"',
    }
    local anims = params.animations or {}
    for _, a in ipairs(anims) do
      table.insert(lines, 'animations {')
      table.insert(lines, '  id: "' .. (a.id or "tile") .. '"')
      table.insert(lines, '  start_tile: ' .. (a.start_tile or 1))
      table.insert(lines, '  end_tile: ' .. (a.end_tile or a.start_tile or 1))
      table.insert(lines, '  playback: ' .. (a.playback or "PLAYBACK_NONE"))
      table.insert(lines, '  fps: ' .. (a.fps or 30))
      table.insert(lines, '  flip_horizontal: 0')
      table.insert(lines, '  flip_vertical: 0')
      table.insert(lines, '}')
    end
    table.insert(lines, 'extrude_borders: ' .. extrude)
    table.insert(lines, 'inner_padding: 0')
    table.insert(lines, 'sprite_trim_mode: SPRITE_TRIM_MODE_OFF')
    local content = table.concat(lines, '\n') .. '\n'
    editor.create_resources({ { path, content } })
    return { ok = true, path = path, tile_width = tw, tile_height = th, animations = #anims }
  end
  return util.error_response("UNKNOWN_OP", "Unknown tilesource_manage op: " .. op)
end

-- ============ Tilemap ============
function M.tilemap_manage(body)
  local op = body.op or ""
  local params = body.params or {}
  local path = util.norm_resource_path(params.path or "")

  if op == "create" then
    if path == "" then return util.error_response("MISSING_PARAM", "create needs path") end
    local tile_set = util.norm_resource_path(params.tile_set or "")
    if tile_set == "" then return util.error_response("MISSING_PARAM", "create needs tile_set (.tilesource path)") end
    local layer_id = params.layer_id or "ground"
    local material = params.material or "/builtins/materials/tile_map.material"
    local cells = params.cells or {}
    local lines = {
      'tile_set: "' .. tile_set .. '"',
      'layers {',
      '  id: "' .. layer_id .. '"',
      '  z: 0.0',
      '  is_visible: 1',
    }
    for _, c in ipairs(cells) do
      table.insert(lines, '  cell {')
      table.insert(lines, '    x: ' .. (c.x or c[1] or 0))
      table.insert(lines, '    y: ' .. (c.y or c[2] or 0))
      table.insert(lines, '    tile: ' .. (c.tile or c[3] or 0))
      table.insert(lines, '    h_flip: ' .. (c.h_flip or 0))
      table.insert(lines, '    v_flip: ' .. (c.v_flip or 0))
      table.insert(lines, '    rotate90: ' .. (c.rotate90 or 0))
      table.insert(lines, '  }')
    end
    table.insert(lines, '}')
    table.insert(lines, 'material: "' .. material .. '"')
    table.insert(lines, 'blend_mode: BLEND_MODE_ALPHA')
    local content = table.concat(lines, '\n') .. '\n'
    editor.create_resources({ { path, content } })
    return { ok = true, path = path, cells_baked = #cells }
  end
  return util.error_response("UNKNOWN_OP", "Unknown tilemap_manage op: " .. op)
end

return M
