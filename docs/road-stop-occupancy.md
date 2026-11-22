# Stock road-stop occupancy and controller kernel

The isolated `openttd/road_stop_occupancy.lua` implements ordinary
OpenTTD 14.1 bay state and directional drive-through entry caches from
`src/roadstop.cpp`, `src/roadstop_base.h`,
`src/station_cmd.cpp` and `src/roadveh_cmd.cpp`.
It does not change the game's current single modeled shelter or enable
two-bay traffic automatically.

## Bay approach, parking, and release

There are three separate occupancy bits:

- Status bits 0 and 1 are set when the respective bay is **free**.
  Enter always takes the lowest-numbered free bay.
- Status bit 7 is the shared **entrance busy** lock. A vehicle claims the
  lock when entering and releases it on reaching the actual parked
  frame. The bay remains occupied while loading. Leaving the parked
  frame requires reacquiring the lock. Physically leaving the tile
  frees both that bay and the entrance. Waiting at the parked frame
  keeps speed zero if another vehicle owns the entrance.
- Articulated vehicles cannot enter an ordinary bay, even with both
  bays and the entrance free. An ordinary bay does not allow reverse
  at tile exit. Through-stop handling is independent of bay flags.

Road-vehicle movement state is `32 + trackdir + 2*bay`. Bit 2 marks
the already-entered/loading berth and does not change the motion row.
The pinned rows are already in `road_motion_data.lua`. The following
numbers use the stock tile's 0–15 planar pixels and 0–7 heading, with
right-hand traffic:

| Entry trackdir | Relative berth 0 | Relative berth 1 | Parked heading | Parked row frames 0/1 |
|---|---:|---:|---:|---:|
| 0 (NE, −X) | (5,6) | (9,6) | 7 | 16/12 |
| 1 (SE, +Z) | (6,10) | (6,6) | 1 | 16/12 |
| 8 (SW, +X) | (10,9) | (6,9) | 3 | 15/11 |
| 9 (NW, −Z) | (9,5) | (9,9) | 5 | 15/11 |

Left-hand traffic uses parked-frame pairs 20/16, 20/16, 19/15, 19/15.
The stock positions are four pixels apart along the tile's parking
axis. Native lane projection must not collapse the two poses into the
same center. These are slots within one tile, not two stops occupying
two tiles.

## Drive-through line, entry cache, and real vehicle tail

A through-stop shares a line with consecutive same-station,
same-facility-type tiles with the exact same orientation. The canonical
orientation is `AXIS_X=0` or `AXIS_Y=1`. The smallest tile ID is the
shared base. Cache both directed entries independently: stock
directions 0–1 are the east entry, 2–3 are west. Each tile contributes
16 units of length. Entry occupancy is the sum of full *cached chain
lengths* of admitted fronts, not a vehicle count or a hard capacity.
It is legitimate for that total to exceed line length.

Merging/joining a line preserves both occupied totals. Removing an
empty middle tile splits it and rebuilds both sides from the
authoritative tile hash, counting each compatible **directional**
primary front once, and excluding crashed actors, normal-road states
and non-road vehicles. Removing an empty end simply reduces length.
A front moving across a continuation keeps ownership of the same
entry. Moving its front out of the line, or crashing the front,
subtracts its full cached length. Track occupancy of a still-present
articulated tail **separately** for physical collision or train-bar
admission; do not treat entry utilization as tail clearance, and do
not apply the same release to both front and tail.

A through-stop uses the original two opposite-direction straight road
lanes, not a new bypass lane. Stop frame 11 can move onward if there is
the same compatible platform ahead, after ordinary headway checks have
already passed. A vehicle stopped by traffic may begin loading earlier
only for a matching owned stop/destination and when not leaving it.
A vehicle passing a different stop still contributes to its utilization
but does not automatically load there.

## Host call order

- Instantiate with `RoadStopOccupancy(Motion)`. Store the result of
  `new()` in campaign data. `register(cache,board,id)` follows the
  physical board placing a stop. `clear(cache,board,id,actors_at)`
  follows normal ground-vehicle clearance (requires the old stop to still
  be queryable); the host may then remove the map tile. The cache stores
  integer group keys, so serialization does not rely on aliased tables.
- Board records are `kind=bay_stop|drive_stop`, `station`, `stop_type`,
  `dir` and `owner`. Adapter functions `tile(id)` and
  `adjacent(id,diag)` are authoritative. `actors_at(id)` provides stock
  tile membership for cache rebuild. Actor records use `state`, `frame`,
  `direction`, `tile`, `speed`, `id/first` (or `front` and
  `primary`), `total_length`, `articulated`, `bus`, `owner`,
  `type` and `crashed` fields. Stock trams count as road vehicles on a
  through stop, but native tram routing/queue integration is separate.
- Call `station_callback(cache,board,id,actor)` at the stock
  VehicleEnterTile callback using the actor's current state/frame,
  not an assumed bay on tile-boundary arrival. After geometry,
  proximity and crossing admission succeed, `transition(cache,board,
  actor,next_tile,selected_td)` releases or retains the old entry
  and gives the state to commit. Preserve the existing road–rail
  crossing acquire/transaction scope; don't release a prior claim on
  a movement attempt that is rejected at the crossing.
- The normal movement loop chooses actual row from current state and
  observes proximity. After leader-speed matching, `blocked_load`
  can request early platform loading. Otherwise at the correct current
  stop frame call `at_stop(...,traffic_side,order,compatible)`. It
  returns `ordinary`, `move_inline`, `load`, `wait_entrance` or
  `depart`. For `move_inline` the host commits the frame movement
  and skips the ordinary inclination branch; for `load` it calls
  BeginLoading and does not advance; for `wait_entrance` it likewise
  does not advance. Apply `commit_through_motion` after a successful
  ordinary advance when leaving a drive-through stop. The host owns
  actual order and loading state; the order view has `kind`, `station`
  and `should_stop` from the actual order logic.
- `routing(cache,base_board)` overlays `bay_free`, `stop_entry`
  (occupied, length) and `stop_continues` for the existing YAPF cost
  specialization. This is accounting feedback, not an admission
  shortcut. `crash` and `delete_tail` are one-time callbacks for their
  respective source lifecycle branches.

This port does not implement bankrupt/flood removal, station NewGRF
callbacks, whole articulated-vehicle kinematics, or physical/native
two-bay validation. Live route compilation needs to respect the
selected bay in the actual motion row before this can be enabled.

## Tests

`lua5.1 tests/road_stop_occupancy.lua` exercises the full two-bay
queue and a drive-through merge/split with actual source movement rows
and a serialization-style restored representation.
`python3 tests/road_stop_occupancy_upstream.py /path/to/OpenTTD [lua5.1]`
compiles SHA-pinned ownership/status methods, directional list
cache, admission and selected controller branches; the harness supplies
tile hashes, orders and vehicle identities instead of running the
whole OpenTTD UI.
