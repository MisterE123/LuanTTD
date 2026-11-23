# Stock Steel Mill (industry 8)

An original Temperate site for [OpenTTD 16.0-RC1 Steel Mill layout zero](https://github.com/OpenTTD/OpenTTD/blob/07b339c0aaeb0a87be9490b2f1c3f17c6b00b837/src/table/build_industry.h#L355-L389). It covers its exact 12 cells: GFX 52–55 form the compact process house and furnaces, while GFX 56 and 57 carry the material yards. The second stock layout is not included.

Visible equipment includes two separately shaped blast furnaces, oxygen preheat stoves, hearth channels, a high roof monitor, bridging intake conveyor, rolling-shop hoist and stacks of finished steel. Internal rails are presentation, not player-operated track. No stock game sprite pixels are distributed.

`stock_steel_mill.blend` contains the editable whole site. Runtime clips each piece against the exact 2×2-native-node footprint, using the same NW grade+1 node anchor as the refinery. A flat shared foundation is required for the clipped pieces to join; the gameplay adapter owns the leveling check.

Build and validate:

```sh
STOCK_METAL_SITE=steel_mill blender -b -t 2 --python-exit-code 1 --python tools/build_stock_metal_industry_art.py
python3 tests/stock_metal_industry_art.py --site steel_mill
blender -b -t 2 --python-exit-code 1 --python tests/stock_metal_industry_art.py -- --site steel_mill
```

The Blender audit opens the saved source and measures preservation of the process roofs, intake, rails and 12 exact tile surfaces.
