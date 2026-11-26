# Road update performance

The 3D junction clearance guard runs inside the stock road pixel-step loop. OpenTTD movement, blocking, vehicle order, and each day's 75 pose/visibility samples still have exactly the same cadence. The guard indexes the original 3×3 junction candidates by rendered center tile once per topology instead of probing nine map cells and allocating a dedup table on every pixel. The candidate lookup includes centers immediately outside the playable map; the vehicle occupancy scans still use in-bounds tiles only. Clearance rules, swept radius, exclusion of deck occupancy, departure priority, and the height difference threshold are unchanged.

Road height is resolved lazily for the junction guard, then reused by passing, grade changes and the position just accepted into the same occupancy index. Heights are never kept between frames or ticks. This does not change the existing topology invalidation or introduce saved state.

## Reproduce

```sh
tests/road_fleet_perf_native.sh luantiserver e0a13ec90dcc02b5c10c8d899759a615b55c6aca /tmp/luanttd-road-bench
```

The native async VM compares production daily stepping for 192 bought and ordered buses of three types on 24 routed roads, spread across four companies on a 128×128 map. Buses start at separate points on their actual routes, rather than queuing at depots during the timed span. The harness alternates A/B order over 12 logical days, recursively compares the entire durable state and all road visibility/pose samples after each day, and checks that the fleet is moving and actually arriving at stations. The reported median discards the first two warm-up days. Timing excludes setup, comparisons, transport to the host, and rendering; process CPU time is less sensitive to competing workloads on the same machine. It is not an FPS or renderer benchmark.

`tests/road_junction_guard.lua` also covers lazy height lookup, rebuild after topology changes and a junction just inside the map edge, as well as the existing real bus turn/hold and resume after reload. Other regression scenarios exercise overtaking, drive-through and bay stops, crossing groups, one-way changes, bridges, tunnels, stock loading, breakdowns, and depot transitions.

## Faster authoritative vehicle stepping

The paid stock road loop uses numeric proximity buckets and reuses one
short-lived candidate array, rather than constructing keys and temporary
neighbor arrays on each pixel move. Its exact search radius, oldest
vehicle-ID tie-break, bridge/tunnel portals, and reverse, overtake,
depot and bay rules are unchanged. A road vehicle's engine classification
also happens just once before its economy counters are charged.

Ordinary road height profiles are shared within a single movement tick.
The stock slope function still evaluates every exact local pixel on a
graded tile. The worker discards that cache before the next landscape
and station callbacks; bridge decks and tunnel floors read the live span
record instead. Nothing new is saved and no tick or motion sample is
omitted.

```sh
lua5.1 tests/road_traffic_runtime.lua
tests/road_fleet_perf_native.sh luantiserver \
  57327d161c1e4e955b1d6ba053864a9ed132cb4e /tmp/luanttd-busy-fleet
```

In two Luanti 5.15.2 async benchmarks, median wall time for the exact
74-tick simulation advance was **83.3 → 67.7 ms** and **97.4 → 73.3 ms**.
Median process CPU time was **83.6 → 67.2 ms** and **97.6 → 73.5 ms**.
The runs start each timed advance after a collection because the
benchmark holds both worlds in one VM. Setup, explicit collection,
rendering and IPC are outside the timer. There was still substantial
variation between individual days on the shared runner; these numbers
describe the fixture, not a guaranteed live latency or FPS.

The two variants produced identical durable state and all 75 pose and
visibility samples for each of 192 buses across 12 days; 48 reached
stations during the run. Separate instrumented runs counted
**98,688 → 74,616** road-surface resolutions over four days, including
routing and movement.
