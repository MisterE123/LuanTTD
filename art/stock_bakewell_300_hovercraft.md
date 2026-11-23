# Bakewell 300 Hovercraft #208

Original editable Blender passenger hovercraft for OpenTTD 16.0-RC1. It uses the stock visual hierarchy of a broad dark skirt, low white glazed deck and red outboard frame accents, without reusing any stock sprite pixels or models. Independent elements include a sealed rubber plenum, individually folded skirt fingers and seam stitching, amphibious underskirt skid strips, separate aluminum upper hull, a paneled passenger cabin with real windows, bow lights, passenger door/ramp fittings and two true annular stern thrust ducts. Each duct houses a swept five-bladed propeller on its own hub and three inlet support stators. Forward outrigger models house lift-air intake louvers, not a painted fan panel.

- `art/stock_bakewell_300_hovercraft.blend`: editable skirt/hull, cabin and propulsion collections.
- `mods/luanttd_core/models/bl_stock_bakewell_300_hovercraft.obj`: original native mesh.
- `mods/luanttd_core/textures/bl_stock_bakewell_300_hovercraft_atlas.png`: original 64-cell 512×8 palette.
- `tools/build_stock_hovercraft_art.py` and `tests/stock_hovercraft_art.py`: Blender generator and structural verification.

Use native scale **1.0**, local **−Z** bow and **Y=0** design waterline. Visible bounds W/H/L are .7595/.7192/1.7265 nodes. Engine #208 is a 100-passenger ship, SVI row 4, sprite index 3 mapping to 3693 plus direction. It has one mesh across all fill states. This is art only and does not enable land operations, alter hydrodynamics, or mount service.

## Rebuild and verify

```sh
blender -b -t 3 --python-exit-code 1 --python tools/build_stock_hovercraft_art.py
python tests/stock_hovercraft_art.py
```

For optional Blender bow, stern and underbody renders set `HOVERCRAFT_REVIEW` to an existing directory. Isolated builds use `LUANTTD_HELPERS` pointing at the game’s `tools` directory and `LUANTTD_BASE` at the game checkout root for tests. Test optional `--engines`, `--ship-cmd` and `--opengfx` inputs assert the exact source identity.

The 10,364-triangle model passed closed-shell checks for the independent load deck/skirt and both ducts, real open-duct bore tests, and 1,446 real existing geometry probes spanning both depot axes, open gates, all four lock directions, every lock segment and four lift phases. Worst per-yaw adjacent berth clearance is .1281 and the closed mitre gate clearance is .0833 nodes. This is art clearance proof, not evidence of world mounting or a live paid route.

## Provenance

- [OpenTTD 16.0-RC1 engines](https://github.com/OpenTTD/OpenTTD/blob/16.0-RC1/src/table/engines.h), exact blob `1f71919c2399ebe7053cd78a306a96fb59e25def`.
- [OpenTTD 16.0-RC1 ship direction-only image dispatch](https://github.com/OpenTTD/OpenTTD/blob/16.0-RC1/src/ship_cmd.cpp#L67-L154), blob `b468042e8e3f77282cb3735e239abd5ad0394b13`.
- [OpenGFX ship slot mapping](https://github.com/OpenTTD/OpenGFX/blob/master/sprites/base/base-3668-ships.pnml), blob `13d590c94c46f12f2697bf244feabbfa206023e0`, and [stock silhouettes](https://github.com/OpenTTD/OpenGFX/blob/master/sprites/png/ships/ships01.png), blob `91aacf94a5ce3765301b5c250db2c897e927c3f2`. Only silhouette/colors informed original geometry and palette; no reference images in the build or handoff.
