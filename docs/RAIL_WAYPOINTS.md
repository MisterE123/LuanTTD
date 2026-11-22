# Stock rail waypoints

Railways can carry a single-tile wayfinding sign on a straight rail piece.
It is not a passenger platform, stop, depot, or freight stage. Create one
on existing track for $600, or remove the sign while keeping the rail for
$150 at base prices. The quote/apply functions use the same ownership and
construction transaction as ordinary rail. A waypoint preserves the rail
piece, railtype and reservation data; the host does not permit removing an
active route's or otherwise reserved waypoint. Signals, junctions,
crossings and protected transport layers are refused. Level rail and
existing stock level foundations on accepted non-steep slopes are supported.

For a purchased passenger shuttle, choose the first real passenger
platform, optionally a waypoint, then the second real platform. The train
goes to the first platform from its depot as before. It then follows the
waypoint on each leg between the two platforms. It passes the sign on the
actual chosen track without stopping or loading there. This preview
supports one waypoint and one owned passenger shuttle with safe ends on
both real platform legs. It does not mount a full stock orders list,
waypoint joining, custom NewGRF graphics, opposite direction via orders,
freight or paired-waypoint operations.

The host stores the waypoint in the shared station/waypoint ID pool but
not in the station, cargo or catchment registry. YAPF searches the actual
waypoint through the destination adapter and keeps the approach and
continuation on that route. PBS may use the next real platform order to
extend through an unsafe-to-stop waypoint, with the same staged reservation
checks as the through-platform controller. Front passage updates the order
and increments its saved pass count, without changing speed or opening a
cargo operation. Existing track/portal protection remains authoritative.

Source: OpenTTD 14.1 `src/waypoint_cmd.cpp`
(`GetAxisForNewWaypoint`, `IsValidTileForWaypoint`, `CmdBuildRailWaypoint`),
`src/station_cmd.cpp` (`CmdRemoveFromRailWaypoint`, `RemoveFromRailBaseStation`),
`src/table/pricebase.h` and `src/train_cmd.cpp`
(`CheckNextTrainTile`, `ChooseTrainTrack`). OpenTTD contributors, GPL-2.0-only.

```sh
python3 tests/rail_waypoint_upstream.py /path/to/openttd-14.1 lua5.1
lua5.1 tests/rail_owned_service.lua waypoint
```

The stock oracle compiles the original eligibility helpers and prices
against 72,960 deterministic tile cases. The paid train fixture physically
takes the shorter main line to its first station, then the alternate line
through the waypoint twice, persists the active waypoint order across
reload, passes while moving, and only loads and earns fares at actual
passenger platforms.
