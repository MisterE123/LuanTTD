# Stock Steel Mill (layout 1)

Original 14-cell artwork for the alternate Temperate Steel Mill in
[OpenTTD 16.0-RC1](https://github.com/OpenTTD/OpenTTD/blob/07b339c0aaeb0a87be9490b2f1c3f17c6b00b837/src/table/build_industry.h#L370-L385).
It has two adjacent 2×2 process units (GFX 52/53/54/55), a row of stock
yards, and two added southern yard cells. The southwestern and
southeastern corner cells of the bounding rectangle remain untouched.

The paired blast-furnace assemblies, rolling houses, crane components,
roof monitors, and under-house transfers are the original layout-zero
component kit. Furnace groups are nudged as rigid assemblies slightly
south so the north site boundary does not sever their circular
platforms. The left GFX56/57 yard pair still uses the exact original
mesh body, including its siding seam. The new adjacency provides
a continuous service alley, rerouted ore-feed belts, relocated hot-air
stoves and steel handling stacks in the two southern yards.

The editable Blender master contains independently named groups and
a survey camera. The 14 runtime sections use the existing industry
palette and ordinary (x*2, grade+1, z*2) native anchors. The stock shade
atlas is reused byte-for-byte under the alternate style name. No
OpenTTD sprite data is distributed.

Build, inspect and verify:

    STOCK_STEEL_L1_PREVIEW=/tmp/steel-l1.png blender -b -t 3 --python-exit-code 1 --python tools/build_stock_steel_mill_layout_1_art.py
    python3 tests/stock_steel_mill_layout_1_art.py --upstream-layout /path/to/src/table/build_industry.h
    blender -b -t 3 --python-exit-code 1 --python tools/build_stock_steel_mill_layout_1_art.py -- --check
