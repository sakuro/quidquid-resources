local api = require("__quidquid__.lib.api")

local ViewActions = {}

-- A patch has its own coordinates, so the jump goes there rather than to a remembered
-- position; Quidquid keeps those for surfaces.
local function resolve_remote_view(candidate, _player)
  local surface = game.get_surface(candidate.surface_index)
  if surface == nil then
    return nil, "quidquid-resources.action-open-remote-view-unavailable"
  end
  return { surface = surface, position = candidate.position }, nil
end

local function open_remote_view(candidate, player_index)
  return api.run_action(candidate, player_index, resolve_remote_view, function(target, _candidate, player)
    player.set_controller({ type = defines.controllers.remote, surface = target.surface, position = target.position })
  end)
end

local function resolve_prototype(candidate, _player)
  local prototype = prototypes.entity[candidate.resource_name]
  if prototype == nil then
    return nil, "quidquid-resources.action-open-factoriopedia-unavailable"
  end
  return prototype, nil
end

local function open_factoriopedia(candidate, player_index)
  return api.run_action(candidate, player_index, resolve_prototype, function(prototype, _candidate, player)
    player.open_factoriopedia_gui(prototype)
  end)
end

--- Adds the remote-view and Factoriopedia interfaces that prototypes/actions.lua names.
function ViewActions.add_interface()
  remote.add_interface("quidquid-resources.remote-view", { execute = open_remote_view })
  remote.add_interface("quidquid-resources.factoriopedia", { execute = open_factoriopedia })
end

return ViewActions
