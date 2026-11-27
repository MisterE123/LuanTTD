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
