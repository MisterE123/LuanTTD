# Stock Temperate industry footprints

All 23 footprints in the ten-family land-industry generator now have native media and are eligible for normal generation. This update mounts both remaining Farm layouts, the second Factory, second managed Forest, second Oil Wells, and second Oil Refinery. The stock Oil Rig and Bank retain their dedicated placement paths.

The [ordered RC1 comparison](../tests/industry_layout_catalog_rc1.py) checks position and graphics ID against the pinned OpenTTD header. [Placement and asset tests](../tests/industry_farm_oil_layout_ingress.lua) check the actual occupied cells, leave the source gaps untouched, and require every variant's media before the shared generator treats it as available. The [graphical worker replay](../tests/industry_alternate_native.sh) uses a generated Temperate world at seed 11, not a collection of hand-placed samples.

* Farms have new barns, machinery sheds, silo banks, garden rows and fenced paddocks. Runtime shares six self-contained original modules, and the two editable scenes show the exact arrangements: [layout 1](../art/stock_temperate_farm_l1.blend) and [layout 2](../art/stock_temperate_farm_l2.blend). Nearby alternate pens use the same capped, viewport-local livestock animation as the original farm.
* [Factory layout 1](../art/stock_temperate_factory_l1.blend) rearranges three purpose-built four-cell production blocks. The runtime reuses the original block art in the correct orientation and keeps exhaust attached to the displaced chimney mouths.
* [Oil Wells layout 1](../art/stock_oil_well_l1.blend) places the same original five pumpjack modules at the alternate stock positions. The [second refinery](../art/stock_oil_refinery_l1.blend) has its own receiving lanes, flare stacks and pipe runs between actual adjacent processing cells.
* The second Forest uses the original [managed forest media](../art/managed_forest.md), including the existing harvested-tree presentation.

The completed scope is layouts, not all industry mechanics. Exact site leveling for every family, industry funding/prospecting and every lifecycle or animation stage are separate work. This does not claim full Temperate map parity.
