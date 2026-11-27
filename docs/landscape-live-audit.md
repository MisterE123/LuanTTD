# Sparse landscape scheduling: live callback audit

**Status: detached proof, not a production mount.** The stock OpenTTD 14.1
`src/landscape.cpp::RunTileLoop` order is already ported; this work does
not add more stock tile behaviors or change a release. It asks whether
the **current LuanTTD** callback chain can omit visits proved inert while
keeping the stock tile order, shared RNG, and all game ticks.

## What actually runs

In `sim.lua::stock_station_day`, `town_passenger_runtime.day` advances
the shared cursor by a **single** tick, 74 times per game day. Inside
each tile callback the order is coastal, coal, the selected secondary
freight adapter, then house. The non-stock-service paid-passenger
branch and house-only batch are separate call sites: preserve their
existing rating/cursor visibility, not just the final clock.

| Current owner | Keep scheduled | Safe omissions and caveats |
|---|---|---|
| House supply + town growth | Any physical tile with `t.house`, including incomplete growth, even when no passenger or mail stop is in range. | No house flag means no house callback. Completed houses have a stock unconditional tile RNG draw, optional lift RNG and stock passenger **and mail** draws (even with no mail route). Incomplete houses update counters, visual stages, town population; completion uses the old tick cursor plus one. Lazy legacy house stamping is a write. Initial town roots/parts and new growth cannot be inferred from rendered art. |
| Coastal wet/dry | `water_flood_world.visit` after the same native prefilter, iff its pure `Flood.visit` quote has at least one change. | Bare/ramped sea with no legal clear target, stable supported shores and fixed river/canal are inert *now*, not forever. Do not broadly skip void: generated `stock_void` records are stored with water terrain, `W.board` recognizes their stock active behavior, and tile 0 has the first slot every 256th tick. Coastal stations may be sources while remaining protected from replacement; let current classes decide. The result depends on class/ownership/cover/layer/grade of an eight-neighbor footprint. Shrinking this blanket to only present shore tiles is wrong. |
| Coal mine/power (road, paid rail and ship use one coal binding) | All tiles of the binding's non-removed industry footprint. | Outside that map-key set the callback returns before looking up options. Some finished power tiles are inert; conservatively keep all footprint tiles. Coal construction progresses before the editor check. Shared production and distribution are distinct phases: an earlier visit can drain waiting coal so a later one changes behavior without removing any footprint membership. |
| Forest/sawmill (road + optional shared goods-by-rail) | All tiles of the bound industry footprint, even if stock is empty. | Outside it the callback is immediately inert. The replay ledger writes `landscape_tick`/`visited[key]` before the tile kernel. Construction and transitions 16↔17 can matter independently of a waiting-cargo threshold. Same-direction cargo dispatch order remains source order. |
| Farm/factory | All current footprint tiles **and every persisted field record**, even a field which would now fail occupancy/grade checks. | `road_farm_service.B.tile_visit` performs field work first. A stale field visit removes the record and publishes dirtiness. Fields age, inspect cardinal neighbors to fence, or revert after their producer disappears. Per-tick farm production can randomly plant an area and remove woods; new plain fields still need future visits. No field records outside the footprint may be omitted on the assumption “not an industry.” |
| Oil/refinery (road and optional paid rail) | All current footprint tiles; keep independently clocked animations. | Oil wells completing a visit or at finished gfx 29 cannot be decided on visible inventory; a finished gfx 29 well can draw RNG and start the animation with no dispatch. `oil.binding` animates sorted IDs every eighth tick, with RNG at intermediate frames; monthly closure can clear an industry footprint. |
| Current clear/road/rail/airport/objects/ordinary trees | No independent per-tile callback unless selected above (e.g. a field or a flood dependency). | Do not treat “inert here” as stock parity: full OpenTTD 14.1 dispatches `TileLoop_Clear` (grass counters/editor RNG and ambient), `TileLoop_Trees` (cycle, growth, RNG and spreading), structure-specific loops and broader shore classes. These are outside the current supported callback chain; adding any requires registration and fresh proof. |

Between landscape ticks, **do not skip** the paid multimode station scans
and arrivals, road loading/traffic/crossings/faults, freight vehicle
settlement, town timers/growth, station/mail/freight ratings and packet
truncation, industry producers, farm field attempts, and oil animations.
The current order is encoded in `stock_station_day`: the growth-mounted
path delays passenger/mail rating until after vehicle/commercial work
and the town growth tick; the nongrowth path rates before tile visits.
Per-day fault/auto-service RNG and growth preparation happen before the
day, and month-end producer changes/legacy town construction afterwards.
Flood effects, catchment updates and queue order all observe the
same owner state and RNG. It is **not safe** to run different tile
owners in different workers and merge their effects later. Worldgen's
separate pre-town river widening/flood `B.run_tile_loop` handoff is not
a live callback to replace.

## The invalidation boundary

1. Owner track coordinates in **stock zero-based stride**, not native
   `Sim.id - 1` unless the map is a matching square/rectangle. Example:
   authored 48×36 uses a 64×64 source lattice; unmapped slots are inert.
   Generated 128×128 uses the complete lattice. Save/reload rebuilds the
   index token from authoritative registers, never serializes a heap.
2. On a coastal mutation re-evaluate the changed tile and its eight
   neighbors immediately, before the next logical slot (terrain
   changes invalidate all dirty tiles touching changed corners, then
   their neighbors). Re-register a source if its remaining slot is
   still ahead; reactivation of an already-passed slot waits a cycle.
   Quote only: never mutate water or serialize the whole coast to decide.
3. House commit/removal, stock industry creation/closure and tile
   footprints, field plant/removal, and any changed coastal class input
   must publish **explicit owner-side membership invalidations**. The
   current visuals append `s.changed` for coast/house/field effects,
   but many external commands return dirty lists (road/rail/ship,
   object pruning and terraforming), change layer maps, or update
   topology separately. `s.topology` lacks coordinates and does not
   cover every membership mutation; a visual journal is not an
   authoritative dependency contract. Rebind daily coal/secondary
   industry maps only at their current day boundary; a field introduced
   by a per-tick producer must be visible before the next tick.
4. Important external writers include `Sim.build` and its clear
   path, `Sim.landscape` (dirty tiles returned from propagated corners),
   `ship_network` (canal, lock, aqueduct, dock/depot and removal),
   bridge/tunnel layer writers on road and rail, crossing construction,
   tram/airport construction and removal, town growth and legacy
   monthly housing, and the coal/timber/farm/oil preview workbenches,
   including monthly oil sweep. Also handle settings/profile changes
   and restored saves. Disabling a feature does not authorize dropping
   cleanup or saved construction that the current adapter still runs.
5. Mount first only in a closed test profile declaring complete
   write ownership. Validate bounded active size **before** entering
   sparse execution, keep dense fallback for missing hooks/unknown
   features, and design an exact suffix fallback for unforeseen
   inflation; never flush/replay a partially written tick. Cache a
   frontier/active set and update from writes rather than rebuild it
   from dense tiles per tick. Dense `s.tiles`, monthly upkeep scanning
   and large latent virgin coastal/vegetation classes are **separate**
   scalability problems. No current 4096 playable claim.

## Detached scheduler and evidence

`openttd/landscape_dynamic.lua` consumes the prior exact
`landscape_index`. `D = Factory(Index).new(log_x, log_z)`;
`D.set(stock_id, present)` can run synchronously in a before-tick,
tile, or after-tick callback. `D.advance(clock, ticks, visit[,before[,after]])`
dispatches `visit(id, tick, slot, x, z)`; `after` has the updated
one-tick clock, while the batch variant without it exposes the same
initial clock during the loop as the legacy one-call batch.
`D.advance` returns dispatched count/peak pending list size.
The owner promises every required mutation is reported before the
next slot and keeps the clock read-only during dispatch. The local
calculation needs no tile-wide array: one rank and at most one heap
entry per active tile (up to 65,536), one head rank hint, the existing
bounded square-root rank cache, and serial callbacks. Pending removal
is immediate, not a growing tombstone list. It still iterates gameplay
ticks, and compiles a fresh pending heap for a window; use day-sized
interactive windows in any future production mount. Callback failure
is terminal for the tentative owner session; there is no rollback of
arbitrary game writes. To parallelize, use workers only for bounded,
immutable candidate derivation and accept after checking ownership and
revisions; do not mutate the live map or consume authoritative RNG
from an async worker.

```sh
lua5.1 tests/landscape_dynamic.lua
lua5.1 tests/landscape_dynamic_live_audit.lua
python3 tests/landscape_index_upstream.py /path/to/openttd-14.1 lua5.1
```

The source C++ oracle remains the previous SHA-pinned test for
`RunTileLoop`; the mutation-aware proof compares the same source walk
through `H.advance_houses`. Seven clock/shape fixtures (including
rectangles, near safe-integer limit, and saved noncanonical head) cover
over 22,000 exact event/slot/head comparisons. A real conservative
128² world-flood witness has a sea-activated neighbor 18 slots later
in the **same tick**: both effects must be tick 256. Snapshot-only
scheduling delays the second to tick 512, and in the reverse order a
newly activated tile whose slot already passed must not run early. A
graded shore with no support also dries on its own slot and leaves
the scheduler immediately.

A separate harness substitutes only the walker in a test-local
`Sim.daily` load. It compares every persisted field in both states,
after every day and after save-shaped deep-copy/rebind (not native SQLite): generated
128² seed 1751 coast, house/mail, mixed coal and timber; authored
farm/factory/fields, oil/refinery/animation, and actual transport-backed
town growth. The farm test introduces one field through the real field
writer and proves the normal source loop visits it; it does not wait for
a random planting event. The 128² fixture selected 754 of 56,832 stock
slots across 12 days and preserved carried river head, RNG, coal and
timber state. It makes **no performance claim** for the per-tick splice
used only to audit the existing callback shape. The test-only harness
uses visual dirty appends within the adopted fixtures; it does not
claim coverage for arbitrary external tool edits or for a new
fully stock multiplayer game.

## Landscape cursor reference for optimization

`tests/landscape_tile_loop_rc1.py` extracts `RunTileLoop` unchanged
from the pinned 16.0-RC1 source. It compares the binary tile-ID stream
and final cursor/counter with the Lua owner, including initialization
and live timing at tile-zero boundaries. The 100 reference cases cover
every supported pair of axis sizes, from 64×64 through 4096×4096,
and compare 2,076,800 actual tile visits, not aggregate counts.
This tests the cursor order, not the performance of an entire 4096² game.

```sh
python3 tests/landscape_tile_loop_rc1.py /path/to/OpenTTD-16.0-RC1 --lua lua5.1
```
