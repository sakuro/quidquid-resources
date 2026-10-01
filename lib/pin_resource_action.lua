local api = require("__quidquid__.lib.api")

local PinResourceAction = {}

local PREVIEW_DISTANCE = 64

local function resolve(candidate, _player)
  local surface = game.get_surface(candidate.surface_index)
  if surface == nil then
    return nil, "quidquid-resources.action-pin-resource-unavailable"
  end
  return surface, nil
end

-- is_available only gates by candidate type (via this action's registered `types`);
-- whether the patch's surface still exists is a per-candidate runtime fact, so it's
-- resolved here and reported by execute, not hidden from the tooltip.
--
-- resource = selected_candidate.resource_name passes a prototype name string, one of
-- the three forms runtime-api.json's EntityID union accepts for LuaPlayer.add_pin's
-- resource parameter; its description ("The resource prototype to add an entire
-- resource patch with") confirms this pins the whole patch rather than one entity.
--
-- No label is passed, deliberately. Given surface, position and resource, the engine
-- resolves the whole patch and holds a reference to every entity in it. Confirmed in
-- game: a pin made here and one made by Factorio's own map-search pin button come back
-- with the same targets and the same centre. It renders the name and the remaining
-- amount from those entities, so the figure follows the patch as it is mined. Any label
-- we passed would be a frozen copy of that figure sitting beside the live one.
local function execute(candidate, player_index)
  return api.run_action(candidate, player_index, resolve, function(surface, selected_candidate, player)
    player.add_pin({
      surface = surface,
      position = selected_candidate.position,
      resource = selected_candidate.resource_name,
      preview_distance = PREVIEW_DISTANCE,
    })
  end, "quidquid-resources.action-pin-resource-unavailable")
end

--- Adds this action's remote interface, named by its declaration in prototypes/actions.lua.
function PinResourceAction.add_interface()
  remote.add_interface("quidquid-resources.pin", { execute = execute })
end

return PinResourceAction
