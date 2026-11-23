# Late freight road vehicles

Three original editable Blender models for the OpenTTD 16.0-RC1 stock cargo fleet, reconstructed from the staged designs after the workspace reset. Body and cargo geometry are independent collections; the OBJ files contain the production triangles and an original shared 64-colour, 1,024×16 palette, saved under each vehicle's native atlas filename. No upstream sprites or logo assets are embedded.

| Stock engine | Art stem | Road index | Base sprite | Loaded visual |
| --- | --- | ---: | ---: | --- |
| #146 Moreland Wood Truck | `stock_moreland_wood_truck` | 41 | 3540 | `_loaded.obj` at 12/24 cargo |
| #143 Goss Grain Truck | `stock_goss_grain_truck` | 40 | 3532 | `_loaded.obj` at 15/30 cargo |
| #137 Foster Livestock Van | `stock_foster_livestock_van` | 38 | 3508 | No alternate: stock loaded offset is zero |

The Moreland is a modern cobalt tandem rigid stake truck with actual sawn, tapered logs, 20 in two strapped packs and four legally credible stake pairs (not a real-world safety claim). The Goss keeps the OpenGFX compact cab-over and open silver tipper hopper; its loaded version is a true closed gold grain mesh with separate modeled kernels. The Foster is a lightly ribbed dark blue cattle enclosure over a swept cab: 24 watertight slats split its six physical slot bays into two levels on both sides, plus visible pen rails and separate modelled rear hatch hinges and locks.

Place all three with visual scale `.42`, nominal world local nose −Z and tire contact Y=0. Empty and loaded variants of each model have identical other faces and overall bounds. This is asset-only; the world separately controls access, load, economy and movement.

## Build and tests

```sh
blender -b -t 3 --python-exit-code 1 --python tools/build_stock_late_freight_art.py
python tests/stock_late_freight_art.py
```

For review JPEGs, set `LATE_FREIGHT_REVIEW` to an existing directory; for an isolated copy, `LUANTTD_HELPERS` should point at the main checkout’s `tools` and `LUANTTD_BASE` at the checkout root. QA ran 6,760 exact freight stop poses, 12,784 stock-corner poses, native lane/turn tests and real tread contacts for each of five mesh files. It also checks separate timber, sealed grain geometry, Foster side airflow rays and slat watertightness. Two optional exact upstream inputs, `--engines` and `--roadveh`, assert stock identity and sprite loading behavior.

## Provenance

- [OpenTTD 16.0-RC1 engines/data](https://github.com/OpenTTD/OpenTTD/blob/16.0-RC1/src/table/engines.h), blob `1f71919c2399ebe7053cd78a306a96fb59e25def`.
- [OpenTTD 16.0-RC1 sprites](https://github.com/OpenTTD/OpenTTD/blob/16.0-RC1/src/roadveh_cmd.cpp#L48-L145), blob `30b5ca437f407046b9ccb9a5dcb8824942c925c8`.
- [OpenGFX road mapping](https://github.com/OpenTTD/OpenGFX/blob/master/sprites/base/base-3092-road-vehicles.pnml), [flatbeds reference](https://github.com/OpenTTD/OpenGFX/blob/master/sprites/png/roadvehicles/flatbeds.png), [vehicle silhouettes](https://github.com/OpenTTD/OpenGFX/blob/master/sprites/png/roadvehicles/vehiclesroad01.png). Moreland empty and loaded at sprite rows Y=360/424, Goss empty and loaded at Y=584/648, and Foster at Y=552. Only silhouettes and cargo identity informed artist-authored Blender shape and independent geometry.
