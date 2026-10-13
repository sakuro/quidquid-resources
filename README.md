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

A patch is listed once any one of its chunks is charted, with its full extent and total amount.

When the mod is added to an existing save, a background scan fills in the list over the following minutes. Until then, an empty or partial result does not mean the resource isn't there. A chat message is posted when the scan finishes.

A patch that already has a mining drill working it is marked on the same line, right after its name and amount.

The remaining amount is updated as resource entities are exhausted, so it lags behind the drills. For infinite resources such as crude oil, it can stay at the value from when the patch was charted.

The muted line under the name carries the patch's surface and the coordinates a left click lands on, plus the distance from the character when the patch is on the same surface.

Pinning a patch uses the game's own map-pin system, which keeps the amount up to date, so the list is for choosing a patch and the pin is for watching one.

## For other mods

See [EXTENDING.md](https://github.com/sakuro/quidquid-resources/blob/main/EXTENDING.md) for the fields a resource candidate carries.
