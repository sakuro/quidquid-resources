local flib_dictionary = require("__flib__.dictionary")
local ResourceClustering = require("lib.resource_clustering")
local ResourceLogic = require("lib.resource_logic")
local ScanQueue = require("lib.scan_queue")

local ResourceSource = {}

local SCHEMA_VERSION = 4
local SCAN_CHUNKS_PER_TICK = 8

-- Every handler starts from here and returns early on nil. ensure_storage runs from
-- on_init and on_configuration_changed, which together cover the mod being added, so
-- nil should be unreachable -- but an event firing against a half-initialised storage
-- would otherwise be a nil index deep inside the clustering code.
local function state()
  return storage.resources
end

local function store_for(surface_index)
  local resources = state()
  local store = resources.surfaces[surface_index]
  if store == nil then
    store = ResourceClustering.new_store()
    resources.surfaces[surface_index] = store
  end
  return store
end

local function enqueue(surface_index, x, y)
  ScanQueue.enqueue(state().queue, surface_index, x, y)
end

local function enqueue_everything()
  for _, surface in pairs(game.surfaces) do
    for chunk in surface.get_chunks() do
      enqueue(surface.index, chunk.x, chunk.y)
    end
  end
end

-- Prototypes are fixed for a session, so each resource's answer is computed once. A
-- plain upvalue rather than storage: it is derived from prototypes alone, so every
-- peer computes the same value and a save/load only costs recomputing it.
local loose_by_name = {}

local function is_loose(resource_name)
  local loose = loose_by_name[resource_name]
  if loose == nil then
    loose = ResourceClustering.is_loose(prototypes.entity[resource_name].collision_box)
    loose_by_name[resource_name] = loose
  end
  return loose
end

local function scan(surface_index, x, y)
  local surface = game.get_surface(surface_index)
  if surface == nil then
    return
  end
  local entities = surface.find_entities_filtered({
    area = { left_top = { x * 32, y * 32 }, right_bottom = { (x + 1) * 32, (y + 1) * 32 } },
    type = "resource",
  })

  -- find_entities_filtered's area is a closed box, so an entity sitting exactly on a
  -- shared edge can come back for this chunk and its neighbour both. Keep only the
  -- entities this chunk actually owns, using the same floor-division on_resource_depleted
  -- and on_built_entity derive a chunk key from, so all three agree by construction.
  local owned = {}
  for _, entity in ipairs(entities) do
    local position = entity.position
    if math.floor(position.x / 32) == x and math.floor(position.y / 32) == y then
      table.insert(owned, entity)
    end
  end

  local grouped = ResourceClustering.group_chunk(owned)
  local existing_store = state().surfaces[surface_index]
  if next(grouped) == nil and existing_store == nil then
    return
  end

  local key = ResourceClustering.chunk_key(x, y)
  local store = store_for(surface_index)
  -- A resource this chunk held before but the rescan no longer finds (depleted to
  -- nothing, or removed) must be dropped, not just left stale -- see on_resource_depleted.
  for resource_name in pairs(store.owner) do
    if grouped[resource_name] == nil then
      ResourceClustering.remove_chunk(store, resource_name, key)
    end
  end
  for resource_name, entry in pairs(grouped) do
    ResourceClustering.insert(store, surface_index, resource_name, key, entry, is_loose(resource_name))
  end
end

--- Creates the cluster cache, or throws it away when its shape has changed.
---
--- A schema bump is the whole migration: the cache is discarded and every charted
--- chunk re-enqueued for the background scan, so no per-version migration code is
--- needed. Run from on_init and on_configuration_changed.
function ResourceSource.ensure_storage()
  local resources = storage.resources
  if resources ~= nil and resources.version == SCHEMA_VERSION then
    return
  end
  storage.resources = { version = SCHEMA_VERSION, surfaces = {}, queue = ScanQueue.new(), initial_scan_pending = true }
  enqueue_everything()
end

--- Scans a bounded slice of the pending chunk queue.
---
--- Bounded rather than exhaustive because the queue holds every charted chunk of every
--- surface when the mod is added to an existing save; scanning that in one tick would
--- freeze the load, with no progress to show and no way to resume. Registered from
--- control.lua's on_tick.
function ResourceSource.on_tick()
  local resources = state()
  if resources == nil then
    return
  end
  local scanned = 0
  while scanned < SCAN_CHUNKS_PER_TICK do
    local chunk = ScanQueue.dequeue(resources.queue)
    if chunk == nil then
      break
    end
    scan(chunk.surface_index, chunk.x, chunk.y)
    scanned = scanned + 1
  end
  if ScanQueue.is_empty(resources.queue) then
    -- Announced once, when the batch ensure_storage queued is through. The queue drains
    -- again and again in ordinary play -- every newly charted chunk and every exhausted
    -- entity refills it -- so the flag, not an empty queue, is what marks the end of the
    -- initial scan. This runs even when the queue was already empty going in, because a
    -- brand new game can have nothing to scan at all, and staying silent there would be
    -- the one case where adding the mod says nothing.
    if resources.initial_scan_pending then
      resources.initial_scan_pending = nil
      game.print({ "", { "mod-name.quidquid-resources" }, ": ", { "quidquid-resources.resource-scan-complete" } })
    end
  end
end

--- Queues a newly charted chunk for scanning.
---@param event table  on_chunk_charted
function ResourceSource.on_chunk_charted(event)
  if state() == nil then
    return
  end
  enqueue(event.surface_index, event.position.x, event.position.y)
end

--- Forgets the clusters' hold on deleted chunks.
---
--- A cluster losing a chunk is not a cluster splitting: it keeps the rest, and goes
--- away only once nothing is left. See issue #174.
---@param event table  on_chunk_deleted
function ResourceSource.on_chunk_deleted(event)
  local resources = state()
  local store = resources and resources.surfaces[event.surface_index] or nil
  if store == nil then
    return
  end
  for _, position in pairs(event.positions) do
    local key = ResourceClustering.chunk_key(position.x, position.y)
    for resource_name in pairs(store.owner) do
      ResourceClustering.remove_chunk(store, resource_name, key)
    end
  end
end

--- Drops a surface's clusters whole.
---
--- Surface indices are reused, so a leftover store would be read as another surface's
--- -- the same hazard a source keying anything by surface_index has to guard against.
--- Registered for both on_surface_deleted and on_surface_cleared.
---@param event table  on_surface_deleted or on_surface_cleared
function ResourceSource.on_surface_removed(event)
  local resources = state()
  if resources ~= nil then
    resources.surfaces[event.surface_index] = nil
  end
end

--- Re-scans the chunk an exhausted resource entity sat in.
---
--- `entity.amount` at this point is what's left, not what disappeared -- zero for a
--- finite resource, the minimum yield for an infinite one -- so subtracting it would
--- leave the cached amount permanently wrong instead of correcting it. Re-enqueuing
--- lets the background scan recompute the chunk's entry from what is actually still
--- there, the same way on_built_entity handles a chunk gaining a resource.
---@param event table  on_resource_depleted
function ResourceSource.on_resource_depleted(event)
  local entity = event.entity
  if state() == nil or not entity.valid then
    return
  end
  enqueue(entity.surface_index, math.floor(entity.position.x / 32), math.floor(entity.position.y / 32))
end

--- Re-scans the chunk a resource entity was added to or removed from by script.
---
--- Mods place or remove resources after a chunk has been charted and scanned; without
--- this the cache would never learn about either change. A destroyed entity raises
--- neither on_resource_depleted (that only fires for exhaustion) nor on_chunk_charted
--- (the chunk was already charted), so script_raised_destroy is the only signal the
--- cache gets -- confirmed against a live server that `event.entity` is still valid,
--- with a readable position and surface_index, at the time this handler runs.
--- Registered with a type filter so the handler is not called for ordinary building or
--- destruction.
---@param event table  on_built_entity, on_robot_built_entity, script_raised_built or
--- script_raised_destroy
function ResourceSource.on_resource_entity_changed(event)
  local entity = event.entity
  if state() == nil or entity == nil or not entity.valid or entity.type ~= "resource" then
    return
  end
  enqueue(entity.surface_index, math.floor(entity.position.x / 32), math.floor(entity.position.y / 32))
end

local NAMESPACE = "resources"
-- flib's dictionary is one flat table of resource-prototype-name -> translated name;
-- prototype names are kebab-case, so this sentinel (double-underscore, never valid
-- kebab-case) cannot collide with one and shares the same table for the occupied
-- marker's own translation.
local OCCUPIED_MARKER_KEY = "__occupied__"

local function collect_resources()
  local resources = {}
  for _, prototype in pairs(prototypes.entity) do
    if prototype.type == "resource" then
      table.insert(resources, prototype)
    end
  end
  return resources
end

-- Built fresh per search rather than cached: prototypes never change within a session,
-- but this is a handful of entries and the cache lookup would cost more than rebuilding.
local function collect_localised_names()
  local localised_names = {}
  for _, prototype in ipairs(collect_resources()) do
    localised_names[prototype.name] = prototype.localised_name
  end
  return localised_names
end

-- The rich-text token for a resource candidate's surface: a planet icon when the
-- surface has one (the same "[planet=...]" tag vanilla's own Space Age locale uses,
-- rendered as rich text by lib/search_highlight.lua like the rest of this line), or
-- the plain surface name otherwise -- LuaSurface.planet is nil for a scripted surface
-- from another mod that has none.
local function surface_token(surface)
  if surface.planet ~= nil then
    return "[planet=" .. surface.planet.name .. "]"
  end
  return surface.name
end

-- Collects both the visible clusters and each of their surfaces' display tokens in
-- one pass, since this loop already has every relevant LuaSurface in hand -- a second
-- pass just to build the token map would walk the same surfaces again for nothing.
local function visible_clusters(player)
  local clusters = {}
  local surface_tokens = {}
  local resources = state()
  if resources == nil then
    return clusters, surface_tokens
  end
  local force = player.force
  for surface_index, store in pairs(resources.surfaces) do
    local surface = game.get_surface(surface_index)
    if surface ~= nil and surface.platform == nil then
      surface_tokens[surface_index] = surface_token(surface)
      for _, cluster in ipairs(ResourceClustering.all(store)) do
        for key in pairs(cluster.chunks) do
          local x, y = key:match("^(-?%d+),(-?%d+)$")
          if force.is_chunk_charted(surface, { x = tonumber(x), y = tonumber(y) }) then
            table.insert(clusters, cluster)
            break
          end
        end
      end
    end
  end
  return clusters, surface_tokens
end

-- One find_entities_filtered per candidate, with limit = 1 so the engine stops at the
-- first hit. Measured on a disposable headless server with 1400 mining drills present:
-- ~45us per call for a patch with no drill on it, the common case -- the engine must
-- scan the whole bbox and find nothing. `search` used to run this over every matching
-- patch, not just the DISPLAY_LIMIT PaletteLogic.merge_candidates keeps, which at a few
-- hundred matching patches roughly doubled a keystroke's cost; unlike items or
-- technologies, typing more of a resource's name does not shrink the match count, since
-- there are only a handful of resource prototypes but potentially hundreds of patches
-- each. `decorate` (below) now calls this only on the candidates about to be shown.
--
-- Every link of the chain -- the surface, this surface's store, this cluster -- is
-- guarded rather than indexed straight through: state() can be nil like every other
-- entry point here, and a surface's store or a specific cluster can legitimately be
-- gone by the time this runs (the background scan and the player both mutate it).
-- Any of those absences means "nothing to report", not a crash worth letting the
-- caller's pcall swallow for every candidate in the search.
local function is_occupied(candidate)
  local surface = game.get_surface(candidate.surface_index)
  if surface == nil then
    return false
  end
  local resources = state()
  if resources == nil then
    return false
  end
  local store = resources.surfaces[candidate.surface_index]
  if store == nil then
    return false
  end
  local cluster = store.clusters[candidate.id]
  if cluster == nil then
    return false
  end
  local drills = surface.find_entities_filtered({
    area = {
      left_top = { cluster.bounds.left, cluster.bounds.top },
      right_bottom = { cluster.bounds.right, cluster.bounds.bottom },
    },
    type = "mining-drill",
    limit = 1,
  })
  return #drills > 0
end

local function search(query, player_index)
  local player = game.get_player(player_index)
  if player == nil then
    return {}
  end
  local translated_names = flib_dictionary.get(player_index, NAMESPACE) or {}
  local clusters, surface_tokens = visible_clusters(player)
  return ResourceLogic.build_candidates(
    query,
    clusters,
    translated_names,
    collect_localised_names(),
    surface_tokens,
    translated_names[OCCUPIED_MARKER_KEY]
  )
end

-- Registered as this source's `decorate`, called by lib/palette.lua only on the
-- candidates that survived PaletteLogic.merge_candidates' trim -- see the comment above
-- is_occupied for why that bound is the point of this hook. Building the occupied form
-- needs only the candidate's own `label` and `occupied_marker`, both plain fields
-- build_candidates already sets on every candidate for exactly this reader, so nothing
-- needs deriving from scratch here. An unoccupied candidate gets no entry: nil tells
-- lib/palette_logic.lua's apply_decoration to leave it exactly as `search` produced it.
local function decorate(candidates, _player_index)
  local decorations = {}
  for index, candidate in ipairs(candidates) do
    if is_occupied(candidate) then
      local label, search_display_name = ResourceLogic.occupied_label(candidate.label, candidate.occupied_marker)
      decorations[index] = { label = label, search_display_name = search_display_name }
    end
  end
  return decorations
end

--- Registers the resource-name dictionary with flib, for translated-name search.
---
--- Must run from on_init/on_configuration_changed, before the first on_tick -- see
--- control.lua and EXTENDING.md "Translated names". The occupied marker rides in the
--- same dictionary, under OCCUPIED_MARKER_KEY, so `search` gets its translated form
--- from the same `flib_dictionary.get` call as every resource name, rather than
--- standing up a second dictionary for one entry.
---
--- The marker's value is base game's own `[gui]occupied` (`{ "gui.occupied", "" }`),
--- not a locale entry this mod maintains -- passing an empty `__1__` yields the fixed
--- part on its own (`" (occupied)"`, leading space and all; ResourceLogic.occupied_label
--- trims it). Verified by reading every shipped `core/locale/*/core.cfg`: of the 50
--- locales the game ships, 32 define `gui.occupied` and 31 of those order it
--- `__1__ (...)`. So borrowing the key is a strict gain for 31 languages that get only
--- English from a two-language mod entry, neutral for the 18 that leave the key
--- undefined and fall back to English either way, and a word-order compromise for one.
--- It also removes the risk of hand-copied text drifting from the game's own wording.
--- The one exception is Hebrew (`he`), which orders it `(occupied) __1__` -- marker
--- first -- so extracting the fixed part and appending it reverses the intended order
--- there. Not an RTL problem: of the three RTL locales shipped, only Hebrew defines the
--- key at all, and its ordering is its translator's choice. Accepted rather than worked
--- around, because Hebrew already fell back to the English "(occupied)" under the old
--- mod-owned entry, so this is not a regression, and a placeholder's position cannot be
--- recovered from a string it has already been resolved out of.
function ResourceSource.register_dictionary()
  flib_dictionary.new(NAMESPACE)
  for _, prototype in ipairs(collect_resources()) do
    flib_dictionary.add(NAMESPACE, prototype.name, prototype.localised_name)
  end
  flib_dictionary.add(NAMESPACE, OCCUPIED_MARKER_KEY, { "gui.occupied", "" })
end

--- Adds this source's remote interface, named by its declaration in prototypes/sources.lua.
function ResourceSource.add_interface()
  remote.add_interface("quidquid-resources.source", { search = search, decorate = decorate })
end

return ResourceSource
