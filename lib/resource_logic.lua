local api = require("__quidquid__.lib.api")

local ResourceLogic = {}

-- A geometric centre is not safe to hand to LuaPlayer.add_pin: resource entities sit at
-- tile centres (n + 0.5), so averaging a chunk's min and max entity coordinate on an
-- axis gives (i + j) / 2 + 0.5, which lands on another tile centre only when i + j is
-- even. When i + j is odd it lands on a bare tile BOUNDARY, inside no entity's
-- collision box. That parity is a per-axis coin-flip independent of patch shape, so it
-- bit convex, single-chunk patches as often as ring-shaped ones (confirmed in the
-- field: the engine's "no resource entity found at the given position" fires for
-- exactly the patches whose richest chunk spans an odd number of tiles on some axis).
-- The pin is anchored on an actual entity position instead, which
-- ResourceClustering.group_chunk records as the chunk's `anchor`; a real entity's own
-- position is always on ore. Chunks with equal amounts are ordered by chunk key,
-- ascending, so the result is stable across runs regardless of pairs() iteration order.
local function richest_chunk_anchor(chunks)
  local best_key, best_entry
  for key, entry in pairs(chunks) do
    if
      best_entry == nil
      or entry.amount > best_entry.amount
      or (entry.amount == best_entry.amount and key < best_key)
    then
      best_key, best_entry = key, entry
    end
  end
  return best_entry.anchor
end

-- The point measured to is the caller's `position`, the richest-chunk anchor the second
-- line already prints, so the distance and the coordinates agree. That follows from
-- reusing the position already in hand rather than from weighing it against the patch's
-- nearest edge; the game's own pin measures the latter, so a pin reads lower on the
-- same patch.
--
-- nil rather than a number for a patch on another surface: a straight line between two
-- surfaces is not a distance anyone can walk, so the second line shows the coordinates
-- alone there. The floor is this function's half of a contract, not a guard: the
-- `distance` parameter it feeds is documented as whole metres, so a float truncated
-- later inside `suffixed` would make that documentation a lie.
local function distance_to(player_location, surface_index, position)
  if player_location == nil or player_location.surface_index ~= surface_index then
    return nil
  end
  local dx = position.x - player_location.position.x
  local dy = position.y - player_location.position.y
  return math.floor(math.sqrt(dx * dx + dy * dy))
end

--- A patch's own second line: where it is, not what it's called.
---
--- Every patch of one resource shares the same prototype name, so putting that name
--- on the muted second line (as search_internal_name would) gives ten identical
--- lines for ten patches. The surface token plus the anchor's floored coordinates
--- does distinguish them, and the coordinates match the anchor used for the pin and
--- remote view, so what is shown is where the player actually lands.
---
--- A patch already worked by a mining drill is occupied, a runtime fact this pure
--- module never learns on its own (see lib/resource_source.lua, which calls
--- back in once it knows). The marker lives on the name line instead (see
--- `.occupied_label`), matching where Factorio's own map search puts it, so this
--- second line stays a plain string that only says where the patch is.
---
--- The distance's unit symbol is a hardcoded ASCII "m", not base game's
--- `si-unit-meter-short`, even though 43 of the 50 shipped locales define that key.
--- Borrowing it would pair a localised symbol with Quidquid's hardcoded ASCII tier
--- suffix, so Russian would read "1.2kм", the unit in Cyrillic and the prefix in
--- Latin. An SI unit symbol is language-independent by definition, so ASCII
--- throughout agrees with the suffix and keeps this line a plain string, with no
--- dictionary round-trip and no window during which the symbol is missing. One tile
--- is one metre (https://wiki.factorio.com/Map_structure#Real_world_size_analogy),
--- so `suffixed`'s k and M tiers read as the SI prefixes of the same name.
---@param surface_token string  the surface's display token, "[planet=x]" or a plain name
---@param position table  { x, y }, the candidate's own position
---@param distance number|nil  whole metres from the player, already floored by the
--- caller; nil for a patch the player cannot walk to, which leaves the line at the
--- coordinates
---@return string  the surface token, the floored coordinates and, given a distance,
--- that distance in metres
function ResourceLogic.secondary_text(surface_token, position, distance)
  local text = ("%s (%d, %d)"):format(surface_token, math.floor(position.x), math.floor(position.y))
  if distance == nil then
    return text
  end
  return text .. " " .. api.number_format.suffixed(distance) .. "m"
end

--- Splices the occupied marker onto a candidate's name-line label.
---
--- Called by lib/resource_source.lua's decorate once it has learned, at
--- search time, that a mining drill already works this patch, which build_candidates
--- cannot know when it first builds the label. Two label shapes come
--- in, both needing the marker appended so the occupied form matches Factorio's own map
--- search:
---
--- - A plain string (`"<name> <amount>"`, once the name itself is translated) stays a
---   plain string when the marker is too, by appending it directly. This keeps
---   search_display_ranges, which point into the name prefix, valid for highlighting.
--- - A LocalisedString (`{ "", localised_name, " ", amount }`, while the name is still
---   untranslated) has no highlighting to protect, so the marker is spliced in as its
---   own LocalisedString regardless of whether the marker itself has been translated.
---
--- A plain-string label with no translated marker yet falls back to the LocalisedString
--- form instead of rendering nothing or the raw dictionary key. Highlighting is lost
--- only for the short window before the marker's own translation arrives.
---
--- `occupied_marker` is base game's `{ "gui.occupied", "" }` resolved with an empty
--- `__1__` (see resource_source.lua's `register_dictionary`), which yields the fixed
--- part on its own (`" (occupied)"` in English, with a leading space). It is therefore
--- trimmed on both ends here before this function adds its own single separating
--- space.
---@param label string|table  the candidate's own label, as build_candidates set it
---@param occupied_marker string|nil  the marker's own translated plain string, from
--- flib's dictionary under resource_source.lua's sentinel key and carried on the
--- candidate as `occupied_marker`; nil when not yet translated. May carry leading or
--- trailing whitespace; trimmed before use.
---@return string|table  the new label, marker appended or spliced in
---@return string|nil  the new search_display_name: the new label itself when it is
--- still a plain string, nil otherwise
function ResourceLogic.occupied_label(label, occupied_marker)
  if type(label) == "string" and occupied_marker ~= nil then
    local trimmed_marker = occupied_marker:match("^%s*(.-)%s*$")
    local marked = label .. " " .. trimmed_marker
    return marked, marked
  end
  if type(label) == "string" then
    return { "", label, " ", { "gui.occupied", "" } }, nil
  end
  local spliced = { table.unpack(label) }
  table.insert(spliced, " ")
  table.insert(spliced, { "gui.occupied", "" })
  return spliced, nil
end

--- Builds the resource source's candidates for one query.
---
--- Clusters of one resource all carry the same name and so the same match score.
--- PaletteLogic.merge_candidates breaks a score tie by arrival order, which for one
--- source is this array's order. Sorting here by amount therefore decides the order a
--- player sees, without bending search_score to carry it.
---@param query string
---@param clusters table  array of clusters, as lib.resource_clustering builds them
---@param translated_names table  resource name -> translated name, from flib's dictionary
---@param localised_names table  resource name -> LocalisedString, from the resource
--- prototypes; used as the label until a translated name arrives
---@param surface_tokens table  surface_index -> display token ("[planet=x]" or a plain
--- surface name), built by the caller from the LuaSurface it already has in hand; a
--- cluster whose surface has no entry falls back to the surface index itself
---@param occupied_marker string|nil  the occupied marker's own translated plain string,
--- from flib's dictionary; carried onto every candidate as `occupied_marker` for
--- lib/resource_source.lua's decorate to pass to `.occupied_label` once it
--- learns, at search time, which candidates are actually occupied
---@param player_location table|nil  { surface_index = uint, position = MapPosition },
--- the player's physical controller's own pair, extracted by lib/resource_source.lua;
--- nil leaves every candidate without a distance
---@return table  candidates, richest first; see EXTENDING.md "Candidates"
function ResourceLogic.build_candidates(
  query,
  clusters,
  translated_names,
  localised_names,
  surface_tokens,
  occupied_marker,
  player_location
)
  local candidates = {}
  local matcher = api.matcher(query)
  surface_tokens = surface_tokens or {}
  for _, cluster in ipairs(clusters) do
    local translated = translated_names[cluster.resource_name]
    local match = matcher:match("resource", cluster.resource_name, {
      display = translated,
      internal = cluster.resource_name,
    })
    if match ~= nil then
      local position = richest_chunk_anchor(cluster.chunks)
      local surface_token = surface_tokens[cluster.surface_index] or tostring(cluster.surface_index)
      local amount_text = api.number_format.suffixed(cluster.amount)
      -- The amount goes after the name, in both cases: appended directly when
      -- `translated` is a plain string (see the module comment on why that is safe
      -- for search_display_ranges), or spliced into a LocalisedString when only the
      -- prototype's localised_name is available.
      local label, search_display_name
      if translated ~= nil then
        label = translated .. " " .. amount_text
        search_display_name = label
      else
        label = { "", localised_names[cluster.resource_name], " ", amount_text }
      end
      table.insert(candidates, {
        type = "resource",
        id = cluster.id,
        resource_name = cluster.resource_name,
        surface_index = cluster.surface_index,
        amount = cluster.amount,
        position = position,
        label = label,
        icon = "entity/" .. cluster.resource_name,
        search_display_name = search_display_name,
        occupied_marker = occupied_marker,
        secondary_text = ResourceLogic.secondary_text(
          surface_token,
          position,
          distance_to(player_location, cluster.surface_index, position)
        ),
        search_display_ranges = match.display_ranges,
        search_score = match.score,
      })
    end
  end
  table.sort(candidates, function(a, b)
    if a.amount ~= b.amount then
      return a.amount > b.amount
    end
    return a.id < b.id
  end)
  return candidates
end

return ResourceLogic
