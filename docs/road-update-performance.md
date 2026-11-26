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

## Large generated worlds: skip ineligible ocean neighbors

The RC1 flood visitor still evaluates sources, drying, and potentially
floodable neighbors in the original order. For an active source, the
native board no longer classifies stock voids or computes corner slopes
and builds a temporary descriptor for a plain water neighbor that could
not be changed. Water-backed rail, stops and woods still get the full
classification. Tests compare the exact stock receipts with and without
the shortcut and cover actual flooding, drying, and casualty handling.

Paired headless replays of the same generated 512² and 1024² saves, with
towns and industry but no player vehicles, measured median daily
simulation times of **281 → 260 ms** and **1,162 → 1,034 ms**, respectively.
The decoded campaigns matched at the same logical day on both map sizes,
apart from the elapsed real-time fraction. Large checkpoint encoding still
takes over a second on 1024²; the shortcut does not reduce that cost or
guarantee an improvement in the worst individual day's time.

## Compact checkpoints for stock woodland

On the profiled generated 1024² world, 142,415 tiles held stock trees.
Their height, terrain, variant and six small wood fields can be written
with a compact record instead of repeatedly spelling the generic fields
and graph tags. Both tile and tree retain their own table IDs. The
generic path is still used for unfamiliar fields, nonstandard values or
a woodland table seen before its tile. The new reader still opens earlier
checkpoints; an earlier binary does not understand the new woodland tag.

In two sets of paired native tests against `349badc`, the generated
1024² checkpoint encoded in **1,290 → 1,189 ms** and **1,501 → 1,196 ms**.
Raw data shrank by about 21%, and the stored compressed checkpoint by
13–15%. A native world reopened a compact checkpoint, advanced two
days with the ordinary simulation worker, and checkpointed again. The
profiled 1024² scene had towns and industry but no player vehicles.

```sh
tests/campaign_checkpoint_perf_native.sh "$(command -v luantiserver)" \
  349badcaf95bc7befa0f9db4032695d4a8027282 \
  /tmp/copied-generated-checkpoint.chk /tmp/luanttd-woodland-bench --equivalent
```

The `--equivalent` mode checks values and shared references after save
and reload rather than requiring the optimized file to have the same
bytes. Always benchmark a disposable copy, not an open world.

## Cheaper stock road route searches

The native YAPF board computes a tile's center height once per traversal.
A new search gets a fresh board, so grading and construction are still
visible. Comparing two flat road surfaces now checks the same height
tolerance directly; sloped surfaces still sample both ends and center.
No route cost, live occupancy, reservation, or selection rule changes.

A native 256² workload used 128 stock buses on 16 services alongside
purchased ore and steel trains and their original industry cargo chain.
Across 20 restored days, both versions reached identical campaign state.
Separate untimed counters showed 26,720 → 6,880 center-height resolutions
and no repeated edge samples on the fixture's 13,680 flat connections.

Two native trials timed batches of 128 complete route searches on that
saved network. Median wall time was **71.5 → 40.4 ms** and
**67.0 → 41.3 ms** (38–44% lower; similar CPU times). Explicit garbage
collection and route checks were outside the timer. This is a result
for path searches on the tested corridor, not a 38–44% game-loop or
frame-rate gain. The mixed worker still spends more time updating road
traffic than moving its two trains.

## Passenger catchments on mature networks

A house emission no longer tests every station in the network. The
commercial simulator indexes station catchment bounds into 16×16
sectors for its day's station catalog, then checks the exact union of
the facility squares for the nearby candidates. Extending/removing
physical facilities invalidates the index with the authoritative
topology revision. Shared stops, cross-sector houses, station ratings,
town rights and fixed-point allocation remain unchanged.

In a synthetic native test of 512 road, rail, dock and airport stations,
2,000 house allocations took **223 → 20 ms** and **198 → 18 ms**
(median of eight batches for each pair). The runs produced the same
2,683 allocations and 12,853 passenger units, with identical queues
and receipts. The actual mixed road/freight worker also matched its
previous saved state after 20 days and 182 house emissions. The
allocation benchmark measures one stage, not the entire simulation.

```sh
tests/passenger_supply_spatial_bench_native.sh "$(command -v luantiserver)" \
  /tmp/luanttd-passenger-index
```

### Before the first train or airport is built

Road-only games now share the same coarse catchment lookup. The road
index uses physical stop membership, the stock catchment radius, and the
day's ordered station catalog. It is reused while construction topology is
unchanged. A candidate still needs to pass the exact road coverage and
rating checks, and removing a joined member updates the index.

In two native batches of a 12-day road-only house loop with 512 stops,
the median was **114 → 93 ms** and **117 → 100 ms**. Both versions
credited 7,598 identical waiting passenger units. A separate native
77-day ordinary worker replay used 128 paid buses and no alternate
passenger service; actual cash and stop queues also matched.

```sh
tests/passenger_supply_spatial_bench_native.sh "$(command -v luantiserver)" \
  /tmp/luanttd-road-house --road-only aff651a24de6d7090893a256d95d252d1c206090
```

### Shared mail stations use less transient memory

The daily mixed road/rail/air mail allocator now uses the same coarse
sector lookup. Exact station regions still decide eligibility, including
gaps between joined facilities. It no longer builds a reverse table
entry for every tile in every station's catchment.

In native pairs with 512 stations, constructing the daily allocator
took **22.6 → 11.8 ms** and **24.4 → 13.6 ms**. Measured retained Lua
heap for the allocator dropped from about **17.2 MiB to 5.1 MiB**.
The two versions delivered the same 9,096 waiting mail units from
3,000 events, with identical queue contents. Separate real rail and
air worker tests reopened loaded vehicles, settled the correct fares
and did not pay twice after restart.

```sh
tests/passenger_supply_spatial_bench_native.sh "$(command -v luantiserver)" \
  /tmp/luanttd-shared-mail --shared-mail 3fc99ab57e1c219d8d60f71dc327d2d0e262163d
```

### Keep existing mail footprints between days

The ordinary commercial simulator now reuses the exact footprint data
when a station retains the same physical tile list, catchment setting
and map dimensions. Construction publishes a new list and triggers
a rebuild. Ratings, ownership decisions and cargo are still evaluated
live and are not in this cache.

On the same 512-station network, with geometry already loaded,
daily allocator construction measured **13.2 → 1.0 ms** and
**12.3 → 0.9 ms**. Each daily allocator added about **0.22 MiB** of
heap rather than 5.1 MiB. The original footprint geometry is still
retained; 0.22 MiB is the extra daily allocation, not total memory.
The same 3,000 house events produced identical mail queues.

```sh
LUANTTD_MAIL_BENCH_WARM=1 \
tests/passenger_supply_spatial_bench_native.sh "$(command -v luantiserver)" \
  /tmp/luanttd-shared-mail-warm --shared-mail 49ef93d62a923d19bd8abb62f59ceb94e8736d12
```

### Keep the worker mailbox responsive while catching up

At 4× speed on a large world, a slow day or an autosave can leave multiple
game days due. The native owner used to run up to twelve complete days
before returning to its mailbox. The owner now gives any waiting request
a turn at the next complete-day boundary before starting more overdue
work. It still advances the stock day in source order, preserves the
existing elapsed-time budget, and saves a durable action before its
receipt. Manual stepping is unchanged.

On Luanti 5.15.2, two native replays of the same generated 1024×1024 save at
4× speed included ordinary view requests, autosaves and one durable
company creation. The longest observed viewport replies were **26.36–37.00
seconds** before and **5.33–5.69 seconds** after. The revised worker's
median was **0.91–0.98 seconds**; the old worker returned only five view
samples per run under saturation, so its percentiles are not a stable
comparison. The durable action took **34.74–35.77 → 4.83–5.54 seconds**.
This improves request scheduling, not the CPU cost of a game day or
checkpoint, and is not a frame-rate measurement. A single heavy day or
save can still delay a reply.

The native harness works on a copy of a stock generated campaign and
does not write to the input checkpoint. On a slower host, increase
`LUANTTD_BENCH_TIMEOUT` (seconds) to allow the old worker to return.

```sh
tests/campaign_worker_fairness_native.sh "$(command -v luantiserver)" \
  958fb7ac923aa5c8f098b8063031494c50257fa9 /path/to/luanttd-campaign-owner.chk /tmp/luanttd-fairness
```

### Skip empty industry and farm callbacks on the stock landscape walk

The native owner was calling the coal, mixed-industry and farm adapters
for hundreds of thousands of cells every day. When the stock cursor and
world use the same dimensions, the adapters now use their existing
physical tile indexes directly. The worker still visits every tile in
the same order and runs the same production, cargo offer, field fencing
and regrowth rules on occupied cells. A newly planted field can become
eligible later in the same stock tick. Other board layouts keep their
coordinate lookups.

Across two native comparisons of thirteen days on the same generated
1024×1024 map, median `Sim.daily` CPU time fell from **1.13 to 0.97 s**
and from **1.09 to 0.97 s** (about **12–14%**). Total CPU across those
thirteen days fell about **6–12%**. Both final saved states matched the
original across all 1,048,576 tiles and every saved value and shared
reference, discounting only the wall-time playback fraction. This is a
worker CPU measurement, not a frame-rate or checkpoint gain.
A separate 20-day native replay with 128 buses and two freight trains
also produced identical saved state. The farm freight restart test
still settled the exact livestock, grain and factory Goods receipts.

### Avoid allocations on unchanged sea and shore visits

Flooding still checks every eligible source in stock visit order. A
plain sea or void tile is an active source regardless of its slope, so
it does not require a new terrain descriptor. The native caller also
no longer allocates an empty edit list for every unchanged visit. The
active target checks, shore drying, and protected vehicle/structure
callbacks retain their previous ordering.

On the same generated 1024×1024 campaign, the two native CPU medians
for a simulation day were **996.5 → 886.3 ms** and
**940.3 → 902.5 ms** (about **4–11%**). Both 13-day pairs ended with
the same tile states, values and aliases other than the wall-time
playback fraction. The improvement depends on how much water the
stock clock visits; these are not gameplay frame-rate figures.

### Don't scan the fleet again for each visible sector

The live host uses the assembled actor projection for its viewport.
Nine sector replies no longer repeat an unused legacy list of the same
road vehicles. The diagnostic single-window endpoint still supplies
that list, and the viewport's actor poses, shapes, orders and scene
versions are otherwise unchanged.

In the native worker, a 192-bus, nine-sector fixture made **1,864 → 136**
position lookups and dropped 136 redundant rows per batch. Warm batches
took **7.39–8.80 → 5.83–6.32 ms** of worker CPU across four alternating
samples. An ordinary mixed-fleet worker replay also kept drawing road
traffic and acknowledged both durable construction commands. The
batch timing is not a frame-rate or whole-day speedup.

### Reuse the exact corner bytes while the owner grid is unchanged

A warm sector no longer re-encodes its 33×33 shared corner heights
when the worker's terrain revision is unchanged. The cache belongs to
the bounded scene entries, not the whole map. Stock terrain commits
invalidate it; replacing the grid or backing height array also does.
An edit on the boundary refreshes both affected sectors, and other
tile state still goes through the usual scene checks.

On the nine-sector native worker fixture, warm corner encodes per
batch dropped from **9 to 0**, with identical receipts. Median whole
batch CPU was **7–12% lower** across three alternating runs. A real
stock corner raise at a sector boundary produced the same updated
bytes in both neighboring sectors as the original encoder. This does
not measure renderer frame rate or save time.
