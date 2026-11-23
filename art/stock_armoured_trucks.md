# Stock Balogh, Uhl and Foster Armoured Trucks

Three original Blender models for the OpenTTD 16.0-RC1 armoured fleet. The early Balogh has a separate rounded bonnet, a short upright blue cab, small circular lights and a low round-edged box. Uhl has a midcentury full frontal blue cab, boxed silver grille and a squared load compartment. Foster uses a deeper swept cab, modern flat lamps and an extended rear tandem chassis. All have independent sealed wrapped coachwork, real outer lights, closed door surfaces and original geometric trim. Their stock invisible cargo does not create exposed boxes or alternate external shells.

| Engine | ROV row / image / sprite | Capacity | Native W × H × L |
| --- | --- | ---: | --- |
| #153 Balogh Armoured Truck | 37 / 10 / 3372 | 12 | .2491 × .2764 × .6756 |
| #154 Uhl Armoured Truck | 38 / 27 / 3180 | 15 | .2570 × .2789 × .6804 |
| #155 Foster Armoured Truck | 39 / 44 / 3564 | 16 | .2570 × .2894 × .6829 |

Original cargo climate mapping is Valuables/Gold/Diamonds in Temperate/Sub-Arctic/Sub-Tropical; the initial Temperate integration uses Valuables. All stock full image offsets are zero. In native Luanti use visual scale **.42**, vehicle nose **−Z**, wheel treads **Y=0**. Atlas files (original 64-cell palettes) and editable Blender filenames share each base mesh stem: `stock_balogh_armoured_truck`, `stock_uhl_armoured_truck` and `stock_foster_armoured_truck`. Meshes and PNGs in the mod use the existing `bl_` prefix.

## Verify

```sh
blender -b -t 3 --python-exit-code 1 --python tools/build_stock_armoured_trucks_art.py
python tests/stock_armoured_trucks_art.py
BAYLINE_NATIVE_TOOLS=/path/to/toolroot tests/stock_armoured_trucks_native.sh
```

Set `LATE_FREIGHT_REVIEW` to an existing directory for optional Blender renders. Isolated verification accepts `LUANTTD_HELPERS` pointing at the repo’s tools and `LUANTTD_BASE` pointing at the checkout. Optional `--engines`, `--roadveh` and `--opengfx` check exact sources. The authoring tool uses existing low-level helper `build_stock_late_freight_art.py`.

All three exact production meshes passed manifold shell, tread height, lane/turn tests, 6,760 exact freight stop/fence sweeps and 12,784 road-corner poses each. Actual mesh and texture rendering was checked in a native Lua/graphics fixture with a disposable local game and two road-view screenshots, not a gameplay or purchasing fixture. Triangles: Balogh 7,044, Uhl 6,408, Foster 7,964.

## Source and license

- [OpenTTD 16.0-RC1 engines table](https://github.com/OpenTTD/OpenTTD/blob/16.0-RC1/src/table/engines.h) blob `1f71919c2399ebe7053cd78a306a96fb59e25def`.
- [OpenTTD 16.0-RC1 road sprite/full-adder tables](https://github.com/OpenTTD/OpenTTD/blob/16.0-RC1/src/roadveh_cmd.cpp#L48-L145), blob `30b5ca437f407046b9ccb9a5dcb8824942c925c8`.
- [OpenGFX slot mapping](https://github.com/OpenTTD/OpenGFX/blob/master/sprites/base/base-3092-road-vehicles.pnml) blob `ff7de7f3ea587fc554fc9331399bc35333607364`; [original stock silhouette raster](https://github.com/OpenTTD/OpenGFX/blob/master/sprites/png/roadvehicles/vehiclesroad01.png) blob `115510b811f8b475abac68df299c17369dfd1706`. OpenGFX is [GPL version 2](https://github.com/OpenTTD/OpenGFX/blob/master/README.md#50-license). No copied raster or model files are embedded or packaged, and all palettes and geometry are independently authored.
