-- Component handlers — add Defold components (script, sprite, model, ...) to GOs.

local util = require "mcp.lib.util"

local M = {}

local VALID_TYPES = {
  ["script"] = true, ["gui"] = true, ["sprite"] = true,
  ["model"] = true, ["mesh"] = true, ["label"] = true,
  ["sound"] = true, ["particlefx"] = true,
  ["factory"] = true, ["collectionfactory"] = true,
  ["collisionobject"] = true, ["tilemap"] = true,
  ["camera"] = true, ["buffer"] = true, ["spinemodel"] = true,
}

function M.add(body)
  local gameobject = body.gameobject or ""
  if gameobject == "" then
    return util.error_response("MISSING_PARAM", "params.gameobject is required")
  end
  local type_str = body.type or ""
  if not VALID_TYPES[type_str] then
    return util.error_response("INVALID_TYPE",
      "Unknown component type: " .. type_str ..
      ". Use component_list_types for the full list.")
  end
  local id = body.id or ""
  if id == "" then id = type_str .. "_" .. tostring(math.random(1000, 9999)) end

  -- If the user provided a resource path, treat it as a component-reference;
  -- otherwise create an embedded component.
  local resource = body.resource or ""
  local component_spec
  if resource ~= "" then
    component_spec = {
      type = "component-reference",
      id = id,
      path = util.norm_resource_path(resource),
    }
  else
    component_spec = {
      type = type_str,
      id = id,
    }
  end
  -- Merge in additional properties (depending on component type).
  local props = body.properties or {}
  for k, v in pairs(props) do
    component_spec[k] = v
  end

  if not editor.can_add(gameobject, "components") then
    return util.error_response("NOT_ALLOWED",
      "Cannot add components to " .. gameobject ..
      ". Is it a game object (not a collection)?")
  end

  editor.transact({ editor.tx.add(gameobject, "components", component_spec) })
  editor.save()
  return { ok = true, gameobject = gameobject, component_id = id, type = type_str }
end

function M.remove(body)
  local gameobject = body.gameobject or ""
  local component_id = body.component_id or ""
  if gameobject == "" or component_id == "" then
    return util.error_response("MISSING_PARAM", "remove needs gameobject + component_id")
  end
  local comps = editor.get(gameobject, "components") or {}
  for i, c in ipairs(comps) do
    if tostring(util.try_get(c, "id")) == component_id then
      editor.transact({ editor.tx.remove(gameobject, "components", i - 1) })
      editor.save()
      return { ok = true, removed = component_id }
    end
  end
  return util.error_response("NOT_FOUND", "Component id not found: " .. component_id)
end

return M
