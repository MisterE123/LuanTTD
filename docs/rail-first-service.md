# First passenger train without signals

A single train on an isolated connected line can serve two platforms
and reverse on its own. Lay ordinary track, place two straight
platforms, open the depot to buy a train with a passenger carriage,
choose both platform orders, then Dispatch. Use house catchments to earn
passenger fares. The beginner tutorial no longer makes signals a step
you must complete.

## OpenTTD 16.0-RC1 translation

- [`train_cmd.cpp`](https://github.com/OpenTTD/OpenTTD/blob/16.0-RC1/src/train_cmd.cpp):
  the ordinary branch of `ChooseTrainTrack` does not reserve ahead with
  a single reachable track, no path signal and the default
  `pf.reserve_paths=false`. A reverse only needs a forward reservation
  on a path-signalled segment or when the setting requires it. The
  Luanti host still journals occupied tiles for consists and crossings;
  this does not reserve an empty route ahead. This pass limits the
  no-PBS path to one owned shuttle on a simple, unsignalled railway.
  Full junction and multiple-train parity is not claimed.
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
