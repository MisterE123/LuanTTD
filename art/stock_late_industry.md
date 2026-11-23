# Stock late industrial road vehicles

Three original native road vehicles with editable Blender scenes, generated meshes and attributed geometry-based designs. At the stock .42 presentation scale, local −Z is forward and wheel treads touch Y=0. Each asset is a rigid road vehicle with chassis clearance verified in both lanes, at turns, and through all simulated freight stops. This package adds no runtime availability or altered cargo rules.

| RC1 engine | Road row / image | Vehicle asset stem | Cargo | Visual load |
| --- | --- | --- | ---: | --- |
| #140 Goss Goods Truck | 24 / 39 | `stock_goss_goods_truck` | 18 | No stock alternate |
| #125 DW Coal Truck | 9 / 35 | `stock_dw_coal_truck` | 28 | Load mesh at 14, base sprite 3484 + 88 |
| #134 Perry Oil Tanker | 18 / 37 | `stock_perry_oil_tanker` | 27 | No stock alternate |

The closed Goss has a blue ribbed box body, paired rear door leaves, hinges/rods and an upright folded loading deck. The DW has a grey tipping coal hopper, tandem rear wheel chassis and its own rock-lump geometry in a sealed bulk volume; none of its empty-body faces or bounds move when loaded. The Perry has a sealed blue steel pressure barrel, domed ends, tank support straps, a service valve cabinet, safe-in-travel access ladder, and raised refilling hatches. All are original mesh work, not retextured copies or source pixels.

- Three editables under `art/stock_*.blend`.
- Four OBJ files under `mods/luanttd_core/models` (one additional loaded coal mesh).
- An atlas per vehicle under `mods/luanttd_core/textures`; original 1,024×16, 64 sampled colors.
- Build utility `tools/build_stock_late_industry_art.py` uses low-level geometry and Blender packaging from `tools/build_stock_late_freight_art.py`. Verification `tests/stock_late_industry_art.py` likewise uses the existing `tests/stock_late_freight_art.py` geometry/road helpers.

```sh
blender -b -t 3 --python-exit-code 1 --python tools/build_stock_late_industry_art.py
python tests/stock_late_industry_art.py
```

Optional `LATE_FREIGHT_REVIEW` points at a directory for Blender front/rear art QA. For an isolated run, `LUANTTD_HELPERS` points at the project tools and `LUANTTD_BASE` points at the checkout. The tests accept optional `--engines`, `--roadveh` and `--opengfx` inputs to check upstream slot identity. At scale .42 dimensions (W/H/L) are Goss .2570/.2885/.6861, DW .2570/.2583/.6781 and Perry .2570/.2894/.6781. All four mesh variants passed 6,760 exact freight and 12,784 exact stock-corner poses each.

## References

- [OpenTTD 16.0-RC1 engine table](https://github.com/OpenTTD/OpenTTD/blob/16.0-RC1/src/table/engines.h), blob `1f71919c2399ebe7053cd78a306a96fb59e25def`. Exact stock naming is Goss Goods / DW Coal / Perry Oil; #152 is Kelling Steel and not in this batch.
- [OpenTTD 16.0-RC1 road sprite table and full adder](https://github.com/OpenTTD/OpenTTD/blob/16.0-RC1/src/roadveh_cmd.cpp#L48-L145), blob `30b5ca437f407046b9ccb9a5dcb8824942c925c8`.
- [OpenGFX slot mapping](https://github.com/OpenTTD/OpenGFX/blob/master/sprites/base/base-3092-road-vehicles.pnml), blob `ff7de7f3ea587fc554fc9331399bc35333607364`, and [original stock silhouette reference](https://github.com/OpenTTD/OpenGFX/blob/master/sprites/png/roadvehicles/vehiclesroad01.png), blob `115510b811f8b475abac68df299c17369dfd1706`. Stock cabin/body cues are independently modeled; no sprites are supplied in the package.
