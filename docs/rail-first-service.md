# First passenger train without signals

A single train on an isolated connected line can serve two platforms
and reverse on its own. Lay ordinary track, place two straight
platforms, open the depot to buy a train with a passenger carriage,
choose both platform orders, then Dispatch. Use house catchments to earn
passenger fares. The beginner tutorial no longer makes signals a step
you must complete.

## Place or extend a station

Select **Rail station** and drag a rectangle. Right-click with the tool to
choose the platform orientation, use fixed track count and length instead,
or build separately from an adjacent station. The footprint and price are
shown before release. A nearby station of your company can extend as the
same station that existing vehicle orders refer to.

## OpenTTD 16.0-RC1 translation

The station footprint follows `PlaceRail_Station` / `HandleStationPlacement`
in [rail_gui.cpp](https://github.com/OpenTTD/OpenTTD/blob/16.0-RC1/src/rail_gui.cpp)
and the limited rectangle selection in [viewport.cpp](https://github.com/OpenTTD/OpenTTD/blob/16.0-RC1/src/viewport.cpp).
Ordinary rail station joining follows `FindJoiningBaseStation` /
`GetStationAround` in [station_cmd.cpp](https://github.com/OpenTTD/OpenTTD/blob/16.0-RC1/src/station_cmd.cpp).
This pass supports level rail platforms, not distant join, non-rail station
joining, sloped foundations or the full stock station selection UI.

- [`train_cmd.cpp`](https://github.com/OpenTTD/OpenTTD/blob/16.0-RC1/src/train_cmd.cpp):
  the ordinary branch of `ChooseTrainTrack` does not reserve ahead with
  a single reachable track, no path signal and the default
  `pf.reserve_paths=false`. A reverse only needs a forward reservation
  on a path-signalled segment or when the setting requires it. The
  Luanti host still journals occupied tiles for consists and crossings;
  this does not reserve an empty route ahead. For one owned train
  on an unsignalled railway, the moving front now calls stock YAPF at
  a choice, including the junction where a side depot meets a main
  line. The native regression buys a train, takes the depot curve,
  restarts, then crosses that turnout in both directions and earns
  passenger fares. Mixed signals and multiple-train parity are not
  part of this test.
- [`rail_gui.cpp`](https://github.com/OpenTTD/OpenTTD/blob/16.0-RC1/src/rail_gui.cpp#L109-L165):
  after successful depot construction, the callback tries the stock
  three direction-dependent track pieces on the immediately adjacent
  exit tile. Each is independently purchased through the ordinary
  BuildRail validator. An unaffordable or forbidden piece does not
  roll back the depot. It does not lay track across an empty gap.
- [`tree_cmd.cpp`](https://github.com/OpenTTD/OpenTTD/blob/16.0-RC1/src/tree_cmd.cpp):
  AutoRail quotes the temperate dry-tree clear cost per stem using
  `ClearTrees` from the stock price table and removes the trees on
  commit. Protected land, incompatible slopes and water still stop a
  drag. This does not port tree-clearing authority penalties.
- [`rail_cmd.cpp`](https://github.com/OpenTTD/OpenTTD/blob/16.0-RC1/src/rail_cmd.cpp):
  flipping a single existing head of the same variant is free. The
  Luanti direction picker and private aim arrow are presentation
  adapters, not extra rules. Layered removal confirms a whole affected
  facility while keeping supported underlying layers.

The straight 3D diagonal is a rendering adapter. It preserves the logical
half-tile rail pieces, track directions, pathfinder, train length, station
axes and signal rules. Visual train poses follow the new meshes, and
diagonals ease back to the ordinary rail at ends and junctions.

## Mixed signals and more than one train

Use the **Both directions** choice for a conventional block signal when
both directions are allowed. Protect every approach to a shared junction
with signals. In the depot, buy and order each passenger train separately;
no joint preview dispatcher is required. These ordinary mixed-signal
services use the same physical track and loading clock for all of the
company's trains.

[OpenTTD 16.0-RC1 signal.cpp](https://github.com/OpenTTD/OpenTTD/blob/16.0-RC1/src/signal.cpp)
sets unreserved path aspects from real occupancy, splits and multiple
entrances. A reserved head is left to the path reservation code.
[train_cmd.cpp](https://github.com/OpenTTD/OpenTTD/blob/16.0-RC1/src/train_cmd.cpp)
classifies the depot segment and updates both the moving front and tail.
A conventional head into a Path block triggers reservation *after* the
front crosses it. The native regression saves while a train is held on
one approach to a four-way diamond, restarts, and follows both separately
bought trains through reciprocal trips with independent passenger fares.

This pass does not enable unsignalled multiple-train operation, shared
depot occupancy or dispatching freight and passengers together. Avoid
single-track head-to-head routes without a passing loop.
