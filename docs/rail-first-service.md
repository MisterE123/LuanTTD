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
  passenger fares. A path signal on another disconnected line does
  not add an ahead reservation; the actual depot segment decides.
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

Several trains can wait fully inside the same depot. The stock
37-tick release check holds the depot's track reservation only when
a front leaves and does not release the next train while its block or
depot exit is occupied. A native test saves with one train still
inside, restarts, and checks both take their own turnout branch and
earn fares.

An unprotected collision is not a hidden red signal. The stock
`CheckTrainCollision` tests real moving front and vehicle center
coordinates, length, ownership and vertical separation after each
physical step. In native QA, two ordered trains restored from an
unsignalled opposite approach hit at seven stock pixels. Both stopped,
the wrecks held the track, then the last bodies cleared and released
it. The crash record applies the stock 160-point rating loss to
represented active passenger cargo at owned stations within 30
Manhattan tiles. Full news presentation, crash effects, all freight
rating entries and some tunnel/wreck cases remain unported. Avoid
single-track head-to-head routes without a passing loop.


While ordinary owned trains run, you can add independent railway and
place, flip or remove its signals. The tools still protect occupied,
reserved and currently ordered tracks; destructive edits that require
full stock rerouting are not enabled by this change. Native mixed-fleet
QA builds and signals another line while both existing trains continue
to earn fares across a restart.


## Passenger and freight trains on the same clock

The source train tick processes all vehicles once, in pool order. The
rail adapters now prepare independent cargo callbacks and advance the
physical fleet once per simulation tick. Passenger boarding and Goods
loading do not advance each other's trains a second time. One freight
train and multiple passenger trains may coexist; native QA verifies a
Goods Van still loading after SQLite restart, then paid Goods delivery
and passenger fares on the same company clock. Arbitrary freight fleets
and wagons beyond the mounted cargo formations are still in progress.

An ordinary approach can enter an unreserved bridge or tunnel without
forcing a reservation to its destination. It occupies the span as it
enters and releases the physical portals after its last car clears. A
signal-free round-trip test goes over a bridge, through a tunnel and
across a road, then reverses and earns fares after save/restore.


## Signal placement on curves

On plain track, aim at the actual piece. For parallel half tracks, the
same 16-by-16 fractional tile selection as OpenTTD 16.0-RC1
[`GenericPlaceSignals`](https://github.com/OpenTTD/OpenTTD/blob/16.0-RC1/src/rail_gui.cpp)
chooses the track. Pick its travel direction in the placement panel or
both heads for a conventional signal. To remove only one signal, choose
the matching curve in the Bulldozer layer dialog. Junctions where the
actual tracks overlap cannot hold these signals.

Linux native verification built a path signal and a bidirectional block
signal on different halves of one tile and mounted all three physical
heads. The 3D mast starts at the stock sprite anchor and may move
slightly to clear the swept train body on curves; this does not change
which track or direction it protects.


## Placing a depot

With **Rail depot** selected, the door faces you by default. The
placement preview shows the compass direction. Right-click to pick a
fixed direction or select **Face me** to return to automatic facing.
The same tool can
rotate a clear owned depot; a no-change quote costs nothing. Keep the
exit next to the line if you want automatic attachment. The post-build
connections are independent stock rail quotes, not free automatic
trackwork. A refused or unaffordable connection does not undo the depot.

The construction command uses the 16.0-RC1 direction-dependent
foundation and clearance checks, including supported steep slopes and
the required height under overhead bridges. It will not silently clear
an existing rail tile. Sheltered roofs, platform props and track beds
were reduced in native size, while running rails and depot wheel/track
anchors still align.

## Passenger station orders

Choose **Set orders** for a purchased passenger train in the depot, then use **Pick** to click platforms in visit order. Open **Review orders** to select a row, move it up or down, or delete it. Choose **Dispatch** when the list is ready. The train repeats the list and can reverse at an end station. A two-platform route can still use the dedicated waypoint workflow.

This port uses the OpenTTD 16.0-RC1 cursor rules from [`vehicle_base.h`](https://github.com/OpenTTD/OpenTTD/blob/16.0-RC1/src/vehicle_base.h) and the draft edit index rules from [`order_cmd.cpp`](https://github.com/OpenTTD/OpenTTD/blob/16.0-RC1/src/order_cmd.cpp). [The test](../tests/rail_order_index_upstream.py) compares the Lua cursors against 22,580 cases executed against the pinned upstream C++ source. [The native test](../tests/rail_order_list_native.lua) exercises six arrivals and fare payment across a SQLite save and restart. This is for normal passenger station orders chosen before dispatch. Repeated adjacent entries, general waypoints, edit/skip during service, freight lists, depot/conditional orders, shared lists and timetables are not part of this proof.

### Tight corners

A right-angle turn across two immediately adjoining curves may be valid
track geometry but forbidden to trains. OpenTTD 16.0-RC1 ships with
**Forbid 90 degree train turns** on. Prefer a gentler turnout or go the
other way first. If you deliberately want that stock Expert setting off,
set `luanttd_forbid_90_deg = false` in the server's Luanti configuration
and restart the world. The setting applies in the railway worker, not
just to a UI preview; specific rail-type restrictions still take priority.
