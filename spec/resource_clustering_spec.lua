local ResourceClustering = require("lib.resource_clustering")

local ALL = 0xFFFFFFFF

-- Every edge full by default, so neighbouring chunks touch unless a spec says otherwise.
local function entry(amount, x, y, edges)
  return {
    amount = amount,
    tiles = 1,
    left = x,
    top = y,
    right = x,
    bottom = y,
    edges = edges or { top = ALL, bottom = ALL, left = ALL, right = ALL },
  }
end

local EMPTY = { top = 0, bottom = 0, left = 0, right = 0 }

local function edges(overrides)
  local result = { top = 0, bottom = 0, left = 0, right = 0 }
  for side, mask in pairs(overrides) do
    result[side] = mask
  end
  return result
end

local function bit(index)
  return bit32.lshift(1, index)
end

describe("ResourceClustering", function()
  describe(".chunk_key", function()
    it("joins the coordinates with a comma", function()
      assert.are.equal("3,-2", ResourceClustering.chunk_key(3, -2))
    end)
  end)

  describe(".is_loose", function()
    it("is false for a one-tile resource", function()
      local box = { left_top = { x = -0.1, y = -0.1 }, right_bottom = { x = 0.1, y = 0.1 } }

      assert.is_false(ResourceClustering.is_loose(box))
    end)

    it("is true for a resource wider than one tile", function()
      local box = { left_top = { x = -1.4, y = -1.4 }, right_bottom = { x = 1.4, y = 1.4 } }

      assert.is_true(ResourceClustering.is_loose(box))
    end)
  end)

  describe(".touches", function()
    it("is true when facing edges share a tile", function()
      local a = entry(1, 0, 0, edges({ right = bit(5) }))
      local b = entry(1, 0, 0, edges({ left = bit(5) }))

      assert.is_true(ResourceClustering.touches(a, b, 1, 0))
      assert.is_true(ResourceClustering.touches(b, a, -1, 0))
    end)

    it("is true when facing edges are one tile apart along the seam", function()
      local a = entry(1, 0, 0, edges({ bottom = bit(5) }))
      local b = entry(1, 0, 0, edges({ top = bit(6) }))

      assert.is_true(ResourceClustering.touches(a, b, 0, 1))
      assert.is_true(ResourceClustering.touches(b, a, 0, -1))
    end)

    it("is false when facing edges are two tiles apart along the seam", function()
      local a = entry(1, 0, 0, edges({ bottom = bit(5) }))
      local b = entry(1, 0, 0, edges({ top = bit(7) }))

      assert.is_false(ResourceClustering.touches(a, b, 0, 1))
    end)

    it("ignores edges that do not face each other", function()
      local a = entry(1, 0, 0, edges({ left = ALL, top = ALL, bottom = ALL }))
      local b = entry(1, 0, 0, edges({ right = ALL, top = ALL, bottom = ALL }))

      assert.is_false(ResourceClustering.touches(a, b, 1, 0))
    end)

    it("joins diagonal neighbours only through both corner tiles", function()
      local a = entry(1, 0, 0, edges({ bottom = bit(31), right = bit(31) }))
      local b = entry(1, 0, 0, edges({ top = bit(0), left = bit(0) }))
      local b_without_corner = entry(1, 0, 0, edges({ top = bit(1), left = bit(1) }))

      assert.is_true(ResourceClustering.touches(a, b, 1, 1))
      assert.is_true(ResourceClustering.touches(b, a, -1, -1))
      assert.is_false(ResourceClustering.touches(a, b_without_corner, 1, 1))
    end)

    it("joins anti-diagonal neighbours through their own corners", function()
      local a = entry(1, 0, 0, edges({ top = bit(31), right = bit(0) }))
      local b = entry(1, 0, 0, edges({ bottom = bit(0), left = bit(31) }))

      assert.is_true(ResourceClustering.touches(a, b, 1, -1))
      assert.is_true(ResourceClustering.touches(b, a, -1, 1))
    end)
  end)

  describe(".group_chunk", function()
    it("sums amount and tile count per resource name", function()
      local grouped = ResourceClustering.group_chunk({
        { name = "iron-ore", amount = 100, position = { x = 1, y = 1 } },
        { name = "iron-ore", amount = 250, position = { x = 2, y = 1 } },
        { name = "copper-ore", amount = 40, position = { x = 3, y = 3 } },
      })

      assert.are.equal(350, grouped["iron-ore"].amount)
      assert.are.equal(2, grouped["iron-ore"].tiles)
      assert.are.equal(40, grouped["copper-ore"].amount)
      assert.are.equal(1, grouped["copper-ore"].tiles)
    end)

    it("bounds each resource by its own entity positions", function()
      local grouped = ResourceClustering.group_chunk({
        { name = "crude-oil", amount = 3000, position = { x = -5, y = 12 } },
        { name = "crude-oil", amount = 9000, position = { x = 20, y = -4 } },
      })

      assert.are.same({ left = -5, top = -4, right = 20, bottom = 12 }, {
        left = grouped["crude-oil"].left,
        top = grouped["crude-oil"].top,
        right = grouped["crude-oil"].right,
        bottom = grouped["crude-oil"].bottom,
      })
    end)

    it("marks the edge tiles each resource occupies", function()
      -- Chunk (-1, 0): tile x -32 is its left column, -1 its right; tile y 0 its top row.
      local grouped = ResourceClustering.group_chunk({
        { name = "iron-ore", amount = 1, position = { x = -31.5, y = 0.5 } },
        { name = "iron-ore", amount = 1, position = { x = -0.5, y = 31.5 } },
        { name = "iron-ore", amount = 1, position = { x = -20.5, y = 10.5 } },
      })

      assert.are.same({
        top = bit(0),
        bottom = bit(31),
        left = bit(0),
        right = bit(31),
      }, grouped["iron-ore"].edges)
    end)

    it("returns an empty table for a chunk with no resources", function()
      assert.are.same({}, ResourceClustering.group_chunk({}))
    end)

    it("anchors on the entity nearest the bounding box's centre", function()
      -- Bounding box centre is ((0.5 + 9.5) / 2, 0.5) = (5.0, 0.5), a tile boundary.
      -- The entity at (4.5, 0.5) is 0.5 tiles from it; the ones at the ends are 4.5 --
      -- so (4.5, 0.5), a real entity position, is the anchor.
      local grouped = ResourceClustering.group_chunk({
        { name = "iron-ore", amount = 100, position = { x = 0.5, y = 0.5 } },
        { name = "iron-ore", amount = 100, position = { x = 9.5, y = 0.5 } },
        { name = "iron-ore", amount = 100, position = { x = 4.5, y = 0.5 } },
      })

      assert.are.same({ x = 4.5, y = 0.5 }, grouped["iron-ore"].anchor)
    end)

    it("breaks a distance tie by the smaller x", function()
      -- Bounding box centre is (5.0, 0.5); both entities are 4.5 tiles from it.
      local grouped = ResourceClustering.group_chunk({
        { name = "iron-ore", amount = 100, position = { x = 9.5, y = 0.5 } },
        { name = "iron-ore", amount = 100, position = { x = 0.5, y = 0.5 } },
      })

      assert.are.same({ x = 0.5, y = 0.5 }, grouped["iron-ore"].anchor)
    end)

    it("breaks a further tie by the smaller y when x is equal", function()
      -- Bounding box centre is (0.5, 5.0); both entities are 4.5 tiles from it.
      local grouped = ResourceClustering.group_chunk({
        { name = "iron-ore", amount = 100, position = { x = 0.5, y = 9.5 } },
        { name = "iron-ore", amount = 100, position = { x = 0.5, y = 0.5 } },
      })

      assert.are.same({ x = 0.5, y = 0.5 }, grouped["iron-ore"].anchor)
    end)
  end)

  describe(".insert", function()
    it("creates a cluster for a chunk with no charted neighbour", function()
      local store = ResourceClustering.new_store()

      local cluster = ResourceClustering.insert(store, 1, "iron-ore", "0,0", entry(100, 5, 5), false)

      assert.are.equal("iron-ore:0,0", cluster.id)
      assert.are.equal(1, cluster.surface_index)
      assert.are.equal(100, cluster.amount)
      assert.are.equal(1, #ResourceClustering.all(store))
    end)

    it("merges a chunk into a cluster that owns a neighbouring chunk", function()
      local store = ResourceClustering.new_store()
      ResourceClustering.insert(store, 1, "iron-ore", "0,0", entry(100, 5, 5), false)

      local cluster = ResourceClustering.insert(store, 1, "iron-ore", "1,0", entry(50, 40, 5), false)

      assert.are.equal("iron-ore:0,0", cluster.id)
      assert.are.equal(150, cluster.amount)
      assert.are.same({ left = 5, top = 5, right = 40, bottom = 5 }, cluster.bounds)
      assert.are.equal(1, #ResourceClustering.all(store))
    end)

    it("keeps a neighbouring chunk separate when the resource does not touch the seam", function()
      local store = ResourceClustering.new_store()
      ResourceClustering.insert(store, 1, "iron-ore", "0,0", entry(100, 5, 5, EMPTY), false)

      ResourceClustering.insert(store, 1, "iron-ore", "0,1", entry(50, 5, 40, EMPTY), false)

      assert.are.equal(2, #ResourceClustering.all(store))
    end)

    it("merges a non-touching neighbour when the resource is loose", function()
      local store = ResourceClustering.new_store()
      ResourceClustering.insert(store, 1, "crude-oil", "0,0", entry(100, 5, 5, EMPTY), true)

      local cluster = ResourceClustering.insert(store, 1, "crude-oil", "1,1", entry(50, 40, 40, EMPTY), true)

      assert.are.equal(150, cluster.amount)
      assert.are.equal(1, #ResourceClustering.all(store))
    end)

    it("merges when the chunk arrives before the neighbour it touches", function()
      local store = ResourceClustering.new_store()
      ResourceClustering.insert(store, 1, "iron-ore", "1,0", entry(50, 40, 5, edges({ left = bit(3) })), false)

      local cluster =
        ResourceClustering.insert(store, 1, "iron-ore", "0,0", entry(100, 5, 5, edges({ right = bit(4) })), false)

      assert.are.equal(150, cluster.amount)
      assert.are.equal(1, #ResourceClustering.all(store))
    end)

    it("keeps a rescanned chunk in its cluster after its edge stops touching", function()
      local store = ResourceClustering.new_store()
      ResourceClustering.insert(store, 1, "iron-ore", "0,0", entry(100, 5, 5), false)
      ResourceClustering.insert(store, 1, "iron-ore", "1,0", entry(50, 40, 5), false)

      ResourceClustering.insert(store, 1, "iron-ore", "1,0", entry(20, 40, 5, EMPTY), false)

      local clusters = ResourceClustering.all(store)
      assert.are.equal(1, #clusters)
      assert.are.equal(120, clusters[1].amount)
    end)

    it("keeps a different resource in the same chunk separate", function()
      local store = ResourceClustering.new_store()
      ResourceClustering.insert(store, 1, "iron-ore", "0,0", entry(100, 5, 5), false)

      ResourceClustering.insert(store, 1, "copper-ore", "0,0", entry(70, 6, 6), false)

      assert.are.equal(2, #ResourceClustering.all(store))
    end)

    it("joins two clusters when a chunk bridges them", function()
      local store = ResourceClustering.new_store()
      ResourceClustering.insert(store, 1, "iron-ore", "0,0", entry(100, 5, 5), false)
      ResourceClustering.insert(store, 1, "iron-ore", "2,0", entry(100, 70, 5), false)
      assert.are.equal(2, #ResourceClustering.all(store))

      local cluster = ResourceClustering.insert(store, 1, "iron-ore", "1,0", entry(10, 40, 5), false)

      assert.are.equal(1, #ResourceClustering.all(store))
      assert.are.equal(210, cluster.amount)
    end)

    it("replaces the entry when the same chunk is inserted twice", function()
      local store = ResourceClustering.new_store()
      ResourceClustering.insert(store, 1, "iron-ore", "0,0", entry(100, 5, 5), false)

      local cluster = ResourceClustering.insert(store, 1, "iron-ore", "0,0", entry(60, 5, 5), false)

      assert.are.equal(60, cluster.amount)
      assert.are.equal(1, #ResourceClustering.all(store))
    end)
  end)

  describe(".remove_chunk", function()
    it("drops the chunk and keeps the cluster", function()
      local store = ResourceClustering.new_store()
      ResourceClustering.insert(store, 1, "iron-ore", "0,0", entry(100, 5, 5), false)
      ResourceClustering.insert(store, 1, "iron-ore", "1,0", entry(50, 40, 5), false)

      assert.is_true(ResourceClustering.remove_chunk(store, "iron-ore", "1,0"))

      local clusters = ResourceClustering.all(store)
      assert.are.equal(1, #clusters)
      assert.are.equal(100, clusters[1].amount)
    end)

    it("removes the cluster once its last chunk is gone", function()
      local store = ResourceClustering.new_store()
      ResourceClustering.insert(store, 1, "iron-ore", "0,0", entry(100, 5, 5), false)

      ResourceClustering.remove_chunk(store, "iron-ore", "0,0")

      assert.are.same({}, ResourceClustering.all(store))
    end)

    it("keeps one cluster when the chunk between its halves is removed", function()
      local store = ResourceClustering.new_store()
      ResourceClustering.insert(store, 1, "iron-ore", "0,0", entry(100, 5, 5), false)
      ResourceClustering.insert(store, 1, "iron-ore", "1,0", entry(10, 40, 5), false)
      ResourceClustering.insert(store, 1, "iron-ore", "2,0", entry(100, 70, 5), false)

      ResourceClustering.remove_chunk(store, "iron-ore", "1,0")

      local clusters = ResourceClustering.all(store)
      assert.are.equal(1, #clusters)
      assert.are.equal(200, clusters[1].amount)
    end)

    it("reports nothing removed for a chunk it does not hold", function()
      local store = ResourceClustering.new_store()

      assert.is_false(ResourceClustering.remove_chunk(store, "iron-ore", "9,9"))
    end)
  end)
end)
