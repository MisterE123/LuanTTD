# Temperate Iron Ore, Steel, and Factory Goods

This port reads the stock OpenTTD 16.0-RC1 [industry layouts and per-tile acceptance](https://github.com/OpenTTD/OpenTTD/blob/16.0-RC1/src/table/build_industry.h),
[cargo definitions](https://github.com/OpenTTD/OpenTTD/blob/16.0-RC1/src/table/cargo_const.h), and
[vehicle purchase data](https://github.com/OpenTTD/OpenTTD/blob/16.0-RC1/src/table/engines.h).
The mine is industry type 18 and the mill is type 8. Temperate steel is made from **Iron Ore**, not Coal.
Existing stock Factories accept Steel as their third input and turn it into Goods.

## Build a service

1. Find an Iron Ore Mine, a Steel Mill, and a Factory in a generated Temperate game.
2. Use **Road Construction → Road Freight → Truck stop** to build a stop by each site. Right-click a stop to check what its actual catchment collects and accepts. A correctly placed mill stop can both accept Iron Ore and collect Steel.
3. Connect the stops to a Road depot. Buy an Iron Ore Truck and a Steel Truck. From each vehicle's card, use **Orders** to add its pickup and drop-off, then start it. Make sure both trucks can turn around.
4. To complete the chain, send a Goods Truck from the Factory to a truck stop that accepts Goods. Queues and ratings update with the running simulation.

| Service | Stock road vehicles | Capacities |
| --- | --- | --- |
| Iron Ore | MPS #147, Uhl #148, Chippy #149 | 22, 25, 27 |
| Steel | Balogh #150, Uhl #151, Kelling #152 | 15, 18, 20 |

Vehicles appear on the stock calendar. Their empty and loaded models share the same chassis mesh and change state at the original half-load threshold. See the [Mine](../art/stock_iron_mine.md), [Mill](../art/stock_steel_mill.md), [Iron Ore Trucks](../art/stock_iron_ore_road.md), and [Steel Trucks](../art/stock_steel_trucks.md) for original Blender art and source provenance.

## Verification and scope

- Native async generation on a 128×64 map produced both industries. It matched the world generated synchronously, including exact occupied tile offsets and original graphics indices.
- Each early, middle and late pair was purchased in an ordinary worker, collected and paid for real ore and steel, and resumed after reloading. Its recorded accepted cargo matched the paid cargo totals once each vehicle had finished unloading.
- Native Luanti clients displayed all six moving trucks after ordinary depot purchase and dispatch, without a missing mesh.
- Only the mounted 16-tile Mine and 12-tile Mill layouts run here. Sites still require a compatible flat platform. The alternate Mill layout, rail cargo wagons, shipping these cargos, fundraising and other climates are separate work.
