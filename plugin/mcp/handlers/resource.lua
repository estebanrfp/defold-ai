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
    local ok, err = os.remove(relative)
    if not ok then return util.error_response("DELETE_ERROR", tostring(err)) end
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
    return util.error_response("NOT_IMPLEMENTED",
      "Preset library coming later (rain, snow, smoke, sparkle, explosion).")
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
