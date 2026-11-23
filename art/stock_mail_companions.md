# Stock Mail Trucks #126 and #128

Two original editable Blender models for OpenTTD 16.0-RC1's early and late temperate postal fleet slots, also present in the original arctic/subtropical roster. The early MPS has a period deep red livery, long independently shaped bonnet, upright divided windscreens, exposed wheel arches, round lamps and cream lettering. The late Perry has a cobalt swept cab, distinct covered cargo body, charcoal roof belts and modern delivery steps. All meshes and palette colors are original, with no embedded OpenGFX pixels or actual postal trademarks.

| Stock engine | Road row / image | Artwork stem | Mail cap / speed field | Stock sprite |
| --- | --- | --- | --- | --- |
| #126 MPS Mail Truck | 10 / 2 | `stock_mps_mail_truck` | 22 / 96 | 3300 |
| #128 Perry Mail Truck | 12 / 36 | `stock_perry_mail_truck` | 30 / 224 | 3492 |

The stock full image offsets for both are zero. Both use one mesh for all fill states. The renderer must not invent a shell swap or physical cargo. Editor/atlas/mesh files use the matching stems in `art/` and `mods/luanttd_core/{models,textures}` respectively.

Use `.42` native visual scale, nose −Z, tire contact Y=0. At .42 the MPS spans .2512 W × .2671 H × .6529 L nodes in 4,856 faces; the Perry spans .2575 W × .2839 H × .6829 L in 6,016 faces. Each passed all 6,760 stock freight-stop poses and 12,784 source road corner samples. These tests are structural and apply the existing native road fixtures to the actual exported meshes. Blender review stills establish art appearance, not game integration.

## Regenerate and test

```sh
blender -b -t 3 --python-exit-code 1 --python tools/build_stock_mail_companions_art.py
python tests/stock_mail_companions_art.py
```

The builder and tests use existing helpers `build_stock_late_freight_art.py` and `stock_late_freight_art.py`. For an isolated run set `LUANTTD_HELPERS` to project tools and `LUANTTD_BASE` to its root. `LATE_FREIGHT_REVIEW` enables front and rear Blender proof stills. Tests accept optional `--engines`, `--roadveh`, and `--opengfx` exact source inputs for identity checks.

- [OpenTTD 16.0-RC1 engine table](https://github.com/OpenTTD/OpenTTD/blob/16.0-RC1/src/table/engines.h): `1f71919c2399ebe7053cd78a306a96fb59e25def`.
- [OpenTTD 16.0-RC1 road sprite and full adder tables](https://github.com/OpenTTD/OpenTTD/blob/16.0-RC1/src/roadveh_cmd.cpp#L48-L145): `30b5ca437f407046b9ccb9a5dcb8824942c925c8`.
- [OpenGFX first/third mail stock mappings](https://github.com/OpenTTD/OpenGFX/blob/master/sprites/base/base-3092-road-vehicles.pnml): `ff7de7f3ea587fc554fc9331399bc35333607364`; [body/silhouette reference](https://github.com/OpenTTD/OpenGFX/blob/master/sprites/png/roadvehicles/vehiclesroad01.png) at X=626 and Y=264/520, blob `115510b811f8b475abac68df299c17369dfd1706`.
