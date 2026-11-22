# Stock temperate river world generation

This detached port follows OpenTTD 14.1
[landscape.cpp](https://github.com/OpenTTD/OpenTTD/blob/14.1/src/landscape.cpp)
from spring search to marked FIFO downhill/outlet search and ascending
lake-center lottery. It builds paths with stock AyStar and
[BinaryHeap](https://github.com/OpenTTD/OpenTTD/blob/14.1/src/pathfinder/npf/queue.cpp),
including neighbor order, tie handling, route draws, and the 10,000-node
budget. A short or unsuccessful river is not replaced with a hand-drawn
channel. The stock circular search can rewrite the same lake cell on
both sweeps, consuming its draw each time. Shore counts as MP_WATER
for flooding, but not as plain water in the river pathfinder.

Both width modes run the
[reflood and shoreline tile loop](https://github.com/OpenTTD/OpenTTD/blob/14.1/src/water_cmd.cpp)
on worldgen clear grass (density 3), sea, shore, river and void tiles.
Sea, single-raised-corner shore, and void actively flood; river does not
flood. Other shore dries on its visit if no permitted neighbor supports
it. This stage precedes clear tile initialization, towns, industry,
objects and trees. The stock stage calls 256 tile loops without
advancing the game tick; tile zero is therefore visited once per call.
The remaining visits follow stock LFSR order and return the new cursor,
not a fresh restart. The terrain here has no game structures, commerce,
vehicles, terrain foundations, or NewGRF events.

## Interface and limits

```lua
local R = dofile(openttd_path .. "/river_worldgen.lua")(Slope)
local output, stats = R.generate(base, TG.next_random, {
  original = false, terrain = Terrain,
  amount_of_rivers = 2, min_river_length = 16, river_route_random = 5,
})
```

- Use the preceding TerraGenesis terrain object and exact shared RNG
  checkpoint (`base.rng_after`). A new detached output retains its normal
  one-based `corner`, `tile` and `storage_options`, plus
  `river_bits(x,z)`, `river_tileloop_cursor`, and the advanced
  `rng_after`. The input is unchanged. `tile(x,z)` returns 54 for
  river, 38 for coast, 22 for sea, 7 for void, and 0 for clear. River
  water is not interchangeable with sea or a generic flooded tile; a
  native renderer and gameplay adapter must preserve this distinction.
  Disabling the stage (amount zero) returns the same object without any
  RNG, flood or tile-loop calls.
- Choose `original=false, terrain=Terrain` for full stock TerraGenesis
  width. This runs the source downhill width walk and
  [CmdTerraformLand](https://github.com/OpenTTD/OpenTTD/blob/14.1/src/terraform_cmd.cpp)
  on worldgen ground. `Terrain` is the existing stock
  `openttd/terrain.lua` kernel, not a separate approximation. The adapter
  uses exact source-domain corners (including void-edge heights but not
  a fictitious extra row), stores only edits, clears affected ordinary
  sea, river and coast before applying heights, and leaves the original
  board unchanged. No RNG is used by these commands themselves.
  `map_height_limit` is the same explicit setting supplied to TerraGenesis
  when nonzero; omit or pass 0 for stock automatic ceiling.
  Execution stats expose `terraform_commands`, `terraform_committed`,
  `terraform_corner_edits`, and `terraform_cleared_water`. Optional
  `terraform_trace(i,mask,up,success,changed,cleared,reason)` audits each
  executed/query-rejected command without touching gameplay settings.
- Choose `original=true` for the exact **LG_ORIGINAL width branch**,
  evaluated on the supplied landscape. It skips widening, but does not
  convert TerraGenesis terrain into a stock Original terrain generator.
  The wrapper refuses to guess a mode. Optional replacement
  `hooks.terraform`, `reflood`, and `run_tile_loop` require a distinct
  `hook_id`; these are for detached experiments and are not compared
  by the differential. Neither mode is yet mounted in the native game.
- Lower-level operations take zero-based linear index
  `i = x + z*width`, with one NW height (`corner_height`) distinct
  from minimum slope base. `R.create` accepts `tile`, `make_river`,
  `reflood` and `run_tile_loop` callbacks; width and height must be
  stock powers of two. Retain the post-stage LFSR cursor if chaining
  later stock tile loops into a full pipeline. This is a temperate
  initialization stage, not a runtime world flooding replacement.

## Verification

```sh
lua5.1 tests/river_worldgen.lua
python3 tests/river_worldgen_upstream.py /path/to/openttd-14.1 lua5.1
```

The differential compiles hash-pinned source functions with bounded
clear/water/void worldgen stubs. It evaluates the real widening callback
(versus no-op width in Original), recursive terraform, per-type ground
clear dispatch, top-level test and execution, reflood, and tile loops.
The seeded maps feed the Lua TerraGenesis corner raster and initial
clear, water, shore and void words into both implementations. That
raster is independently differential-tested by
`tests/terragenesis_upstream.py`. There are 156 source route/well/lake
cases and 15 complete output boards: 7 actual Original-width inputs,
6 actual TerraGenesis-width inputs, and 2 synthetic command/shore
fixtures. Each complete map checks packed words, surviving river random
bytes, both RNG words and the LFSR cursor. The wide-mode boards also
compare every corner height and the whole ordered terrain-command trace
(tile, corner mask, direction, success, edits and cleared water).
They assert actual source command flags at the command boundaries.
The direct command fixture additionally forces three rejected commands
(nonfreeform border, below zero, above active cap), a clean no-op, and
recursive water clear and height commits. This proves the bounded stage
given identical input, not unsupported post-generation gameplay facts.

At seed 1751 with river-route random 5:

| Size | Amount / min length | Original width river cells | TerraGenesis width river cells | TG changed corners | LFSR cursor |
|---|---:|---:|---:|---:|---:|
| 64×64 | 2 / 16 | 0 | not sampled | not sampled | 2899 |
| 64×64 | 3 / 2 | 26 | 63 | 2 | 2899 |
| 128×128 | 3 / 4 | 267 | 459 | 9 | 6090 |
| 256×256 | 3 / 16 | 1180 | 1775 | 26 | 50782 |

The positive synthetic fixture starts a broad, legal-height dry basin
and an isolated lowered corner with shore cells: the basin refloods,
three visited isolated shores dry, and the fourth remains until its visit.
