# Ordinary level-crossing kernel

This isolated kernel is pinned to OpenTTD 14.1. It does not yet place a
crossing in a saved LuanTTD world or arbitrate two live vehicle clocks.

- Source: rail_cmd.cpp and road_cmd.cpp crossing branches, road_map.h
  axis/owner fields, train_cmd.cpp barrier/approach/tail logic, pbs.cpp
  reservations, road_cmd.cpp road track-status masks, and roadveh_cmd.cpp
  geometric contact test.
- Construction: pass a physical map record and a rail or road/tram request
  to Crossing.quote. Road bits are stock NW/SW/SE/NE = 1/2/4/8, not
  host-specific map bits. Quotes report the resulting crossing record,
  independent rail/road/tram owners, road/rail axes, cost, flattened top,
  and infrastructure deltas. Adding road to plain reserved rail preserves
  the reservation; adding a missing road/tram layer preserves current
  bars and reservation. FALLBACK_CLEAR is a handoff to the existing
  clear/plan path, not permission to demolish infrastructure.
- Boards: tile(id) returns the persistent crossing record, adjacent(id,d)
  uses stock NE=−X, SE=+Z, SW=+X, NW=−Z. road_axis and rail_axis differ.
  road_view and rail_view expose the existing follower axis conventions.
- Motion: call update on placement/invalidation, try_reserve and unreserve
  at the PBS boundary, maybe_bar at head approach after line-end checks,
  and tail_left after committing the final wagon's new tile to occupancy.
  Supply actual train parts to ctx.vehicles_at (including a crashed train
  when still physically present). With shared PBS state use
  ctx.reserved(id,axis) and ctx.set_reservation(id,axis,on) instead of
  writing a second copy of the reservation. Group changes return tile,
  barred, and sound events for presentation.
- Source behavior: road_status separates directed topology from red bits.
  Apply road_step to entry, never to stop or evict cars already on a tile.
  A grouped interior tile may admit travel when neither a train part nor
  its direction is blocked, even with the adjacent bars down. Stock does
  not prevent a train from entering because a car is on the crossing.
  stock_collision detects the stock crash candidate (±4 stock pixels
  on each horizontal axis, ±6 height); it does not remove vehicles.
  Pose records use stock x/y for horizontal and z for elevation, not
  native Luanti's x/z ground and y elevation.
- A fail-closed host can hold a new train entry until an admitted road
  vehicle clears. That is a separate policy, not the stock behavior.
  Keep it separate from the bars: a car stuck by the bars and a train
  waiting for that car to clear could otherwise deadlock each other.

Run tests/level_crossing.lua for pure rail/head/tail and road arbitration.
Run tests/level_crossing_upstream.py with the OpenTTD 14.1 source path
to compile the original crossing-create quote branches, barrier/red
status, vehicle exit and collision predicate for comparison.
