local flib_dictionary = require("__flib__.dictionary")
local ResourceSource = require("lib.resource_source")
local PinResourceAction = require("lib.pin_resource_action")
local ViewActions = require("lib.view_actions")

ResourceSource.add_interface()
PinResourceAction.add_interface()
ViewActions.add_interface()

-- flib_dictionary.new/.add may only run before flib's first on_tick, so the dictionary
-- is registered from on_init and on_configuration_changed, which both reset flib's
-- dictionary state first.
script.on_init(function()
  flib_dictionary.on_init()
  ResourceSource.register_dictionary()
  ResourceSource.ensure_storage()
end)
script.on_configuration_changed(function()
  flib_dictionary.on_configuration_changed()
  ResourceSource.register_dictionary()
  ResourceSource.ensure_storage()
end)

script.on_event(defines.events.on_tick, function()
  flib_dictionary.on_tick()
  ResourceSource.on_tick()
end)
script.on_event(defines.events.on_string_translated, flib_dictionary.on_string_translated)
script.on_event(defines.events.on_player_joined_game, flib_dictionary.on_player_joined_game)
script.on_event(defines.events.on_player_locale_changed, flib_dictionary.on_player_locale_changed)

-- The resource cluster cache is derived from the world, so every event that changes
-- which resources exist, or which chunks hold them, has to reach it. There is no event
-- for un-charting: LuaForce.clear_chart raises nothing, so visibility is filtered per
-- force at search time rather than tracked here.
script.on_event(defines.events.on_chunk_charted, ResourceSource.on_chunk_charted)
script.on_event(defines.events.on_chunk_deleted, ResourceSource.on_chunk_deleted)
script.on_event(defines.events.on_surface_cleared, ResourceSource.on_surface_removed)
script.on_event(defines.events.on_surface_deleted, ResourceSource.on_surface_removed)
script.on_event(defines.events.on_resource_depleted, ResourceSource.on_resource_depleted)

-- LuaBootstrap.on_event's filters parameter only applies "when registering for
-- individual events" (confirmed against runtime-api.json and empirically: passing it
-- alongside an array of events raises "Filters can only be used when registering single
-- non custom-input events"), so the same filter is repeated across four registrations
-- rather than one call with an event array. Addition and removal share a handler because
-- both boil down to the same correction: re-enqueue the chunk and let the background
-- scan recompute it from what is actually there now.
local RESOURCE_ENTITY_FILTER = { { filter = "type", type = "resource" } }
script.on_event(defines.events.on_built_entity, ResourceSource.on_resource_entity_changed, RESOURCE_ENTITY_FILTER)
script.on_event(defines.events.on_robot_built_entity, ResourceSource.on_resource_entity_changed, RESOURCE_ENTITY_FILTER)
script.on_event(defines.events.script_raised_built, ResourceSource.on_resource_entity_changed, RESOURCE_ENTITY_FILTER)
script.on_event(defines.events.script_raised_destroy, ResourceSource.on_resource_entity_changed, RESOURCE_ENTITY_FILTER)
