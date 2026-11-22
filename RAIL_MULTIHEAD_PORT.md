# OpenTTD 14.1 stock reciprocal rail heads

The stock Manley–Morel DMU #11 is a single purchased diesel multiple
unit with **two** powered, independently carrying physical vehicles. It
is not a locomotive and a generic interchangeable passenger carriage.
The 1956-era temperate design uses the original availability calendar,
including seed-dependent introduction when started early.

| Datum | Original #11 |
|---|---:|
| Base purchase | 17,187 |
| Physical parts in vehicle pool / independent lead unit number | 2 / 1 |
| Front/rear sprite index | 8 / 9 |
| Weight (each / coupled empty / coupled full) | 32 / 64 / 68 t |
| Length (each / coupled) | 8 / 16 stock units |
| Seats (per body / total) | 38 / 76 |
| Gradual capacity (per physical cargo store / coupled station scan) | 5 / 10 |
| Power (per body / total) | 300 / 600 hp |
| Maximum | 112 km/h |
| Actual annual running cost (8-bit fraction, medium) | 436,800 |
| Physical life / design life | 12 / 30 years |

`rail_roster.physical_parts({11})` returns two independently situated
parts with reciprocal `role="front"|"rear"` and one-based physical
`mate` indices. A wagon sequence placed behind the front is normalized
so the rear is the last body before the next leading engine, exactly as
stock `NormaliseDualHeads`. A second logical #11 means a second pair,
not an arbitrary separately bought rear. Cargo input can be a logical
`{stock_id=11,cargo_count=...,rear_cargo_count=...}` or the validated
explicit physical chain; each body separately rounds stock cargo weight,
uses its own five-unit gradual load slice and remaining space, and
contributes its powered mass to effort. The build charges the whole price
once: each part's stored value is the stock integer half (8,593), not
the build charge. The live rail running routine divides the odd stock
85 factor per part before multiplication (42 each, not 85 combined).

The live depot offers the authentic pair or that pair with one standard
40-seat carriage between its two powered halves. The three-body train
costs $19,116, carries 116 passengers, weighs 89 t empty/95 t full, and
offers up to 15 seats per actual gradual loading round. Its 600 hp and
running cost are the same as the pair. There is one station visit and
one payment accumulator. For full-load operation, the stock linked
group reserves the front then the reciprocal rear before the carriage.
Actual loading and unloading scan front, carriage, rear in physical
order. The train's 24 units of length also count for stock overhang
and vehicle-pool accounting.

These formations use the ordinary single-company two-platform paid
passenger shuttle. Further wagons, multiple simultaneous DMUs,
paired-train service with a DMU, refits and other cargo are not enabled.
The depot requires the owned paid rail workbench, stock public sale
availability, both dedicated native art files and the loader. To start
in 1960, set `bayline_stock_bus_catalog=true` and
`bayline_stock_bus_start_year=1960` before creating a fresh campaign.
The ordinary 1950 campaign cannot buy it ahead of the original calendar.

Native trials save with passengers aboard every body, restart Luanti
with SQLite, and recheck separate cargo lists, actual tiles, physical
mesh poses, outward cab orientations and one payment per visit. The
controlled two-body and three-body routes each reached 112 km/h. They
settled $364 and $395 respectively, with $141 and $145 running costs.
The focused three-body full-load test carries all 116 seats with three
actual origins and one $875 payout; the two-body test carries all 76
with a single $576 payout.

## Source verification

- `tests/rail_multihead_upstream.py` compiles pinned original
  `AddRearEngineToMultiheadedTrain`, `RemoveFromConsist`,
  `InsertInConsist` and `NormaliseDualHeads`, comparing 3,004 exact
  linked physical chain fixtures including mixed engine orders.
- `tests/rail_roster_upstream.py` compiles pinned price, part-power,
  purchase display weight/capacity, train caches, running and station
  waits. Its 7,500 cases contain 222,375 stock vehicle rows.
- `tests/rail_depot_fleet_upstream.py` covers 192,896 seeded original
  availability/intro/reliability snapshots.
- `tests/rail_multihead.lua` covers value/cargo split, per-body rounding,
  packed receipt shape, a private copy-save and unmounted quote rejection.
- `tests/rail_multihead_loading.lua [coach]` proves 76 or 116 real
  reservations, true separate origins and a copy-save while unloading.
- `BAYLINE_NATIVE_MANLEY=true BAYLINE_NATIVE_STEAM_START_YEAR=1960 bash
  tests/rail_owned_live_native.sh` checks the actual paid route through
  two dedicated Luanti processes and one native SQLite world. Replace
  `BAYLINE_NATIVE_MANLEY` with `BAYLINE_NATIVE_MANLEY_COACH` for the
  three-body route.
