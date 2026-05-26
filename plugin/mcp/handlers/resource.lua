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
    local content = string.format(
      "name: \"%s\"\nvertex_program: \"%s\"\nfragment_program: \"%s\"\n",
      path:match("([^/]+)%.material$") or "material", vp, fp
    )
    editor.create_resources({ { path, content } })
    return { ok = true, path = path }
  elseif op == "set_constant" or op == "get" then
    return util.error_response("NOT_IMPLEMENTED",
      op .. " requires structured .material edit; planned for v0.3. " ..
      "Workaround: use resource_manage(op='read'/'write') to edit the .material text directly.")
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
