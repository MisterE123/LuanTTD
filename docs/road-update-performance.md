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

## Live worker-to-host gaps

The optional headless test uses the real async owner, sequenced mailbox,
viewport interest scheduler, host projection and actor history. It runs
192 stock buses at 4× on the same 128×128 network with nine view
sectors, and the server loop configured for a 25 ms step. There is no client draw
or network transit in this test. Unlike the controlled stepping benchmark
above, Lua garbage collection and the normal periodic checkpoint run during the timing.

```sh
tests/campaign_pose_gap_native.sh "$(command -v luantiserver)" \
  dfda4d96a78a71a19f4efcdd4e2f748977c3082d /tmp/luanttd-pose-gaps
```

Two 14-second paired runs produced the following wall-clock measurements.
The baseline differs only in the two road simulation modules. These
are exploratory timings on the shared Linux runner, not fixed targets:

| Observation | Before (two runs) | After (two runs) |
|---|---:|---:|
| Host gap, median | 103 / 102 ms | 102 / 102 ms |
| Host gap, 95th percentile | 611 / 507 ms | 406 / 318 ms |
| Host gap, largest | 659 / 605 ms | 557 / 532 ms |
| Worker sample gap, 95th percentile | 478 / 414 ms | 364 / 304 ms |

The underlying update got faster, but it is still possible to exhaust the
host's interpolation history. No visible position prediction or simulation
rate change is included.

## Shorter synchronous checkpoint pauses

A second diagnostic timed the worker phases in the same 192-bus campaign
at 4×. The two observed synchronous checkpoints occupied the owner for
256 and 354 ms. The saved route geometry contains many small integer
fields. Emitting their already-known tag and varint as one fragment
reduces Lua calls and intermediate entries without changing a single
byte in the checkpoint.

```sh
tests/campaign_checkpoint_perf_native.sh "$(command -v luantiserver)" \
  836aa19ebc3acf1e867803d6352060ce00f955f4 \
  /tmp/luanttd-pose-gaps/after/luanttd-wide-campaign.chk /tmp/luanttd-checkpoint-bench
```

On a 192-bus checkpoint with 6,314,769 uncompressed bytes, eight runs per
implementation in each of two runs gave median encoding wall times of
257 → 218 ms and 240 → 177 ms (15% and 26%), with similar CPU times.
The packed bytes matched exactly, and the saved file reopened with both
codecs. This
does not change when saves occur or how they are committed; compression,
hash validation, and the atomic write are unchanged. It shortens one
blocking part of a save, rather than removing synchronous pauses.

## Ground occupancy on the worker

A native profile identified repeated occupancy bookkeeping inside the road
movement step. Ordinary road positions now skip the bridge/tunnel portal
lookup unless they're leaving a span. The index still removes the old
portal membership on exit. The bay occupant is only looked up in the
world when the update can change which vehicle holds the bay. The direct
daily road loop also shares one temporary movement argument instead of
allocating a wrapper for every moving vehicle on every tick. No motion
frames, gameplay rules, or time samples are removed.

The same integrated 192-bus benchmark against `8c3ab0bfc69a` gave
**68.4 → 64.9 ms** and **71.2 → 64.5 ms** median wall time per simulated
day. In each test the entire saved world and all motion samples matched
for 12 days, including 48 station arrivals. The focused regressions
also exercise bridges, tunnels, opposite lanes, on-road bays, road/tram
crossings and save/reload. These results measure worker processing, not
frame rate or a guarantee against live checkpoint-related stutters.

## Reuse identical stock road geometry, not pathfinding decisions

In a 192-bus live checkpoint, 144 vehicles held a second copy of an
already present sequence of route poses. The stock pathfinder must
still run for every departure: live traffic can affect which trace it
chooses. After pathfinding, LuanTTD can reuse the completed read-only
motion rows for the same ground trace and the same depot/stop and
one-way geometry. Vehicles still have separate route arrays and
independent cursors, speeds, orders, cargo, and economy. The cache is
per campaign and bounded. Bridges, tunnels, paired arrival bays and
mid-leg replans still compile using the original path; their context
cannot be reduced to an ordinary ground-leg key.

```sh
tests/road_route_geometry_perf_native.sh "$(command -v luantiserver)" \
  cac41ca3c3284dae03a9d363aa9874154da275e6 /tmp/luanttd-route-sharing
```

Two sets of four paired native Lua async measurements gave medians of
**343 → 81 ms** and **391 → 95 ms** for encoding and compressing the
checkpoint (excluding hashing and disk I/O). All 251,904 pose references
are still present; they now reference 31,488 unique rows instead of
251,904. Uncompressed checkpoint data fell from 8.7 MB to 2.1–2.2 MB,
and the compressed file payload from roughly 192–194 kB to 137–146 kB.
The restored worlds were stepped for 12 days and matched all saved
gameplay values and each vehicle's 75 daily pose/visibility samples;
the regression test also verifies that replacing one vehicle's route
tail cannot affect its peer after saving and reopening. The disk format
and atomic write are unchanged.
