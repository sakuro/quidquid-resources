# Quidquid: Resources

[![Downloads](https://img.shields.io/badge/dynamic/json.svg?label=Downloads&url=https%3A%2F%2Fmods.factorio.com%2Fapi%2Fmods%2Fquidquid-resources&query=%24.downloads_count)](https://mods.factorio.com/mod/quidquid-resources)

Adds resource-patch search to the [Quidquid](https://mods.factorio.com/mod/quidquid)
palette. It moved out of Quidquid in 0.10.0. Type `resource ` or `R ` (uppercase,
since lowercase `r` is taken by recipes) to search resource patches.

Search for resource patches your force has charted.

| Key | Action |
| --- | --- |
| Left click | Open in remote view |
| `Ctrl/Cmd` + left click | Pin the patch |
| `Alt` + left click | Open in Factoriopedia |

A patch is every chunk holding a resource whose tiles touch the same
resource's tiles in a neighbouring chunk, diagonals included. Resources
larger than one tile — crude oil, sulfuric acid geysers, fluorine vents,
lithium brine — are scattered by nature, so for them sharing a chunk border
is enough. Two patches whose edges fall in the same chunk still read as one.
This merging never undoes itself: a patch never splits once found, so
mining out or deleting the chunks in the middle leaves the rest as a single
patch, not two.

A patch is listed once any one of its chunks is charted, checked per force at
search time — it then reports its full extent and total amount, including
whatever part still sits under fog of war. Space platforms are skipped; they
hold no resources.

When the mod is added to an existing save, a background scan works through
the world a few chunks per tick, so the list fills in gradually over the
following minutes rather than all at once — an empty or partial result
during that window does not mean the resource isn't there. Quidquid: Resources
says so in chat once that scan finishes, so there is no need to guess when the
list can be trusted.

A patch that already has a mining drill working it is marked right after its
name and amount, on the same line; an unoccupied patch shows no such marker.
Any force's drill counts, not just your own — the same way Factorio's own
map search treats a patch.

Each result's name is followed by its remaining amount, taken from a cache
rather than counted afresh. A chunk is re-scanned when one of its entities is
exhausted to nothing, so a finite patch's figure falls in steps as it is
mined, lagging behind the drills rather than tracking them. Infinite
resources — crude oil, sulfuric acid geysers — raise that event at most once,
as they decay toward their minimum yield, so an oil field's figure can sit at
its chart-time value indefinitely.

Pin a patch and Factorio tracks it properly: pinning uses the game's own
map-pin system, and the pin holds the patch's own entities and recomputes the
amount continuously. So the list is for choosing a patch and the pin is for
watching one. The pin is per-player, and is dismissed from Factorio's own UI
rather than by Quidquid.

## For other mods

A resource candidate (`type = "resource"`) carries, besides Quidquid's standard
candidate fields:

| Field | Meaning |
| --- | --- |
| `resource_name` | The resource entity prototype's name |
| `surface_index` | The surface the patch is on |
| `position` | A MapPosition inside the patch's richest chunk |

Other fields are internal and may change.
