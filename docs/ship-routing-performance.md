# Ship routing on the world worker

## Local water-region invalidation after a tide

OpenTTD 16.0-RC1 `InvalidateWaterRegion` (in
`src/pathfinder/water_regions.cpp`) dirties the region containing a
changed tile. At an edge it also dirties the regions that read across
that edge. The LuanTTD region solver already provided this operation,
but the ship controllers rebuilt their entire region cache whenever
the global topology revision changed.

Passenger, coal and oil ship controllers now use the exact list of
changed tiles from plain coastal floods and dry-outs. Only the region
cache is retained, under the same live-reading water board. Rebuilds
are still lazy. Unknown or interleaved edits, changes to facilities
or spans, and other non-plain coastal changes still invalidate the
whole cache. In-flight route validation, ship orders, and the stock
pathfinder's costs and ties are unchanged.

Two native 128×128 comparisons each ran four alternating batches of
20 real ferry route quotes after actual floods. Four of the floods in
each batch affected regions read by the route search, including
cross-region edges; the rest were remote. Every returned quote and
topology revision matched. Median CPU across both comparisons was
about **953 → 109 ms per 20 quotes**. Water tile/track reads dropped
from **73,960 to 13,800**, and the worker no longer discarded all 20
previously warmed region maps. This is a route-planning measurement,
not total day- or frame-time improvement.

The direct integration regression opens a navigable tile on one side
of a region edge, then observes the reciprocal edge rebuild without
discarding the index. Another plain tide cannot mask an earlier
unclassified revision.

```sh
tests/ship_regions_tide_perf_native.sh luantiserver 33635c0 ../ship-tide-perf
```

## Build fully open sea regions without a tile-by-tile flood fill

The regular water board can prove that every tile in a complete
16×16 region is ordinary sea and all its shared corner heights match.
That gives exactly one connected patch. Interior follower probes
cannot add a patch or find an aqueduct in such a region; only the
64 outward edges can affect connectivity. Each edge still uses the
same stock ship follower. Any slope, coast, rock, facility, partial
rectangle, or decorated routing board uses the full labeling process.

The native differential test checked every patch label, exact edge bit
and ordered neighbor in full and rectangular extents. It included
locks, aqueducts, slopes, and rocks, as well as adding a rock inside
a previously warmed region. In the 256×256 test with 245 provably
flat-sea regions, one cold build took median **1,584 → 86 ms** on the
final four alternating pairs. Follower calls fell from **785,898 to
48,938**. A second fixture ran 20 cold first-route ferry quotes across
opposite shores in 128×128 maps. Median CPU was **4.79 s → 0.61 s**
per batch, with identical quotes. These are scoped cold-cache tests;
coast-only trips do not see that speedup.

```sh
tests/ship_solid_region_perf_native.sh luantiserver ../solid-sea-perf
```

## Sample each tile once when rebuilding a mixed water region

Sampling the native board resolves shared corner heights, bridge layers
and water facilities. In a mixed 16×16 region, the stock flood fill
asks about the same parcel from several headings. The worker now shares
the track mask and tile descriptor only for the duration of one region
rebuild. It still runs the same follower in the same order for every
track direction. Neighboring tiles and far aqueduct mouths are sampled
on first use; nothing from the sampler survives to the next rebuild.

The native worker benchmark compared every patch label, edge bit and
ordered neighbor before and after adding a rock at a region corner.
Across four alternating batches of 64 mixed regions, descriptor reads
went from **405,484 to 20,180** and median cold-build CPU from
**403 to 155 ms**. This measures rebuilding water regions, not the
whole simulation or frame rate.

## Keep the checked sailing leg through unrelated floods

The worker previously verified every remaining edge of an active route
after any map topology revision. It now remembers the exact validated
suffix in the ship controller's temporary cache. A proven plain tide
keeps that check only if its changed parcels do not touch any tile of
the suffix. A touched route, a replacement route, a cursor moving back
before that suffix, or an unknown edit still runs the full check. Movement,
orders, and route selection are unchanged; the proof is not serialized.

An alternating native replay advanced a ferry 40 times after 40 real
remote floods while it sailed an open-water route. Every saved ferry
value matched at every step. Follower calls dropped from **2,080 to
52** per batch and median CPU was about **4.4 → 0.5 ms** across the
two runs. Inserting a rock on the verified route still blocked the
ferry with the original network-change error.

```sh
tests/ship_checked_leg_perf_native.sh luantiserver d0ece7c ../live-ship-leg-perf
```

## Avoid testing for berths on ordinary sailing tiles

The stock destination predicate requires a neighboring physical dock or
oil-rig facility. The regular world board now checks for such a raw
record before constructing full terrain, bridge and navigation
descriptors. A plausible neighbor still goes through the same live
berth checks; decorated test or planning boards stay on the full path.

A headless ferry crossing matched all 439 sampled ferry states and its
arrival. It made the same 468 follower calls, but terrain descriptor
reads dropped from **41,958 to 23,934**. Across eight alternating pairs of
voyages median movement CPU was **64 → 57 ms**. Individual measurements
overlapped. This covers worker movement, not frame rate.

```sh
tests/ship_berth_perf_native.sh luantiserver 78edeed ../ship-berth-perf
```

## Leave unreachable neighboring water regions unopened

When the port's 16×16 region already reports no exit on a side,
the neighboring side cannot share a navigable edge. Skip building that
neighbor's descriptor. Boundary edits still invalidate both sides;
a previously closed connection appears on the next search.

For a cold 1024×128 canal test, batches of 16 route builds returned
identical routes with 788,144 → 276,144 terrain descriptor reads and
approximately 176 → 113 ms median LuaJIT CPU across four pairs.
This is a route-search benchmark, not a whole-game speed claim.
The test also opens a previously dry boundary and checks the new route.

```sh
git show 377a704:mods/luanttd_core/openttd/ship_regions.lua >/tmp/old-ship-region.lua
luajit tests/ship_canal_neighbor_profile.lua /tmp/old-ship-region.lua
```
