# Stock MPS and CS-Inc. Oil Tankers

Two original Blender vessels for OpenTTD 16.0-RC1. The shared stock directional sprite shows a long blue oil hull, an open tank/pipe deck and white aft bridge. The original game uses the same eight directional frames for both tankers; the differing details here are artistic period reinterpretation, not a claim they have different stock sprites. No sprite pixel, logos, or third-party geometry are embedded.

| Engine ID | Stock vessel | Ship table row / image | Oil | Native units W/H/L |
| --- | --- | --- | ---: | --- |
| 204 | MPS Oil Tanker | 0 / 1 | 220 | .6131 / .9501 / 1.7469 |
| 205 | CS-Inc. Oil Tanker | 1 / 1 | 350 | .6851 / 1.0013 / 1.8391 |

The MPS has a finer blue hull, cream steam-era wheelhouse with a tall red funnel and separate work skiff. The larger CS-Inc has a fuller hull, tiered aft bridge, working-shape radar and twin exhausts, loading portal and collapsed delivery jib. Each has a sealed hull, original tank coamings, independently modeled oil pipes and capped bilateral manifold, vent pipes, navigation lights, railings, aft bronze screw and rudder. The native dark boot stripe straddles the design waterline.

- Meshes: `mods/luanttd_core/models/bl_stock_mps_oil_tanker.obj` and `bl_stock_cs_inc_oil_tanker.obj`.
- Atlases: `mods/luanttd_core/textures/bl_stock_mps_oil_tanker_atlas.png` and `bl_stock_cs_inc_oil_tanker_atlas.png`.
- Editable scenes `art/stock_mps_oil_tanker.blend` and `art/stock_cs_inc_oil_tanker.blend` span four semantic collections each.
- Both use native visual scale **1.0**, local **−Z** bow on export and **Y=0** design waterline. No alternate mesh for loading, since stock ship sprite dispatch never switches on cargo fill.

## Rebuild and verify

```sh
blender -b -t 3 --python-exit-code 1 --python tools/build_stock_oil_ships_art.py
python tests/stock_oil_ships_art.py
```

Set `OIL_SHIP_REVIEW` to an existing directory for Blender bow and deck proof renders. For an isolated art stage set `LUANTTD_HELPERS` to the main checkout tools and `LUANTTD_BASE` to its root. The tests optionally accept `--engines`, `--ship-cmd` and `--opengfx` inputs to pin the exact sprite identity.

Each actual mesh passed 1,474 geometry probes across both depot directions, both sections, open lock gates, all four lock orientations, three lock segments and four height phases. The tightest model (#205) clears adjacent berth pier geometry at all yaws by at least .0780 nodes and the closed lock gates by at least .0313. The old and new scenes respectively use 10,304 and 11,556 production triangles. This demonstrates presentation clearance with current geometry, not purchase, cargo simulation, or a native client playtest.

## Exact sources

- [OpenTTD 16.0-RC1 ship engine table](https://github.com/OpenTTD/OpenTTD/blob/16.0-RC1/src/table/engines.h), blob `1f71919c2399ebe7053cd78a306a96fb59e25def`.
- [OpenTTD 16.0-RC1 directional image selection](https://github.com/OpenTTD/OpenTTD/blob/16.0-RC1/src/ship_cmd.cpp#L67-L154), blob `b468042e8e3f77282cb3735e239abd5ad0394b13`: image slot 1 selects base 3669.
- [OpenGFX stock hull PNG](https://github.com/OpenTTD/OpenGFX/blob/master/sprites/png/ships/ships01.png) (reference blob `91aacf94a5ce3765301b5c250db2c897e927c3f2`) and [sprite coordinates for 3669–3676](https://github.com/OpenTTD/OpenGFX/blob/master/sprites/base/base-3668-ships.pnml), blob `13d590c94c46f12f2697bf244feabbfa206023e0`.
