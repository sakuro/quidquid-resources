-- Quidquid's public API cannot load under busted, and this spec tests the extension's
-- own logic, not Quidquid's; Quidquid specs its own matcher and number formatting. The
-- mock matcher matches by plain case-insensitive substring, the same simplification
-- quidquid-blueprints' spec uses, and returns ranges only for the field that won --
-- mirroring the real Matcher:match, which never hands back ranges for the loser.
package.preload["__quidquid__.lib.api"] = function()
  local Matcher = {}
  Matcher.__index = Matcher

  local function ranges_of(query, value)
    if value == nil or query == "" then
      return nil
    end
    local start_byte, end_byte = value:lower():find(query:lower(), 1, true)
    if start_byte == nil then
      return nil
    end
    return { { start_byte = start_byte, end_byte = end_byte } }
  end

  function Matcher:match(_namespace, _id, fields)
    local display = ranges_of(self.query, fields.display)
    local internal = ranges_of(self.query, fields.internal)
    if display == nil and internal == nil then
      return nil
    end
    if display ~= nil then
      return { score = 1, display_ranges = display, internal_ranges = {} }
    end
    return { score = 1, display_ranges = {}, internal_ranges = internal }
  end

  return {
    matcher = function(query, _locale)
      return setmetatable({ query = query }, Matcher)
    end,
    -- The real formatting is Quidquid's own to spec ("9.0k", "4.2M", ...); this mock's
    -- shape ("<9000>") is deliberately unlike it so a test asserting a numeric sort
    -- cannot pass by accident on a string sort of the formatted text -- see "sorts by
    -- the numeric amount, not the formatted amount string" below.
    number_format = {
      suffixed = function(value)
        return ("<%d>"):format(value)
      end,
    },
  }
end

local ResourceLogic = require("lib.resource_logic")

local function cluster(id, resource_name, amount, bounds, chunks)
  return {
    id = id,
    surface_index = 1,
    resource_name = resource_name,
    chunks = chunks or {},
    amount = amount,
    bounds = bounds,
  }
end

describe("ResourceLogic", function()
  describe(".secondary_text", function()
    it("returns the plain string, floored coordinates and all", function()
      local text = ResourceLogic.secondary_text("[planet=nauvis]", { x = -137.5, y = -330.1 })

      assert.are.equal("[planet=nauvis] (-138, -331)", text)
    end)

    it("returns the plain string when position is already whole", function()
      local text = ResourceLogic.secondary_text("[planet=nauvis]", { x = -137, y = -330 })

      assert.are.equal("[planet=nauvis] (-137, -330)", text)
    end)

    -- The occupied marker moved to the name line (see .occupied_label below), so the
    -- second line is a plain string unconditionally now -- there is no third argument
    -- left to flip it into a LocalisedString, and no font-wrapper form to lose the
    -- highlight for. This replaces the old "occupied is true" case above, which
    -- asserted the marker landed here.
    it("never includes the occupied marker, even a stray extra argument is ignored", function()
      local text = ResourceLogic.secondary_text("[planet=nauvis]", { x = -137.5, y = -330.1 }, true)

      assert.are.equal("[planet=nauvis] (-138, -331)", text)
    end)
  end)

  describe(".build_candidates", function()
    -- Each fixture cluster carries a real chunks table, not just bounds: position comes
    -- from the richest chunk's `anchor`, an actual entity position recorded by
    -- ResourceClustering.group_chunk -- never a computed centre. See lib/resource_logic.lua
    -- for why a computed centre can land on a tile boundary with no ore under it.
    local clusters = {
      cluster("iron-ore:0,0", "iron-ore", 5000, { left = 0, top = 0, right = 40, bottom = 20 }, {
        ["0,0"] = { amount = 5000, left = 0, top = 0, right = 40, bottom = 20, anchor = { x = 20, y = 10 } },
      }),
      cluster("iron-ore:9,9", "iron-ore", 9000, { left = 300, top = 300, right = 310, bottom = 310 }, {
        ["9,9"] = { amount = 9000, left = 300, top = 300, right = 310, bottom = 310, anchor = { x = 305, y = 305 } },
      }),
      cluster("copper-ore:0,0", "copper-ore", 100, { left = -10, top = -10, right = 0, bottom = 0 }, {
        ["0,0"] = { amount = 100, left = -10, top = -10, right = 0, bottom = 0, anchor = { x = -5, y = -5 } },
      }),
    }
    local translated = { ["iron-ore"] = "Iron ore", ["copper-ore"] = "Copper ore" }
    local localised_names = {
      ["iron-ore"] = { "entity-name.iron-ore" },
      ["copper-ore"] = { "entity-name.copper-ore" },
    }

    it("matches on the translated name", function()
      local candidates = ResourceLogic.build_candidates("iron", clusters, "en", translated, localised_names)

      assert.are.equal(2, #candidates)
      assert.are.equal("resource", candidates[1].type)
      -- candidates[1] is the 9000-amount cluster (richest first); the mock's
      -- number_format.suffixed renders that as "<9000>".
      assert.are.equal("Iron ore <9000>", candidates[1].search_display_name)
    end)

    it("matches on the prototype name", function()
      local candidates = ResourceLogic.build_candidates("copper-ore", clusters, "en", translated, localised_names)

      assert.are.equal(1, #candidates)
      assert.are.equal("copper-ore:0,0", candidates[1].id)
    end)

    it("orders same-named clusters by descending amount", function()
      local candidates = ResourceLogic.build_candidates("iron", clusters, "en", translated, localised_names)

      assert.are.equal("iron-ore:9,9", candidates[1].id)
      assert.are.equal("iron-ore:0,0", candidates[2].id)
    end)

    it("puts the richest chunk's anchor on a single-chunk cluster", function()
      local candidates = ResourceLogic.build_candidates("copper", clusters, "en", translated, localised_names)

      assert.are.same({ x = -5, y = -5 }, candidates[1].position)
    end)

    it("anchors position on the richest chunk's anchor, not the bounding box's centre", function()
      local multi_chunk_clusters = {
        cluster("iron-ore:multi", "iron-ore", 6000, { left = 0, top = 0, right = 340, bottom = 20 }, {
          ["0,0"] = { amount = 1000, left = 0, top = 0, right = 40, bottom = 20, anchor = { x = 20, y = 10 } },
          ["9,0"] = { amount = 5000, left = 300, top = 0, right = 340, bottom = 20, anchor = { x = 320, y = 10 } },
        }),
      }

      local candidates = ResourceLogic.build_candidates("iron", multi_chunk_clusters, "en", translated, localised_names)

      -- The richer chunk ("9,0", amount 5000) anchors at (320, 10), an actual entity
      -- position. The bounding box centres at (170, 10) -- off the ore entirely, which
      -- is exactly the bug the anchor exists to avoid.
      assert.are.same({ x = 320, y = 10 }, candidates[1].position)
    end)

    it("uses the richest chunk's recorded entity position, not a midpoint that can fall on a tile boundary", function()
      -- Entities at tile centres x = 0.5 and x = 9.5 span an odd number of tiles: their
      -- midpoint is (0.5 + 9.5) / 2 = 5.0, a whole integer -- a tile BOUNDARY, inside no
      -- resource entity's collision box. This is the exact defect reported in the field
      -- (see lib/resource_logic.lua's comment). group_chunk's anchor is recorded from a
      -- real entity, so it is immune to this per-axis parity coin-flip.
      local parity_clusters = {
        cluster("iron-ore:parity", "iron-ore", 2000, { left = 0.5, top = 0.5, right = 9.5, bottom = 0.5 }, {
          ["0,0"] = { amount = 2000, left = 0.5, top = 0.5, right = 9.5, bottom = 0.5, anchor = { x = 9.5, y = 0.5 } },
        }),
      }

      local candidates = ResourceLogic.build_candidates("iron", parity_clusters, "en", translated, localised_names)

      assert.are.same({ x = 9.5, y = 0.5 }, candidates[1].position)
      assert.are_not.equal(5.0, candidates[1].position.x)
    end)

    it("breaks a tie between equally rich chunks by chunk key, ascending", function()
      local tied_clusters = {
        cluster("iron-ore:tie", "iron-ore", 2000, { left = 0, top = 0, right = 340, bottom = 20 }, {
          ["9,0"] = { amount = 1000, left = 300, top = 0, right = 340, bottom = 20, anchor = { x = 320, y = 10 } },
          ["0,0"] = { amount = 1000, left = 0, top = 0, right = 40, bottom = 20, anchor = { x = 20, y = 10 } },
        }),
      }

      local candidates = ResourceLogic.build_candidates("iron", tied_clusters, "en", translated, localised_names)

      assert.are.same({ x = 20, y = 10 }, candidates[1].position)
    end)

    it("names the resource's entity sprite as the icon", function()
      local candidates = ResourceLogic.build_candidates("copper", clusters, "en", translated, localised_names)

      assert.are.equal("entity/copper-ore", candidates[1].icon)
    end)

    it("labels a candidate with the translated name and the amount when a translation is available", function()
      local candidates = ResourceLogic.build_candidates("copper", clusters, "en", translated, localised_names)

      -- The copper-ore fixture's amount is 100; the mock's number_format.suffixed
      -- renders it as "<100>".
      assert.are.equal("Copper ore <100>", candidates[1].label)
    end)

    it("falls back to the localised name, with the amount appended, when untranslated", function()
      local candidates = ResourceLogic.build_candidates("copper", clusters, "en", {}, localised_names)

      assert.are.same({ "", { "entity-name.copper-ore" }, " ", "<100>" }, candidates[1].label)
    end)

    it("sets both label and search_display_name to the same plain string when translated", function()
      local candidates = ResourceLogic.build_candidates("copper", clusters, "en", translated, localised_names)

      assert.are.equal("Copper ore <100>", candidates[1].label)
      assert.are.equal("Copper ore <100>", candidates[1].search_display_name)
    end)

    it("leaves search_display_name nil when untranslated, even though label still carries the amount", function()
      local candidates = ResourceLogic.build_candidates("copper", clusters, "en", {}, localised_names)

      assert.is_nil(candidates[1].search_display_name)
      assert.are.same({ "", { "entity-name.copper-ore" }, " ", "<100>" }, candidates[1].label)
    end)

    it("keeps search_display_ranges inside the name, not spilling into the appended amount", function()
      local candidates = ResourceLogic.build_candidates("copper", clusters, "en", translated, localised_names)

      -- "Copper ore" is 10 bytes; the amount is appended after it, so every matched
      -- range must stay within those first 10 bytes for the highlight to still land
      -- on the name after the append.
      local name_length = #"Copper ore"
      assert.is_true(#candidates[1].search_display_ranges > 0)
      for _, range in ipairs(candidates[1].search_display_ranges) do
        assert.is_true(range.end_byte <= name_length)
      end
    end)

    it("sorts by the numeric amount, not the formatted amount string", function()
      -- The mock formats 10000 as "<10000>" and 800 as "<800>", which sort in the
      -- OPPOSITE order as strings ("<10000>" < "<800>", since "1" < "8") from how they
      -- sort as numbers. Comparing amount as a number must still put the 10000 cluster
      -- first; a sort that compared the formatted string instead would fail this.
      local unformatted_order_clusters = {
        cluster("iron-ore:small", "iron-ore", 800, { left = 0, top = 0, right = 10, bottom = 10 }, {
          ["0,0"] = { amount = 800, left = 0, top = 0, right = 10, bottom = 10, anchor = { x = 5, y = 5 } },
        }),
        cluster("iron-ore:large", "iron-ore", 10000, { left = 100, top = 100, right = 110, bottom = 110 }, {
          ["10,10"] = {
            amount = 10000,
            left = 100,
            top = 100,
            right = 110,
            bottom = 110,
            anchor = { x = 105, y = 105 },
          },
        }),
      }

      local candidates =
        ResourceLogic.build_candidates("iron", unformatted_order_clusters, "en", translated, localised_names)

      assert.are.equal("iron-ore:large", candidates[1].id)
      assert.are.equal("iron-ore:small", candidates[2].id)
    end)

    it("returns nothing when no cluster matches", function()
      assert.are.same({}, ResourceLogic.build_candidates("uranium", clusters, "en", translated, localised_names))
    end)

    it("puts the surface token and the floored position on secondary_text", function()
      local surface_tokens = { [1] = "[planet=nauvis]" }
      local candidates =
        ResourceLogic.build_candidates("copper", clusters, "en", translated, localised_names, surface_tokens)

      -- The copper-ore fixture's anchor is { x = -5, y = -5 }, already whole numbers;
      -- see the floored-position case below for a fixture that actually exercises
      -- math.floor.
      assert.are.equal("[planet=nauvis] (-5, -5)", candidates[1].secondary_text)
    end)

    it("floors fractional coordinates on secondary_text", function()
      local fractional_clusters = {
        cluster("iron-ore:fractional", "iron-ore", 2000, { left = 0, top = 0, right = 10, bottom = 10 }, {
          ["0,0"] = { amount = 2000, left = 0, top = 0, right = 10, bottom = 10, anchor = { x = -137.5, y = 9.9 } },
        }),
      }
      local surface_tokens = { [1] = "[planet=nauvis]" }

      local candidates =
        ResourceLogic.build_candidates("iron", fractional_clusters, "en", translated, localised_names, surface_tokens)

      assert.are.equal("[planet=nauvis] (-138, 9)", candidates[1].secondary_text)
    end)

    it("does not set search_internal_name or search_internal_ranges on a resource candidate", function()
      local surface_tokens = { [1] = "[planet=nauvis]" }
      local candidates =
        ResourceLogic.build_candidates("copper", clusters, "en", translated, localised_names, surface_tokens)

      assert.is_nil(candidates[1].search_internal_name)
      assert.is_nil(candidates[1].search_internal_ranges)
    end)

    it("still matches on the prototype name once search_internal_name is no longer displayed", function()
      local surface_tokens = { [1] = "[planet=nauvis]" }
      local candidates =
        ResourceLogic.build_candidates("copper-ore", clusters, "en", translated, localised_names, surface_tokens)

      assert.are.equal(1, #candidates)
      assert.are.equal("copper-ore:0,0", candidates[1].id)
    end)

    it("falls back to a usable secondary_text when the surface has no token in the map", function()
      -- surface_tokens is deliberately empty: a caller that did not describe this
      -- cluster's surface (or omitted the map entirely) must not crash or render
      -- a literal "nil" on the second line. This is also the only remaining coverage
      -- of the surface-index fallback -- there used to be a second, near-identical
      -- test asserting it through a candidate.surface_token field, but that field had
      -- no reader left once mark_occupied stopped rebuilding secondary_text from it,
      -- so it (and the now-duplicate test) were dropped rather than kept as dead
      -- weight.
      local candidates = ResourceLogic.build_candidates("copper", clusters, "en", translated, localised_names, {})

      assert.are.equal("1 (-5, -5)", candidates[1].secondary_text)
    end)

    it("builds a candidate with a plain-string secondary_text and no annotation", function()
      -- The occupied marker used to be a right-end `annotation` set by the runtime
      -- resource_source.lua, applied after build_candidates ran. That field is gone
      -- now: build_candidates itself never sets it, occupied or not -- occupancy is a
      -- runtime fact this pure module has no way to know at candidate-build time.
      local surface_tokens = { [1] = "[planet=nauvis]" }
      local candidates =
        ResourceLogic.build_candidates("copper", clusters, "en", translated, localised_names, surface_tokens)

      assert.are.equal("[planet=nauvis] (-5, -5)", candidates[1].secondary_text)
      assert.is_nil(candidates[1].annotation)
    end)

    it(
      "carries the translated occupied marker on the candidate, for the runtime source to rebuild the name with",
      function()
        -- lib/resource_source.lua's mark_occupied only learns whether a patch is
        -- occupied after build_candidates has already run (occupancy is a runtime fact,
        -- checked by find_entities_filtered against a live surface). Carrying the
        -- translated marker on the candidate, the same way surface_token is carried, lets
        -- that later step call ResourceLogic.occupied_label without threading the
        -- dictionary lookup back through here.
        local candidates =
          ResourceLogic.build_candidates("copper", clusters, "en", translated, localised_names, {}, "(occupied)")

        assert.are.equal("(occupied)", candidates[1].occupied_marker)
      end
    )

    it("leaves occupied_marker nil when the caller passes none", function()
      local candidates = ResourceLogic.build_candidates("copper", clusters, "en", translated, localised_names)

      assert.is_nil(candidates[1].occupied_marker)
    end)
  end)

  describe(".occupied_label", function()
    it("appends the translated marker to a plain-string label, keeping it a plain string", function()
      local label, search_display_name = ResourceLogic.occupied_label("Iron ore 4.2M", "(occupied)")

      assert.are.equal("Iron ore 4.2M (occupied)", label)
      assert.are.equal("Iron ore 4.2M (occupied)", search_display_name)
    end)

    it("keeps the match inside the name portion once the marker is appended to a translated label", function()
      -- Mirrors what mark_occupied actually does: take a real build_candidates label
      -- and append the marker, then confirm search_display_ranges (unmodified by
      -- occupied_label) still lands inside the name prefix.
      local clusters = {
        cluster("copper-ore:0,0", "copper-ore", 100, { left = -10, top = -10, right = 0, bottom = 0 }, {
          ["0,0"] = { amount = 100, left = -10, top = -10, right = 0, bottom = 0, anchor = { x = -5, y = -5 } },
        }),
      }
      local translated = { ["copper-ore"] = "Copper ore" }
      local localised_names = { ["copper-ore"] = { "entity-name.copper-ore" } }
      local candidates = ResourceLogic.build_candidates("copper", clusters, "en", translated, localised_names)
      local candidate = candidates[1]

      candidate.label, candidate.search_display_name = ResourceLogic.occupied_label(candidate.label, "(occupied)")

      assert.are.equal("Copper ore <100> (occupied)", candidate.search_display_name)
      local name_length = #"Copper ore"
      assert.is_true(#candidate.search_display_ranges > 0)
      for _, range in ipairs(candidate.search_display_ranges) do
        assert.is_true(range.end_byte <= name_length)
      end
    end)

    it("splices the marker into a LocalisedString label when the name itself is not yet translated", function()
      local untranslated_label = { "", { "entity-name.iron-ore" }, " ", "4.2M" }

      local label, search_display_name = ResourceLogic.occupied_label(untranslated_label, nil)

      assert.are.same({ "", { "entity-name.iron-ore" }, " ", "4.2M", " ", { "gui.occupied", "" } }, label)
      assert.is_nil(search_display_name)
    end)

    it(
      "splices the marker into a LocalisedString label when the name is untranslated, even if the marker "
        .. "itself happens to already be translated",
      function()
        -- The marker's own translation status is irrelevant once the name is not a
        -- plain string: there is no highlighting left to protect in this branch, so
        -- the LocalisedString form is used either way, keyed by locale key rather than
        -- embedding the already-translated plain text.
        local untranslated_label = { "", { "entity-name.iron-ore" }, " ", "4.2M" }

        local label, search_display_name = ResourceLogic.occupied_label(untranslated_label, "(occupied)")

        assert.are.same({ "", { "entity-name.iron-ore" }, " ", "4.2M", " ", { "gui.occupied", "" } }, label)
        assert.is_nil(search_display_name)
      end
    )

    it(
      "falls back to the LocalisedString form, not a sentinel key or nil, when the marker is not yet translated",
      function()
        local label, search_display_name = ResourceLogic.occupied_label("Iron ore 4.2M", nil)

        assert.are.same({ "", "Iron ore 4.2M", " ", { "gui.occupied", "" } }, label)
        assert.is_nil(search_display_name)
      end
    )

    it("trims surrounding whitespace off the marker before splicing in its own single space", function()
      -- gui.occupied resolved with an empty __1__ yields its fixed part on its own --
      -- " (occupied)" in English, leading space and all. occupied_label must not just
      -- concatenate that verbatim (which would double the space); it trims both ends
      -- first and supplies exactly one separating space itself.
      local label, search_display_name = ResourceLogic.occupied_label("Iron ore 4.2M", "  (occupied)  ")

      assert.are.equal("Iron ore 4.2M (occupied)", label)
      assert.are.equal("Iron ore 4.2M (occupied)", search_display_name)
    end)
  end)
end)
