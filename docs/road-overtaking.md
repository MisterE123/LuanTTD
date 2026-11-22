# Stock road overtaking kernel

`mods/luanttd_core/openttd/road_overtake.lua` ports the ordinary road-vehicle
overtaking branches from OpenTTD 14.1 `src/roadveh_cmd.cpp`. The
right-driving campaign integrates it in `road_pass_runtime.lua` and the
74-tick road clock. The adapter advances the live stock movement row
rather than offsetting a precompiled pose.

## Call order

1. Supply OpenTTD units and front-engine records. Use the road vehicle
   direction (0–7), tile, state, movement frame, absolute x/y/z, actual
   speed, player-stop flag, current maximum speed and acceleration model.
   Keep `overtaking` and the byte `overtaking_ctr` across ticks and poses.
2. At each game tick, choose acceleration with
   `Speed.tick(actor, cap, O.active(actor), move)` for the original model.
   In the movement-attempt callback, call `O.before_step(actor, is_station)`
   before sampling. A tick with insufficient budget does not increment
   the counter; an attempted step that later blocks does.
3. Use `O.next_pose(Motion, actor, side)` to sample the active drive row
   with the actual previous position and heading. For a next-tile marker,
   determine the route's actual stock trackdir, and use
   `O.enter_pose(Motion, actor, tx, ty, trackdir, side, start_frame)`.
   Keep route and turn/depot/structure semantics external.
4. Probe the candidate position using the standard proximity predicate.
   Resolve a matching articulated part to its front engine. Use
   `O.within_blocked(board, actor, leader, original_acceleration)` only
   when the stock within-tile branch can start a pass. Even a successful
   pass decision returns false for that movement attempt. Tile entry
   instead uses `O.entry_blocked(actor, leader)`. If continuing,
   commit the candidate pose and update the occupancy indices immediately.
5. Supply actual logical tile membership for the look-ahead, not merely
   the normal proximity buckets. Both the current and following tile
   must have complete data. The front of a third vehicle blocks a pass
   regardless of lane, direction, ownership or height. Its detached
   articulated part does not. A missing tile or unavailable status vetoes.

`O.plain_board(F, board, vehicles_at)` supplies the ordinary YAPF road
status for the initial rollout. It deliberately does not start passes
on or immediately before unsupported structures, junctions, platforms or
crossings. A host with a full stock status callback may use `O.check`
directly, including allowed one-way roads or unbarred crossings. Red
signals must be supplied even if they do not include the active direction.
The decision covers two tiles, not arbitrary future traffic. The module
does not claim full-world vehicle collision avoidance or validate a
moving 3D render envelope.

## Verification

`lua5.1 tests/road_overtake.lua`: actual stock movement rows, proximity
and speed drive stopped- and slow-moving-leader passes, plus oncoming
occupancy and track vetoes. The stopped pass uses 18 attempted controller
steps (17 initial counter), moving uses 35. Passing keeps the normal row
on the initiating blocked step and returns to it when the timer reaches 35
on a straight. A curve retains the passing row; a station cancels
immediately; reversal cancels before entry.

`python3 tests/road_overtake_upstream.py /path/to/OpenTTD [lua5.1]`:
compile the source decision functions, dispatcher prefix, controller
timer and reversal branches directly from SHA-pinned 14.1 files.
Compare numeric state to Lua across both acceleration models and the
full byte counter in representative vehicle states. Ordinary stationary
and moving fixtures do not test the native GUI or multiplayer traffic.


## Current campaign limits

The live adapter is intentionally narrower than the source decision.
Passing starts on ordinary straight road only when the remaining sourced
frames can stay on a verified plain corridor for the whole pass window.
An aligned corridor must remain valid after topology edits; do not run
an alternate drive row onto an unverified junction, bend, depot, bridge,
tunnel or station. Roads from older saves without the source movement
frame number remain on the regular row until the next compiled leg.
The simulated traffic collision envelope adds a conservative same-lane
oncoming check for vehicles in the passing row and a blind-side check
on the merge, separate from the exact 14.1 decision. A close conflict can
wait instead of merging or crossing an occupied lane; no route-around
or emergency reverse is implied. This does not port any articulated or
tram overtaking.

The timer, lane-state and shifted actual frame are saved inside the road
speed clock. Render timelines use actual frames. Run
`lua5.1 tests/road_overtake_live.lua` for real built routes including
stopped and moving leaders, a waiting oncoming case, and a junction
change. Run `bash tests/road_overtake_sqlite.sh [luantiserver] [port]`
to checkpoint both cases in Luanti's SQLite mod storage, terminate
the server, start a fresh process, and verify both actors physically
resume their saved passing lane and merge ahead.
