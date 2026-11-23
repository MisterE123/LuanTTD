# Building a railway depot

Open **Rail Construction → Rail depot**. Right-click to choose which side
the door faces, then click the tile. The preview uses the same quote as
construction. An empty owned depot can be turned by choosing a different
door direction and clicking it again. Repeating its current orientation
does not charge for the depot.

This uses OpenTTD 16.0-RC1's
[`CmdBuildTrainDepot`](https://github.com/OpenTTD/OpenTTD/blob/16.0-RC1/src/rail_cmd.cpp),
[`CanBuildDepotByTileh`](https://github.com/OpenTTD/OpenTTD/blob/16.0-RC1/src/depot_func.h),
and [`CcRailDepot`](https://github.com/OpenTTD/OpenTTD/blob/16.0-RC1/src/rail_gui.cpp).
The door cannot face entirely down a slope. On valid slopes, a foundation
levels the depot and its interior rails at the highest terrain corner. A
new depot under a bridge must have at least three height levels below the
deck, measured above the highest ground corner. The quoted cost combines
the normal clearing, foundation, depot and track prices.

As in OpenTTD, the depot can be built without adjacent track. After
building, the immediate mouth is checked for owned, compatible railway,
and permitted pieces are added in source order. Each piece is a separate
purchase, so the depot remains if the company cannot afford a connector.
No piece is added on empty ground, and by default signals are not removed.

The native tool builds standard rail depots. The pure source port includes
electrified pricing; existing electric depots can be turned without
changing railtype. The native tool does not automatically connect a depot
to track where doing so would require changing railtype or removing
signals, does not replace live/coupled train or reservation state, and
does not silently remove existing railway or interfere with crossings or
subsurface infrastructure. The isolated port allows the host to inject
the stock clearing and plain-track commands rather than inventing their
rules.

Run `lua5.1 tests/rail_depot_construction.lua` for the production adapter
fixture. Compare against an extraction of pinned C++ (copies of
`rail_cmd.cpp`, `rail_gui.cpp`, `depot_func.h`, `depot_type.h`, `rail.h`,
`slope_func.h` and `table/pricebase.h`) with:

```sh
python3 tests/rail_depot_construction_upstream.py /path/to/openttd-16.0-RC1/src lua5.1
```
