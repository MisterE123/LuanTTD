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

## Mixed industry production ticks

The farm planting hook is bound once per active ledger, rather than
allocated on every production tick. Oil's shared production routine
no longer copies its options table merely to suppress an ambient
sound. As in RC1's `ProduceIndustryGoods`, it still takes the scheduled
random draw even if no sound plays. Industry ID order, production
counters, RNG state, and farm placement attempts are unchanged.

Two native Luanti worker comparisons of 768 mixed industries measured
196,608 production visits per batch. After warm-up, median CPU dropped
from **97.0 to 75.8 ms** and **84.7 to 67.6 ms** in the two series.
The states matched after every batch, including all 38,730 random draws,
458 ambient emissions, and 5,970 farm-tile probes. A separate 1024×1024
campaign comparison matched every durable field and table alias at
the same finished day, excluding wall-clock presentation fraction.
Seven real farm, timber, and oil freight services also delivered
265 units for $3,869 across a native restart without double payment.

```sh
tests/industry_tick_perf_native.sh luantiserver a1d8907 /tmp/industry-tick-bench
```

### Ordered industry production dispatch

The native owner now dispatches the already ordered industries as one batch
per source tick. It reuses transient production options and avoids looking up
each industry twice. Every live industry still executes its stock production
rules at its original position in the RNG stream; the phase guards and
per-industry replay ledger are unchanged.

On Luanti 5.15.2's async VM, 768 mixed industries over 12 alternating
256-tick batches took a median of 12.08–12.11 ms before and 8.94–10.10 ms
after (17–26% less CPU in this isolated phase). Each batch compared the full
production state, ledger, ambient events and field-attempt RNG. This is not a
26% gain for the whole simulation. A focused farm/factory and timber cargo
regression tests production, delivery, payment and restart as separate steps.
