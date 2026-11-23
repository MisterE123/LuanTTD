# Farm worker optimization and RC1 checks

Farm planting, the clear-tile loop, stations, and the shared RNG retain
one simulation owner. This change avoids allocating transient tile
classification tables, avoids rereading the neighbor of a fence that
already exists, and reads adjacent corner heights from one calculated
index instead of calculating four more. It does not cache old terrain or
schedule farm state on another thread.

## Measurements

Linux process CPU, quiet generated worlds (seed 1751), 50 simulated days,
two runs each in alternating order, before adapting terrain eligibility
to RC1. The optimized and reference checkpoints were byte-identical
at the end of each measured world.

| Map | Farms | Mean CPU ms per day, before → after | Field maintenance CPU seconds, before → after |
| --- | ---: | ---: | ---: |
| 128×128 | 4 | 80.8 → 51.5 | 0.89 → 0.51 |
| 256×256 | 13 | 337.5 → 200.1 | 3.51 → 1.67 |

These are instrumented CPU timings, not frame-rate claims. The larger
world had no routes; random planting took roughly four milliseconds
in all 50 game days. Reproduce with
`lua5.1 tools/profile_farm_worker.lua 256 50 measure`.

## Pinned behavior

Comparison with OpenTTD 16.0-RC1 identified a pre-existing difference
in rough ground. Rough terrain does not count toward a plot's minimum
eligibility, but can be planted once the plot passes. Generated farm
placement now uses actual map void edges and the existing farm
classification prevents the tree generator from planting over crops.
The existing worker's occupied/slope checks still observe current world
state. Orphan crops return to density-2 grass and reach density 3 on
the original counter.

The [planting comparison](../tests/farm_factory_fields_upstream.py)
compiles the actual RC1 functions to compare RNG draws and exact tile
and fence writes. The [maintenance comparison](../tests/farm_clear_rc1_upstream.py)
compiles the stock clear-tile loop and compares fences, crop stages,
editor behavior, orphan expiry and regrowth with the native board.
Those are scoped source comparisons, not a claim that every OpenTTD
industry, climate map, sound, or NewGRF callback is mounted.
