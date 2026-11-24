# Temperate rooftop heliport

The original LuanTTD mesh represents OpenTTD 16.0-RC1 `APT_HELIPORT`: a stepped
office tower, blue-gray glass and bronze shade bands, public ground entrance,
and a single marked roof pad. It is neither the Oil Rig nor an aircraft depot.
The `station_land.h` column for `SPR_HELIPORT` and the heliport FTA both
use a vertical clearance of 60 OpenTTD pixel units. The editable Blender
model and native mesh retain its scale instead of fitting an entire tower
into a single block resembling a low hangar. The OpenGFX 7.1 implementation
of sprite 2633 was used only as a silhouette/proportions reference. No sprite,
icon, palette, texture, or mesh is reused.

- `art/heliport.blend` has ten named components, named palette materials, and
  an orthographic review camera.
- `bl_heliport_0_0.obj` fits the one 2-by-2-node tile; placement is at
  `(tile_x*2, ground_y+1, tile_z*2)`. The walk-in entrance sits at local
  Y=-0.5. The roof deck is at local Y=7.0, exactly 60/8 nodes above the
  original grass surface. The native pad is centered at stock terminal
  coordinates (5,9) after the standard stock-to-Luanti conversion.
- `bl_heliport_atlas.png` is compact and isolated from the land-airport
  palettes; `bl_dispatch_heliport.png` is an independent 32 px alpha icon
  with the stepped tower silhouette and a marked landing ring.

Rebuild checked-in runtime media with `python3 tools/build_heliport_art.py`.
Check byte reproducibility and the tile, deck, window, ring and icon
regressions with `python3 tests/heliport_art.py`.

Refresh the editable source and write a visual proof:

```sh
blender -b -t 3 --python-exit-code 1 --python tools/build_heliport_art.py -- \
  --blend --preview /tmp/luanttd-heliport-preview.png
```
