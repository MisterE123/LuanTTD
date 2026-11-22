# Stock Country Airfield: two ground/runway actors

`airport_ground_pair.lua` is an isolated OpenTTD 14.1 movement and reservation prerequisite, **not** a mounted airline, purchase menu, or commercial two-aircraft service. It runs two stock fixed-wing Sampson U52s (#215), each from a separate owned Country Airfield, into a third shared Country Airfield and back to its own origin. The scenario uses the real 4×3 FTA, direct stock flight, original acceleration and speed, and stocks exactly two terminal bits. It does not create a synthetic airport queue, change any movement point, or add a position/radius admission rule.

On each world tick the first aircraft executes its two original controller passes before the second aircraft executes its two. They read and mutate the same saved flags word on the actual airport. Approaching a busy runway runs the standard holding circuit and restores airspeed. The runway clears when the aircraft **physically reaches the next stock FTA clearance point** and `AirportClearBlock` sees a different block. It is neither freed when a timer expires nor held by a newly invented tail-distance threshold. Both stands, separate taxi paths, takeoff contention and separate return orders are exercised.

## Prerequisite API

```lua
local Pair = dofile(mod.."/airport_ground_pair.lua")(Sim, Small, Motion, Terrain)
local pair = Pair.start(S, owner, origin_a, origin_b, shared_airfield)
local events, why = Pair.advance(S, callbacks, world_tick)
```

- `start` only takes three distinct, unoccupied, north-facing owned Country Airfields. It will not replace a live singleton. Save state at `S.airport_ground_pair` alongside the actual shared flags on `S.stock_small_airports`. Actors have stable `id` and `stock_engine`, two independent orders and physical poses. Aircraft are processed in creation order in this standalone pair.
- Call `advance` once per absolute **stock simulation** tick, after station loading. The native test uses an explicit loop. An optional `world_tick` rejects duplicate/reversed ticks across reload; pausing requires not calling `advance`. No animation callback should advance it a second time.
- Optional callbacks: `arrive(actor, cargo_tile, actual_field)` records an actual terminal visit and returns true; `leave(actor, field)` gates the shared terminal's return departure on the host's real loading readiness. `request_return(S, owner, actor_id)` is the explicit non-commercial counterpart for an actor already stopped at the shared terminal. There is no invented dwell. Once returned, each plane is parked at its original airport. Cargo queues, tickets, purchase, and company running costs are not mounted by this module.
- `current(S)`, `actor(S,id)` and `pose(actor)` expose the two actors. `protects_airfield(S,id)` is the adapter callback for native airport removal. A broken field fingerprint stops the controller without clearing other aircraft's flags.
- A native pair renderer must use `airport_airframe_art.lua`. The existing singleton already uses the **same 0.88 Sampson scale** for its real model, with no alternative shape, horizontal offsets or modified altitude. The wheels keep their original local Y=0; on-ground pitch is neutral. This is a deliberately conservative native mesh adjustment, not a source flight rule.

The scope is single company, unrotated Country Airfields, two small stock U52 aircraft, at controlled same-model clearances. It does not enforce airborne spacing, route around a removed airfield, handle crashes, or mount another aircraft model.

## Verification

```sh
lua5.1 tests/airport_preview_run.lua
lua5.1 tests/airport_ground_pair.lua
python3 tests/airport_small_upstream.py /path/to/pinned-14.1 lua5.1 --pair
python3 tests/airport_ground_pair_geometry.py lua5.1
LUA=lua5.1 python3 tests/small_airport_art.py
TMPDIR=/path/to/qa BAYLINE_NATIVE_TOOLS=/path/to/tools tests/airport_ground_pair_native.sh
```

The pair travels from logical (7,13) and (32,13) into (22,13). Plane 2 reserves the runway on tick 665. Plane 1 encounters that busy reservation at tick 1109 and circles with its speed unchanged. A save/reload happens there. Plane 2 physically reaches Term 1 and clears the runway on tick 1133; Plane 1 enters the same runway on 1984 and parks at Term 2. Both return after separately requested departures, yielding 584 authentic stock ground wait transitions. The native two-boot fixture verifies saved busy, no skipped hold, distinct real 0.88 render objects at the true tire-contact datum, and proper final shared-airfield release.

The C++ differential replays 665 actual position-event transitions using pinned upstream table construction, block tests/setting/clearing, stock flying action, ordinary transfer and terminal allocation with **persistent shared reference airport masks**, plus the original exhaustive primitive tests. The art proof checks conservative real mesh envelopes in 1,629 exact movement passes and 517 synchronized render frames with continuous sweeps. Minimum center clearance is 1.750 nodes; the **conservative** hull clearance is 0.017066 nodes. The singleton hangar, two stand paths, moving gear and tail were swept against the actual twelve airport OBJ components at the same scale in another 2,101 poses.
