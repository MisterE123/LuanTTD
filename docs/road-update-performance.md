# Road update performance

The 3D junction clearance guard runs inside the stock road pixel-step loop. OpenTTD movement, blocking, vehicle order, and each day's 75 pose/visibility samples still have exactly the same cadence. The guard indexes the original 3×3 junction candidates by rendered center tile once per topology instead of probing nine map cells and allocating a dedup table on every pixel. The candidate lookup includes centers immediately outside the playable map; the vehicle occupancy scans still use in-bounds tiles only. Clearance rules, swept radius, exclusion of deck occupancy, departure priority, and the height difference threshold are unchanged.

Road height is resolved lazily for the junction guard, then reused by passing, grade changes and the position just accepted into the same occupancy index. Heights are never kept between frames or ticks. This does not change the existing topology invalidation or introduce saved state.

## Reproduce

```sh
tests/road_fleet_perf_native.sh luantiserver e0a13ec90dcc02b5c10c8d899759a615b55c6aca /tmp/luanttd-road-bench
```

The native async VM compares production daily stepping for 192 bought and ordered buses of three types on 24 routed roads, spread across four companies on a 128×128 map. Buses start at separate points on their actual routes, rather than queuing at depots during the timed span. The harness alternates A/B order over 12 logical days, recursively compares the entire durable state and all road visibility/pose samples after each day, and checks that the fleet is moving and actually arriving at stations. The reported median discards the first two warm-up days. Timing excludes setup, comparisons, transport to the host, and rendering; process CPU time is less sensitive to competing workloads on the same machine. It is not an FPS or renderer benchmark.

`tests/road_junction_guard.lua` also covers lazy height lookup, rebuild after topology changes and a junction just inside the map edge, as well as the existing real bus turn/hold and resume after reload. Other regression scenarios exercise overtaking, drive-through and bay stops, crossing groups, one-way changes, bridges, tunnels, stock loading, breakdowns, and depot transitions.
