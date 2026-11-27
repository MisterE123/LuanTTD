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

### Do not rebuild the road junction index after unrelated tides

The authoritative tide increments the general terrain revision for each
batch of physical changes. The native 3D junction guard used to rebuild
its index after each such batch whenever a vehicle next needed it,
scanning the entire map twice even when the shore was far from the
roads. Plain sea, shore, open land, and tree changes with no structure
or road facility can now carry the last known junction index forward
one revision. An intervening road edit, or a flood touching a facility,
span, or object, still invalidates the index. A necessary rebuild scans
the map once and visits only actual junctions in the second pass, in
the same tile order. No vehicle occupancy, admission, or tide rules
change.

On a 512×512 native Luanti worker with 96 paid buses and an actively
flooding separate shelf, two eight-day comparisons gave median CPU
**305–307 ms → 68–70 ms** per simulated day. The tide made 209–361 map
revisions per day; all world values and every vehicle timeline
matched, including the first 12 station arrivals. This is a benchmark
with frequent coastal changes, not a general FPS measurement.

```sh
tests/coastal_road_network_perf_native.sh luantiserver 1cd8c30 ../coastal-road-perf
```

### Do not recompute river directions after remote tide changes

A river's projected flow depends on each river tile and its adjacent
water outlets. On generated worlds the owner now retains directions
after a plain flood only when the actual changed tiles are outside that
dependency set. Tides at an outlet, geometry edits, and gaps in the
revision sequence still force a rebuild. This affects the direction
sent to views, not the river or navigation rules.

In the 512×512 native probe, comparing directions for all 66 river
tiles after each of 73 real stock floods matched exactly. In four
alternating samples the accumulated direction-query CPU time went
from about **33–36 ms to 0.7–1.4 ms**. This measures only the
river-direction work, not full snapshot latency. The ordinary
generated-world worker also returned the same direction through ten
real snapshots.

```sh
tests/river_tide_perf_native.sh luantiserver ../river-tide-perf
```

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

### Release the checkpoint decoder's temporary memory

After restoring aliases and cycles, the decoder now explicitly drops
its lookup tables and decompressed input. The restored graph keeps its
own references. No save bytes or supported checkpoint fields change.

In two native opens of the same 1024×1024 save, the main VM's Lua heap
after collection dropped from **391.3 to 349.4 MiB** and the worker's
from **388.0 to 346.0 MiB**, about **84 MiB combined**. The 512×512 case
saved about **20 MiB combined**. The measurements exclude engine and
graphics memory. The two VMs still hold separate map data; this change
only releases the temporary decoder storage.

Packed graph, alias, cycle and woodland tests passed, as did the
native quiet-host continuation and in-place recovery from a durable
checkpoint after an injected worker failure.

### Compact the presentation host's bootstrap tiles after handoff

Once the starting area is placed and the worker has sealed and opened
the durable campaign, the presentation host replaces its old dense tile
tables with a compact coordinate fallback. Ordinary land, water and
woodland use the existing field representation. Special tiles retain
their original records. The worker keeps its complete authoritative
map; the host still paints, picks, and updates live terrain from sparse
worker sectors. The save format and simulation are unchanged.

On the same native 1024×1024 world, the host's Lua heap after collection
was **349.4 → 166.4 MiB** (about **183 MiB lower**, after the separate
decoder fix). The worker remained at **346 MiB**. The 512×512 host fell
from **105.6 to 61.4 MiB**. The existing corner grid and other small
presentation and bootstrap records remain. These are Lua heap results,
not total process memory. The compact fallback is built once at handoff,
not during rendering; the 1024×1024 prototype built it in about 220 ms.

A fresh 512×512 native graphical session admitted the player, accepted
real horizontal input, persisted a company transaction, and streamed
a far-away sector after a jump while forgetting the previous sector.
A restart reopened the same company, clock, and command revision.
The standard 64×64 session also passed. To repeat the larger test:

```sh
LUANTTD_NATIVE_SESSION_SIZE=512 tests/campaign_worker_session_native.sh
```

### Avoid rewriting an unchanged paused campaign

Once the worker has checkpointed a paused campaign, ordinary viewport
and clock reads no longer cause another full save every eight seconds.
Running simulation and other requests conservatively make the campaign
eligible for periodic saving again. Edits that require immediate
durability still save before returning success. Explicit saves and
shutdown always write.

In a native 1024×1024 paused session, 19 seconds of viewport traffic
previously triggered two redundant saves (1.32 and 1.46 seconds).
The revised worker performed neither and the before/after save bytes
matched. Native testing also reopened the durable account edit and
verified resume and re-pause; deterministic regression tests cover
periodic saving of edits without immediate durability.

### Check only populated fields in ordinary tile snapshots

Native tiles have only a small subset of the whitelist populated. The
worker now checks those fields and verifies that nothing visible was
removed, rather than checking every possible field on every tile. It
still compares nested fields and ignores private simulation data.
Preview overlays with inherited fields keep the original lookup path.

On two native runs of nine warm sectors and 192 buses, median whole
batch CPU fell from about **5.8–5.9 ms to 4.0–4.1 ms**, with exact
receipts before and after a shared-corner edit. Scene tests also cover
field deletion, nested changes, station/bridge data and ignored fields.
This is viewport CPU, not full simulation or frame-rate speed.

### Reuse packed string-reference bytes during checkpoint encoding

Most keys in the general checkpoint records repeat. The writer now
emits each already-interned key or string as one prepacked fragment,
rather than re-encoding the same reference bytes. The format, dictionary
order, and alias handling are unchanged.

In a native LuaJIT run alternating twelve encodes of the same generated
1024×1024 world, median packing CPU fell from **1.34 s to 1.10 s**. In
sixteen alternating encodes of the 192-bus fixture it fell from
**139 ms to 121 ms**. Every packed byte matched the baseline on both
fixtures, and both versions reopened the resulting file. Unit tests
check repeated keys and references crossing the one-, two-, and
three-byte boundaries. This measures packing only, not disk time or
the observer's frame rate.

### Return a waiting view before catching up after a slow worker turn

When a view request has waited through a long owner turn, the worker
returns the last completed view before it starts another full game day.
This avoids adding a second delay immediately after, for example, a
synchronous autosave. It does not move simulation work to the host or
skip any stock ticks. Normal short turns, commands, and the durability
of edits are unchanged.

On two pairs of ordinary Luanti sessions at 1× on the same generated
1024×1024 world, the longest of each run's observed viewport replies
dropped from **2.04–2.20 s to 1.34–1.75 s**. All four runs advanced the
same number of logical days and ticks. Typical replies still took
about 25 ms, and the 95th percentile varied between runs. This is a
tail-latency safeguard, not a simulation CPU gain or a renderer test.
The owner-loop regression covers the same save-plus-day sequence with
a deterministic clock, including fast views and durable edits.

### Reuse the stock follower while rating ship path nodes

OpenTTD 16.0-RC1 passes a track follower from
`CYapfBaseT::AddMultipleNodes` to `AddNewNode` and then to the ship's
`PfCalcCost`. The Lua port now does the same instead of reading and
following the same movement edge again for every possible child. The
follower also reuses its physical tile descriptions for geometry and
track masks. Trace reconstruction still resolves the original edge,
including skipped aqueduct tiles; the shared road search is unchanged.

On a native Luanti async worker, eight alternating batches of 22 searches
with real map reads and trace reconstruction took a median **3.47 s →
2.11 s** (about 39% less elapsed time). The routes, costs, search limits
and closed-node counts matched on those searches. Separate tests cover
locks, aqueducts, alternate berths and commercial service with a saved
cargo load. This fixture measures route planning, not the whole
simulation or the rendering rate. To rerun it against the pre-change
version:

```sh
tests/ship_yapf_perf_native.sh "$(command -v luantiserver)" \
  f38b4d8d934b3904555b24f8a9a3570dfac46183 /tmp/ship-routing-bench
```

### Share road tile records inside each YAPF segment

The road cost loop now passes the tile description it already read to
the stock cost, destination and follower checks. Reversal and entrance
helpers no longer allocate closures for each tile. Nothing is cached
between searches, and the follower still reads its destination afresh,
including access, roadworks, tram directions, gradients and structures.

In a native Luanti async worker on the 256×256 mixed-company fixture,
median elapsed time for batches of 128 complete bus route searches
fell from **41.4 to 26.4 ms**. Across twelve alternating runs, every
selected path, direction, cost and vehicle motion sample matched
exactly. This measures route searches, not all moving-vehicle updates
or frame rate. To rerun on a copied benchmark checkpoint:

```sh
tests/road_yapf_perf_native.sh "$(command -v luantiserver)" \
  cbaa1785abe27a42d71490202ed5cdcf8a347f93 /path/to/128-bus-checkpoint.chk /tmp/road-routing-bench
```

## Stock vehicle cargo age countdown

Most vehicle ticks only decrement the cargo-aging counter. The Lua
loading adapter follows that fast path without allocating a packet
closure or dividing/modulo on every tick. When the counter wraps it
still ages all onboard, unloading, and reserved cargo, caps each age
at 65,535, and handles more than one expiration in the input interval.

```sh
LUANTTD_CARGO_AGE_ONLY=1 tests/road_fleet_perf_native.sh luantiserver   2a3d80ba4f6f1c851034a10bad29430905e63e55 /tmp/luanttd-age-bench
```

Twelve alternating native async batches of 568,320 cargo age calls on
192 loaded vehicles decreased median CPU time from 76.96 to 20.01 ms.
Every counter and onboard, unloading, and reserved age matched. The
separate 192-bus simulation test compares complete durable and
visual-motion state; this timing is for cargo aging alone, not a
claim about entire fleet stepping or frame rate. Whole-fleet timing
varied in both directions across repeated runs.

### Keep the viewport responsive during periodic checkpoint encoding

The campaign owner can answer its two bounded presentation requests
between encoding chunks. It still reads from the latest completed
simulation day and can only interpolate up to the end of that day's
recorded trajectory. It doesn't step vehicles or change the checkpoint
while projecting a view. Commands, explicit saves, and paid-action
receipts still follow the separate, normal owner turn. A pending
command is never bypassed. Compression and atomic disk replacement
remain synchronous.

In two alternating pairs of ordinary native 1024×1024 sessions at 1×,
the median response time for views requested during an autosave fell
from **1.11 s to 54 ms** (4 baseline and 30 candidate observations;
slowest **1.39 s vs 429 ms**). All four sessions ended on the same
simulation day and tick. Save CPU itself still took roughly 1.1–1.5 s,
and a large simulation day can still delay a view. This is host/worker
latency, not an FPS or whole-fleet smoothness measurement.

The deterministic owner-loop test covers sequence, interpolation,
and command/save ordering. To measure the receipt and encode times on
a copied stock generated checkpoint:

```sh
tests/campaign_autosave_view_native.sh luantiserver 5d35bf8 \
  /path/to/fixture-world /path/to/fixture.conf /path/to/new-bench-dir
```

### Use native bit rotations for the stock simulation RNG

The shared stock generator uses LuaJIT's XOR and rotate instructions
when available. Reducing signed intermediate values modulo 2³²
preserves both saved unsigned words. Plain Lua uses the existing
arithmetic fallback. The formula is OpenTTD 16.0-RC1's
`Randomizer::Next`, not a different generator or a new draw order.

In a native Luanti async VM, median CPU time for 262,144 draws went
from **112.38 to 2.34 ms** over twelve alternating batches. Checksums,
final states and 65,536 individually compared steps matched; both
paths also match boundary vectors from the compiled 16.0-RC1 function.
This measures only RNG cost, not the full simulation day.

```sh
tests/stock_rng_perf_native.sh luantiserver 51c69d2 /tmp/stock-rng-bench
```

### Dense station packet queues

OpenTTD 16.0-RC1's `StationCargoList::ShiftCargo` erases the
consumed FIFO prefix without shifting later packets after each move.
The Lua adapter now compacts a long array once per multi-packet load
or reservation. Short queues and a single complete or partial head
still use the existing path. Packet order, identity, split age and
feeder share, callback order, and remaining station stock are unchanged.

Two native Luanti worker comparisons of 31 independent 1,536-packet
queues measured full-load reservations at **1.62 → 0.28 ms** and
**1.72 → 0.30 ms** CPU. Results matched for gradual pickup and full
reservations in passenger, mail, and goods across empty, short and
long queues. These are loading-kernel timings, not whole-day or FPS
figures. Native road, rail, ferry, air, and save/reload smoke tests
ran against the same candidate.

```sh
tests/cargo_queue_perf_native.sh luantiserver 6228420 /tmp/cargo-queue-bench
```
