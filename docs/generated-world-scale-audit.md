# Generated campaign scale audit

The 64² campaign remains the default. The stock-generated 128² option
now uses the production landscape clock; this audit records the earlier
scale constraints and the headless comparison. For the actual playable
option, see [the generated campaign guide](generated-campaign.md).

## What actually ran

```sh
lua5.1 tests/generated_world_scale.lua /path/to/luanti/builtin/common/serialize.lua
```

The final argument is optional. With it the fixture exercises the
installed Luanti serializer, round-trips the 128² campaign, and advances
the original and restored campaigns on the same stock cursor/RNG.
Measurements below are Linux Lua 5.1 CPU times, not graphical FPS,
Luanti SQLite latency, or a server load test.

| Seed 1751, default mixed industry density, mountainous relief | 64×64, no rivers | 128×128, low rivers |
|---|---:|---:|
| Real host terrain to forest generation | ~0.5 s | ~2.7 s |
| Retained Lua heap above fixture baseline | 1.72 MiB | 6.83 MiB |
| Full serialized opening campaign | ~202 KB | ~857–873 KB |
| Serialize / deserialize | ~0.05 / 0.01 s | ~0.22–0.27 / 0.04–0.05 s |
| 24 headless stock simulation days | ~0.5 s | ~1.4 s |
| Actual accepted towns / industries / landmarks / forest tiles | 2 / 3 / 3 / 403 | 8 / 13 / 8 / 3,260 |
| Rivers | 0 | 2 |

The test passes actual TerraGenesis, river, rough/rocks, town, mixed
coal/timber industry, landmark and tree stages in order. It tracks each
stage's RNG words. This is still the native bounded house/industry
roster, not an unrestricted OpenTTD scenario.

Seed 1751's 128² river generation leaves landscape head **6090**. The
old six-plus-six bootstrap rejected it. With the production seven-plus-
seven clock, official LFSR visits all **16,384** cells exactly once in 256
game ticks, returns to the initial head, then runs the real stock game
loops at 74 ticks/day. Actual road construction and two stops on the far
side yield directed YAPF/motion from tile **8935** to **8942**, with 113
frames and separate station IDs 1/2. Serialized restart keeps that road,
station anchor and clock. The next day agrees on the cursor and both
shared economy RNG words. No native client or payment was part of this
fixture.

The same 128² river raster also mounts independently behind detached
`WorldStorage` and `TerrainStream`: no overlay chunks for the pristine
base, equal 3D edge samples across the X=65 seam, 134 bytes for the base
identity save, and a bounded 5,185-byte 32² snapshot payload (before
protocol fields). This deliberately does not replace campaign terrain
authority.

## 128² mount checklist and remaining load tests

1. **Fresh startup and restore.** Change the `generated_campaign.landscape`
   and `init.lua` gates to accept only explicitly enabled square 64/128
   profiles. Keep the existing 64 default and Harbor's authored geometry.
   Save the selected dimensions; restore from those, not current
   settings. On decode validate version, dimensions, the dense
   `width × depth` tile list and `(width+1) × (depth+1)` corner-grid shape.
   Install `Sim.W,H` before decoding/using any stored tile IDs or rebuilding
   topology indexes. Do not reinterpret an old save as a new width.
2. **The real landscape clock.** `town_passenger_runtime.start` must
   derive axis exponents for generated maps and keep the real river head:
   6/6 for 64², 7/7 for 128². On restore, verify saved logs and in-range
   head as well as the state profile. Leave the smaller specialty scenarios’
   deliberate 64² padded clock intact. The port in
   `openttd/town_passengers.lua` already supports all stock exponents.
3. **Measure gameplay, not just generation.** Launch two fresh native
   Linux worlds without moving the default. Have a client fly across
   logical 64/65 and a far LFSR region, take a far high tile route through
   the real controls, inspect coast/river geometry, pay one fare or
   freight delivery, and restart the same SQLite world. Exercise at
   least one overnight/headless save tick and 4× speed with real traffic;
   measure save stalls and daily ticks. Keep lab workbenches and old
   starter instructions guarded from generated worlds. Right now the
   fixture proves stock path and save addressing, not the camera or net
   client experience.
4. **Don't combine with a storage rewrite.** Keep the existing dense
   backing only for this 128 experiment; it is tractable at the measured
   size. The fixed camera y=20 survey jump and ascent cap y=66 are
   sufficient for regular default 128 relief but not arbitrary heights:
   derive survey height from destination top and the flight ceiling from
   actual profile before exposing higher relief or larger map sizes.

## Assumptions and the actual scale wall

| Area | Current behaviour and large-world implications |
|---|---|
| World authority | The generated adapter allocates one table per tile and a dense numeric corner plane. The process-global `Sim.W,H` makes row-major IDs valid for one world at a time. `s.tiles[id]` and direct nested writes are widespread. Replacing it with just a sparse proxy is not safe: Lua 5.1 `ipairs` stops at holes and serializer/traversals won't see implicit values. |
| IDs | A Sim tile ID is **one-based** `(z-1)*width+x`; stock ID and WorldStorage's tile ID are **zero-based**. WorldStorage's corner stride is width+1 and is not the tile stride. Stations and vehicles are separate increasing numeric IDs, not packed tile IDs. Their live pools do not enforce vanilla station-ID limits; the importer does bound station types' encoded fields to uint16. 128² is well within all current numeric ranges. Do not reuse a station ID as a tile key as maps pass 65,535 tiles. |
| Save | `init.lua::api.save` serializes the **entire** campaign, then sets one mod-storage string on the main thread. It runs every 8 seconds online or in the enabled offline economy, plus joins, leaves and some build/dispatch actions. Serialized output is not byte-identical across unrelated table-allocation orders; deterministic state and RNG are the right assertions. Serialization itself temporarily allocates traversal/rope/output data in addition to retained authority. |
| Simulation | The correct world-size LFSR is `area/256` tiles per stock tick, 74 ticks/day. On 128² this is 4,736 tile visits/day, on 4096² **4,849,664**. The day loop inspects live house/coast/industry eligibility at each tile; no render culling changes this. Company upkeep scans all tiles monthly. Road junction caches rebuild with two whole-map scans on topology change; the legacy rail alternate path scans closed signals. Frontend guide phase and several boot/recovery scans are also dense. |
| Player and native map | Renderer map generation is lazy by Luanti mapgen region, with 2 native nodes per logical tile and a cosmetic horizon. No full native map is eagerly generated; per area it iterates columns up to the global land/bridge `top_bound`, and a changed-tile refresh only swaps already loaded nodes. Large relief magnifies this work. Spawn uses a real town's height, but `/survey` uses y=20. The jump map shows a bounded 20×15 viewport. Site and station HUD labels scan all records per player before distance rejection; vehicle frame code computes poses for all fleet records before culling the actual mesh. |
| Routing and cache | Route board adapters already read dynamic dimensions. Stock road/rail YAPF cap defaults to 10,000 search nodes, with exact route motion frames retained per active leg. Water regions allocate lazily but their cache is unbounded across travel. None of these facts demonstrates a well-performing thousand-vehicle game. |
| Detached sparse/async | `WorldStorage` packs base identity plus explicit corner/32-bit tile-word changes. `TerrainStream` renders bounded windows; the [explicitly promoted detached schema](terrain-river-stream.md) now distinguishes river grade and preserves the source byte. `world_async.lua` runs actual Luanti worker jobs only for bounded snapshots and terrain rasters/plans; the broker validates world/revision/ticket, authorizes and applies on the owner thread. A single global revision can reject even an independent outstanding region after another edit. No normal campaign mounts these workers or stores its dynamic world in this detached store. |

Keeping measured dense costs per cell to 4096² would imply roughly
**6.8 GiB retained Lua memory** and **0.8 GiB of campaign text per
save**, before allocator/serializer peaks, active route frames, the
engine, or more elaborate state. This is an order-of-magnitude
extrapolation, not a memory limit or measurement of a 4096² campaign.
Current memory and full serialization are **O(area)** with a high
constant; reducing visual draw distance does not address either.

## Next scale architecture

* Keep a packed stock height raster (one byte per tile: 16 MiB at
  4096²). Make typed ground/river/forest raster data compact per region
  or derive it from versioned seed+generation data, never duplicate a
  Lua table per cell. Chunk memory is bounded by resident cache and live
  edits/objects, not world-size copies. Initial trees can cover a
  substantial fraction of the map: store simple forest cover in compact
  fields rather than assuming it is sparse.
* Add explicit owner accessors and transactional chunk writes, plus
  indexes for facilities, junctions, signals, influence/catchment and
  active/dirty landscape cells. Maintain stable stock tile IDs and
  ordering. Persist changed chunk pages and separate pool/cursor data;
  add recovery that restores a region without mixed generations.
* Profile exact stock landscape dispatch from active events: preserve
  the LFSR ordering, tick index and RNG when skipping inert cells; verify
  against full stepping with cargo, coast and town effects. Active coast,
  construction and industry count may still bound the design. Spatially
  index vehicle presentation separately from full-world simulation.
* Only then feed immutable revisioned regions to real workers for
  raster/path/terrain jobs. Replace global invalidation with verified
  read-region revisions if disjoint jobs contend. Keep traffic,
  finance, overlap resolution and commits on the authoritative thread.
  Check fast worker/slow worker schedules preserve exact replay before
  advertising whole-world background simulation.

No 4096² playable campaign or multithreaded economy is qualified by this
audit. Existing packed source generation and read-only exploration are
separate achievements.
