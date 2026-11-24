# Road construction and selective removal

In **Roadworks → Road Options**, use **East–west road** or
**North–south road** to lock the drag to that axis. **AutoRoad** still
chooses the axis by where you point; hold **E** for a connected bend
when using AutoRoad. The bend gesture is native to Luanti, not a stock
OpenTTD command.

**Remove road pavement** is a separate tool, not the Bulldozer. Drag or
click the desired half of a tile. Valid road-removal outlines are amber.
The price covers the pavement actually selected; the swipe skips tiles
it has no right to edit and where vehicles are physically present. If
the company cannot afford the full drag, the worker applies only the
affordable prefix. Select an axis of an empty conventional level
crossing to remove its road and keep the plain railway. A vehicle
actually occupying the crossing blocks the removal; a rail reservation
on its own does not. Bulldoze remains the tool for reviewing and
choosing structural layers.

## Scope and evidence

Source: OpenTTD 16.0-RC1 (`07b339c`), `road_gui.cpp` sizing modes and
`road_cmd.cpp` `CmdRemoveLongRoad` and `RemoveRoad`. The tested
slope branch counts pieces rather than charging by tile. Where the
geometry and other way require it, a removal request can mirror the
requested piece or leave a new foundation. The pricing rules are the
ordinary campaign's base costs. Footprint and cost are checked inside
the worker when the drag is released, before spending, instead of
adding a second synchronous preview round trip. A stationary preview
keeps its complete result while the worker rechecks that same gesture;
a different drag never inherits the old quote.

- `tests/road_remove_rc1.py`: 145,920 compiled source geometry cases.
- `tests/road_remove_long.lua`: endpoint normalization, skip order,
  foundation outcomes and affordable prefix.
- `tests/campaign_authority_endpoint.lua`: stale vehicle occupancy,
  confirmed cost and prefix, road/rail split and untouched rail reservation.
- `LUANTTD_NATIVE_BENCH_REMOVE=1 bash tests/road_placement_latency_native.sh`:
  eight 45-tile native worker removals, with persisted results, typically
  reaching a receipt in 45 ms and refreshed host projection in 83 ms
  in the test workspace. This is not a client FPS measurement.
- `LUANTTD_NATIVE_ROAD_GESTURES=1 bash tests/campaign_worker_focus_native.sh`:
  an actual client selects tools and drags. An off-axis aim lays a
  straight road, then the removal tool clears it and the world reopens
  with the same running paid bus and no returned pavement.

Remaining: local-authority approval/rating, road and tram facility and
bridge/tunnel removal through this tool, waypoint placement and orders,
stop drag/orientation/joining and road-type conversion. The current
tool protects town streets and game facilities where those rules are
not yet mounted.
