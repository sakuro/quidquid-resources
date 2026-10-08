# Quidquid: Resources

[![Downloads](https://img.shields.io/badge/dynamic/json.svg?label=Downloads&url=https%3A%2F%2Fmods.factorio.com%2Fapi%2Fmods%2Fquidquid-resources&query=%24.downloads_count)](https://mods.factorio.com/mod/quidquid-resources)

Adds resource-patch search to the [Quidquid](https://mods.factorio.com/mod/quidquid) palette.

By default, resource patches appear in the palette's search along with everything else. Type `resource ` or `R ` (uppercase, since lowercase `r` is taken by recipes) to restrict the search to them. Turning off "Include resources in the default search" leaves them to the restricted search only.

Search for resource patches your force has charted.

| Key | Action |
| --- | --- |
| Left click | Open in remote view |
| `Ctrl/Cmd` + left click | Pin the patch |
| `Alt` + left click | Open in Factoriopedia |

A patch is every chunk holding a resource whose tiles touch the same resource's tiles in a neighbouring chunk, diagonals included. Resources larger than one tile (crude oil, sulfuric acid geysers, fluorine vents, lithium brine) are scattered by nature, so for them sharing a chunk border is enough. Two patches whose edges fall in the same chunk still read as one.
Once found, a patch never splits: mining out or deleting the chunks in the middle leaves the rest as a single patch.

A patch is listed once any one of its chunks is charted, checked per force at search time. It then reports its full extent and total amount, including any part still under fog of war. Space platforms are skipped, since they hold no resources.

When the mod is added to an existing save, a background scan works through the world a few chunks per tick, so the list fills in over the following minutes. Until then, an empty or partial result does not mean the resource isn't there. Quidquid: Resources posts a chat message when the scan finishes.

A patch that already has a mining drill working it is marked on the same line, right after its name and amount. A drill of any force counts, as in Factorio's own map search.

Each result's name is followed by its remaining amount, read from a cache. A chunk is re-scanned when one of its entities is exhausted, so a finite patch's figure drops in steps as it is mined and lags behind the drills. Infinite resources such as crude oil and sulfuric acid geysers raise that event at most once, as they decay toward their minimum yield, so an oil field's figure can stay at its chart-time value indefinitely.

Pinning a patch uses the game's own map-pin system. The pin holds the patch's entities and recomputes the amount continuously, so the list is for choosing a patch and the pin is for watching one. Pins are per player and are dismissed from Factorio's own UI, not from Quidquid.

## For other mods

A resource candidate (`type = "resource"`) carries, besides Quidquid's standard candidate fields:

| Field | Meaning |
| --- | --- |
| `resource_name` | The resource entity prototype's name |
| `surface_index` | The surface the patch is on |
| `position` | A MapPosition inside the patch's richest chunk |

Other fields are internal and may change.
