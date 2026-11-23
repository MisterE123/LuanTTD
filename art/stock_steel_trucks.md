# Stock Balogh, Uhl and Kelling Steel Trucks

Three originals for OpenTTD 16.0-RC1's temperate steel truck family. The Balogh has a long independent rounded hood, an upright cab, period lamps and a small teal cabin. The Uhl has a more compact mid-era square cabin, upright grille bars, larger glass and a stronger headboard. The Kelling is a modern long swept cobalt cab-over with twin rear axles, distinct low headlamps and mature flatbed (not the earlier rail locomotive with the same make).

Every vehicle has an empty timber-deck version and a loaded version with two actual steel coils; the coils have visible concave open cores, concentric winding layers, metallic bands, deck chocks and four real through-eye anchoring strap paths per coil. The payload meshes do not insert or move any native chassis, bed, chock or wheel triangles. Art follows silhouette cues from OpenGFX; all geometry and every palette color were authored here.

| ID | Name | ROV row / image | Stock base / loaded sprite | Capacity / first full image |
| --- | --- | --- | --- | --- |
| 150 | Balogh Steel Truck | 34 / 9 | 3356 / 3404 | 15 / 7 |
| 151 | Uhl Steel Truck | 35 / 26 | 3164 / 3212 | 18 / 9 |
| 152 | Kelling Steel Truck | 36 / 43 | 3548 / 3596 | 20 / 10 |

Use native `.42` visual size, nose −Z and tire treads Y=0. Use `bl_stock_balogh_steel_truck`, `bl_stock_uhl_steel_truck` and `bl_stock_kelling_steel_truck` as the fixed empty mesh stems, append `_loaded.obj` only at the exact integer half-capacity stock threshold, and use a shared-by-variant `_atlas.png` for each vehicle. Editable Blender scenes use matching stems without the `bl_` prefix.

Build and verify:

```sh
blender -b -t 3 --python-exit-code 1 --python tools/build_stock_steel_trucks_art.py
python tests/stock_steel_trucks_art.py
```

Set `LATE_FREIGHT_REVIEW` to an existing directory for optional empty-front/loaded-rear art stills. `STEEL_TRUCK_STEM` rebuilds one item. Isolated runs can pass `LUANTTD_HELPERS` and `LUANTTD_BASE` to the repository’s tools/root, respectively. The builder reuses the existing low-level geometry and Blender export utility `build_stock_late_freight_art.py`.

All six produced meshes passed the same 6,760 exact source freight stop/obstacle fence sweeps and 12,784 native road corner positions: 117,264 checks. The .42 extents W/H/L are .2495/.2608/.6756 (Balogh), .2575/.2650/.6749 (Uhl), .2575/.2869/.6760 (Kelling). The two open coils on each loaded model passed separate manifold/ray checks. This is art verification, not paid cargo integration.

## Sources

- [OpenTTD 16.0-RC1 engines](https://github.com/OpenTTD/OpenTTD/blob/16.0-RC1/src/table/engines.h), blob `1f71919c2399ebe7053cd78a306a96fb59e25def`.
- [OpenTTD 16.0-RC1 loaded image selection](https://github.com/OpenTTD/OpenTTD/blob/16.0-RC1/src/roadveh_cmd.cpp#L48-L145), blob `30b5ca437f407046b9ccb9a5dcb8824942c925c8`.
- [OpenGFX sprite layout](https://github.com/OpenTTD/OpenGFX/blob/master/sprites/base/base-3092-road-vehicles.pnml), blob `ff7de7f3ea587fc554fc9331399bc35333607364`; [OpenGFX flatbed silhouette sheet](https://github.com/OpenTTD/OpenGFX/blob/master/sprites/png/roadvehicles/flatbeds.png), blob `ae7eb40f9623b05354f0698b60af4530ad7aea0d`. File consulted visually only; no sprite pixels or model assets from upstream are included.
