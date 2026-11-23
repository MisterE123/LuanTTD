# Stock road fleet: bus, farm, and timber expansion

The regular worker-owned road depot offers the Foster MkII Superbus (#119),
the Thomas and Goss grain trucks (#142 and #143), the Uhl and Foster livestock
vans (#136 and #137), and the Foster and Moreland wood trucks (#145 and #146).
Availability follows the stock engine calendar. The bus uses the same passenger
stations and orders as other buses. For the trucks, place truck stops at a crop
farm and a factory, or a forest and a sawmill. The train depots are not needed.

The hardware and economic inputs come from the pinned OpenTTD 16.0-RC1
`src/table/engines.h`; each vehicle has an independently authored 3D model and
editable Blender source. The grain and wood bodies change when the vehicle reaches
half its stock cargo capacity (integer truncation). An empty livestock carrier is
not rendered with an extra load mesh.

`tools/build_road_farm_fleet_catalog.py` compares the pinned engine rows. The two
farm-workbench variants, two timber route variants, and Superbus market regression
run paid routes with restored state. Those checks do not claim the entire OpenTTD
road engine roster, all native load graphics, or all refits and breakdowns.

A real Linux Luanti client and the ordinary campaign worker verified all four
2025 models in distinct generated road corridors. They were quoted at ordinary
depots, bought, given two stops, and rendered running on the road. Paid
attendance and cargo/save regressions are distinct economic tests. Run the
graphical check with `bash tests/stock_road_fleet_native.sh`.

## Coal, oil, goods and mail

Ordinary depots also offer Uhl and DW coal trucks (#124 and #125), Foster and
Perry oil tankers (#133 and #134), Goss Goods (#140), and MPS, Reynard and Perry
mail trucks (#126–128). Source-only rows are not purchasable until their native
mesh and atlas load and their stock market date arrives. Mail runs between truck
stops near buildings that produce and accept mail. Coal is picked up at a mine
and sold at a power plant; crude is delivered to a refinery, which can produce
Goods for a town. Existing ordinary running-cost, station rating, quote and
payment routines handle the new rows. The coal models change load mesh at the
stock integer-half thresholds (12/25, 14/28); the tankers and box vans keep
their enclosed body through loading.

Linux Luanti graphical depot–road checks covered each new model at 1950, 1985
or 2025. Scripted deliveries also tested repeated calendar-correct fares after
save-state cloning, including coal to a real power plant and oil to a real
refinery. This is not the entire OpenTTD roster or a full port of road refits,
NewGRF callbacks or alternate climates.
