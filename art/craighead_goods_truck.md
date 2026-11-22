# Craighead Goods Truck

The Craighead is a later enclosed Goods vehicle in an owned road depot.
Start a temperate world in **1976** with a sawmill, factory or refinery
Goods chain. Inspect a road depot to buy it. Use its vehicle card to add
two truck loading stops and start service. The default purchase is $7,109,
with 16 crates and a stock 88 km/h display-speed limit.

## Source and scope

OpenTTD 16.0-RC1 [`engines.h`](https://github.com/OpenTTD/OpenTTD/blob/16.0-RC1/src/table/engines.h)
provides original engine #139 and road row #23: image 22, introduction
baseline 19,724 days after 1920-01-01, decay factor 20, vehicle life 15 years,
base availability life 55 years, temperate/arctic/tropical, speed 176
half-km/h units, capacity 16, weight 48 quarter-tons, power 220 hp,
purchase factor 130 and operating factor 168. The existing stock engine
calendar controls the public sale and the freight service uses the same
integer tick cost and cargo loading logic as the early truck. This does
not add a new climate, alternative cargo refits or truck-specific faults.

The editable Blender model is entirely original. Its low forward-control
nose, two-pane glazing, full steel cargo box, pressed wheel hubs, paneled
rear doors and small plate distinguish it from the earlier separate-bonnet
Balogh with its canvas cover. No sprite files, palette pixels, or photos
were imported. The mesh uses the existing road lane center, tire contact
datum and .42 visual scale.

Rebuild with `blender -b -t 2 --python tools/build_craighead_goods_truck_art.py`.
The automated Goods route test checks normal depot purchase and two full
16-crate road deliveries. A native combined rail and road case checks
that the truck competes for real sawmill output and earns after SQLite
restart. The graphical mesh fixture can be run with
`LUANTTD_GOODS_ART_MODEL=craighead_goods_truck bash tests/balogh_goods_truck_art_native.sh`.
