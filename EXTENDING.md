# Extending Quidquid: Resources

A resource candidate (`type = "resource"`) carries, besides Quidquid's standard candidate fields:

| Field | Meaning |
| --- | --- |
| `resource_name` | The resource entity prototype's name |
| `surface_index` | The surface the patch is on |
| `position` | A MapPosition inside the patch's richest chunk |

Other fields are internal and may change.
