local ResourceClustering = {}

local CHUNK_SIZE = 32
local LAST = CHUNK_SIZE - 1

--- The storage key for one chunk position.
---
--- A string rather than a nested table so a chunk can index a flat map, which is what
--- neighbour lookups walk on every insert.
---@param x number  chunk x, not tile x
---@param y number  chunk y, not tile y
---@return string
function ResourceClustering.chunk_key(x, y)
  return x .. "," .. y
end

--- True when a resource's collision box is larger than one tile.
---
--- Such resources -- crude oil, sulfuric acid geysers, fluorine vents, lithium brine --
--- are placed as scattered 3x3 entities that never touch each other, so testing
--- whether they reach across a chunk seam would split every field into its wells.
--- They merge on chunk adjacency alone instead, as Resource Monitor does. The
--- ores and scrap are one tile. See issue #193.
---@param collision_box BoundingBox  with left_top and right_bottom as {x, y} tables
---@return boolean
function ResourceClustering.is_loose(collision_box)
  return collision_box.right_bottom.x - collision_box.left_top.x > 1
    or collision_box.right_bottom.y - collision_box.left_top.y > 1
end

-- A bit per tile along each chunk edge. An entity's chunk-local coordinate comes from
-- the floor modulo, which Lua's % already is, so the chunk's own position is not needed.
local function record_edges(edges, position)
  local x = math.floor(position.x) % CHUNK_SIZE
  local y = math.floor(position.y) % CHUNK_SIZE
  if y == 0 then
    edges.top = bit32.bor(edges.top, bit32.lshift(1, x))
  end
  if y == LAST then
    edges.bottom = bit32.bor(edges.bottom, bit32.lshift(1, x))
  end
  if x == 0 then
    edges.left = bit32.bor(edges.left, bit32.lshift(1, y))
  end
  if x == LAST then
    edges.right = bit32.bor(edges.right, bit32.lshift(1, y))
  end
end

-- Facing masks overlap within one tile of each other, so a diagonal step across the seam
-- counts as touching, the same 8-connectivity as within a chunk.
local function masks_touch(a, b)
  return bit32.band(a, bit32.bor(b, bit32.lshift(b, 1), bit32.rshift(b, 1))) ~= 0
end

local function has_bit(mask, index)
  return bit32.btest(mask, bit32.lshift(1, index))
end

--- True when one resource's tiles in two neighbouring chunks touch across their seam.
---
--- Tiles touch when they are 8-connected, including across a chunk corner. This is the
--- edge-mask test Resource Monitor merges ore on; see issue #193.
---@param entry table  as group_chunk produces per resource
---@param neighbour table  the same resource's entry in the neighbouring chunk
---@param dx integer  the neighbour's chunk x minus this chunk's, -1 to 1
---@param dy integer  the neighbour's chunk y minus this chunk's, -1 to 1
---@return boolean
function ResourceClustering.touches(entry, neighbour, dx, dy)
  local a, b = entry.edges, neighbour.edges
  if dx == 0 and dy == -1 then
    return masks_touch(a.top, b.bottom)
  elseif dx == 0 and dy == 1 then
    return masks_touch(a.bottom, b.top)
  elseif dx == -1 and dy == 0 then
    return masks_touch(a.left, b.right)
  elseif dx == 1 and dy == 0 then
    return masks_touch(a.right, b.left)
  end
  -- A diagonal neighbour meets this chunk at a single corner tile on each side.
  local own_corner = dy == -1 and a.top or a.bottom
  local their_corner = dy == -1 and b.bottom or b.top
  return has_bit(own_corner, dx == -1 and 0 or LAST) and has_bit(their_corner, dx == -1 and LAST or 0)
end

--- One chunk's resource entities, summed per resource name.
---
--- Reads only `.name`, `.amount` and `.position`, so a spec can hand it plain tables
--- where the runtime hands it a LuaEntity array -- no per-entity allocation on the
--- scanning path.
---@param entities table  array of things answering .name, .amount and .position
---@return table  resource name -> { amount, tiles, left, top, right, bottom, anchor,
---  edges }; edges holds a 32-bit tile mask per side, keyed top, bottom, left, right
function ResourceClustering.group_chunk(entities)
  local grouped = {}
  for _, entity in ipairs(entities) do
    local entry = grouped[entity.name]
    local position = entity.position
    if entry == nil then
      grouped[entity.name] = {
        amount = entity.amount,
        tiles = 1,
        left = position.x,
        top = position.y,
        right = position.x,
        bottom = position.y,
        edges = { top = 0, bottom = 0, left = 0, right = 0 },
      }
      record_edges(grouped[entity.name].edges, position)
    else
      entry.amount = entry.amount + entity.amount
      entry.tiles = entry.tiles + 1
      entry.left = math.min(entry.left, position.x)
      entry.top = math.min(entry.top, position.y)
      entry.right = math.max(entry.right, position.x)
      entry.bottom = math.max(entry.bottom, position.y)
      record_edges(entry.edges, position)
    end
  end

  -- Second pass, once every entry's bounding box is final: pick, per resource, the
  -- entity closest to that box's centre as the anchor. The centre itself can fall on a
  -- tile boundary (see lib.resource_logic) and is only ever used here to rank real
  -- entity positions -- it is never returned as a position itself. A tie is broken by
  -- smaller x, then smaller y, so the result does not depend on entities' iteration
  -- order.
  local anchor_distance = {}
  for _, entity in ipairs(entities) do
    local entry = grouped[entity.name]
    local position = entity.position
    local centre_x = (entry.left + entry.right) / 2
    local centre_y = (entry.top + entry.bottom) / 2
    local dx, dy = position.x - centre_x, position.y - centre_y
    local distance = dx * dx + dy * dy
    local best_distance = anchor_distance[entity.name]
    if
      best_distance == nil
      or distance < best_distance
      or (
        distance == best_distance
        and (position.x < entry.anchor.x or (position.x == entry.anchor.x and position.y < entry.anchor.y))
      )
    then
      entry.anchor = { x = position.x, y = position.y }
      anchor_distance[entity.name] = distance
    end
  end

  return grouped
end

-- Recomputed from the cluster's chunks after every mutation rather than adjusted in
-- place. A cluster holds a handful of chunks, so this is cheap, and it removes the
-- class of bug where an incremental update drifts from the chunks it summarises.
local function recalculate(cluster)
  local amount, bounds = 0, nil
  for _, entry in pairs(cluster.chunks) do
    amount = amount + entry.amount
    if bounds == nil then
      bounds = { left = entry.left, top = entry.top, right = entry.right, bottom = entry.bottom }
    else
      bounds.left = math.min(bounds.left, entry.left)
      bounds.top = math.min(bounds.top, entry.top)
      bounds.right = math.max(bounds.right, entry.right)
      bounds.bottom = math.max(bounds.bottom, entry.bottom)
    end
  end
  cluster.amount = amount
  cluster.bounds = bounds
  return cluster
end

local function absorb(store, target, other)
  for key, entry in pairs(other.chunks) do
    target.chunks[key] = entry
    store.owner[other.resource_name][key] = target.id
  end
  store.clusters[other.id] = nil
end

--- An empty cluster store for one surface.
---@return table  { clusters = {}, owner = {} }; see this task's Interfaces
function ResourceClustering.new_store()
  return { clusters = {}, owner = {} }
end

--- Folds one chunk's worth of a resource into the store, merging with any neighbour.
---
--- A neighbouring chunk is merged only where the resource touches across the seam, or
--- on adjacency alone when `loose` is set -- see is_loose. A chunk that bridges two
--- clusters joins all of them into one. A chunk already in a cluster stays in it even
--- if its rescanned tiles no longer reach that cluster's other chunks: clusters never
--- split (issue #174 "On clusters that never split").
---@param store table  from new_store
---@param surface_index uint
---@param resource_name string
---@param key string  as chunk_key returns it
---@param entry table  as group_chunk produces per resource
---@param loose boolean  as is_loose returns it for this resource
---@return table  the cluster the chunk now belongs to
function ResourceClustering.insert(store, surface_index, resource_name, key, entry, loose)
  local owner = store.owner[resource_name]
  if owner == nil then
    owner = {}
    store.owner[resource_name] = owner
  end

  local target = owner[key] and store.clusters[owner[key]] or nil
  local x, y = key:match("^(-?%d+),(-?%d+)$")
  x, y = tonumber(x), tonumber(y)
  for dx = -1, 1 do
    for dy = -1, 1 do
      local neighbour_key = ResourceClustering.chunk_key(x + dx, y + dy)
      local neighbour = owner[neighbour_key] and store.clusters[owner[neighbour_key]] or nil
      if
        neighbour ~= nil
        and neighbour_key ~= key
        and (loose or ResourceClustering.touches(entry, neighbour.chunks[neighbour_key], dx, dy))
      then
        if target == nil then
          target = neighbour
        elseif neighbour.id ~= target.id then
          absorb(store, target, neighbour)
        end
      end
    end
  end

  if target == nil then
    target = {
      id = resource_name .. ":" .. key,
      surface_index = surface_index,
      resource_name = resource_name,
      chunks = {},
    }
    store.clusters[target.id] = target
  end

  target.chunks[key] = entry
  owner[key] = target.id
  return recalculate(target)
end

--- Every cluster in the store, as an array.
---@param store table  from new_store
---@return table  array of clusters; order is not guaranteed
function ResourceClustering.all(store)
  local clusters = {}
  for _, cluster in pairs(store.clusters) do
    table.insert(clusters, cluster)
  end
  return clusters
end

--- Takes one chunk out of whatever cluster holds it.
---
--- Never splits: a cluster whose remaining chunks are no longer contiguous stays one
--- cluster, so a patch a player already knows does not silently become two. It goes
--- away only once nothing is left of it.
---@param store table  from new_store
---@param resource_name string
---@param key string  as chunk_key returns it
---@return boolean  false when the store held no such chunk
function ResourceClustering.remove_chunk(store, resource_name, key)
  local owner = store.owner[resource_name]
  local cluster = owner and owner[key] and store.clusters[owner[key]] or nil
  if cluster == nil then
    return false
  end

  cluster.chunks[key] = nil
  owner[key] = nil
  if next(cluster.chunks) == nil then
    store.clusters[cluster.id] = nil
  else
    recalculate(cluster)
  end
  return true
end

return ResourceClustering
