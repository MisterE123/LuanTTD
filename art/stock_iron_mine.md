# Stock Iron Ore Mine (industry 18)

An original Temperate site for the single [OpenTTD 16.0-RC1 iron-mine layout](https://github.com/OpenTTD/OpenTTD/blob/07b339c0aaeb0a87be9490b2f1c3f17c6b00b837/src/table/build_industry.h#L602-L623). It occupies exactly 16 cells, from GFX 100 through 115. The west cut banks, winding headframe with two separate spoked sheaves, jaw-crusher building, ore conveyors and two gravity-loading bins are geometry. The private siding presents the load yard; it is not buildable or connected railway track. No original game sprite bytes are distributed.

`stock_iron_mine.blend` contains the editable whole site. Runtime clips each piece to a logical 2×2-native-node square, with the same native grade+1 NW anchor and OBJ winding as the stock refinery. Horizontal ground is physically flush with the stock level foundation. Terraced relief rises from that datum rather than modifying terrain. The stock construction/leveling rules belong to the industry simulation.

Build and validate:

```sh
STOCK_METAL_SITE=iron_mine blender -b -t 2 --python-exit-code 1 --python tools/build_stock_metal_industry_art.py
python3 tests/stock_metal_industry_art.py --site iron_mine
blender -b -t 2 --python-exit-code 1 --python tests/stock_metal_industry_art.py -- --site iron_mine
```

The Blender audit opens the saved source and verifies full surface preservation over all 16 exact partitions, including the cross-tile conveyor and ore loading rail.
