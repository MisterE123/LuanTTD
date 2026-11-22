# Stock temperate map foundation (OpenTTD 14.1)

Unlike the Original generator, TerraGenesis Perlin is self-contained. Its only
inputs are the stock settings and the RNG world seed/state. It requires no
OpenGFX masks, imported art, third-party binaries, online service, or file
uploads. The Lua port keeps the stock fixed-point interpolation, numeric
tables/rounding, random draw order, water histogram, noisy coastline cuts,
coast/slope smoothing, temperate sine redistribution, and optional terrain
variety curves. Heights and tile classes use the pinned OpenTTD 14.1 Linux
semantics, including the double `abs` overload selected by the complete
upstream include chain in the coastline routine.

## Generation stages

```lua
local Slope = dofile(root .. "/openttd/slope.lua")
local TGP = dofile(root .. "/openttd/terragenesis.lua")(Slope)
local Clear = dofile(root .. "/openttd/terragenesis_clear.lua")

local seed = 1751
local terrain = TGP.generate({
  width = 64, depth = 64, seed = seed, rng_state = TGP.startup_rng(seed),
  freeform_edges = true, terrain_type = 3, quantity_sea_lakes = 0,
  tgen_smoothness = 1, water_borders = 15, variety = 0,
})
local world = Clear.generate(terrain, TGP.next_random)
local town_rng = {world.rng_after[1], world.rng_after[2]}
```

* `TGP.generate` accepts stock dimensions (powers of two, 64–4096), every
  stock terrain/sea/smoothness/variety preset, coast mask 0–15 or 16 for random,
  and optional `custom_terrain_type`, `custom_sea_level`, and `map_height_limit`.
  Border bits are NE=1 (low X), SE=2 (high Z), SW=4 (high X), NW=8 (low Z).
  Classic edges force all four coast bits. The far X/Z tile bounds are always
  void. Freeform edges also reserve the first X/Z tile bounds. The void
  corners are still part of the real stock height lattice.
* `TGP.startup_rng(seed)` reproduces the one stock `StartupEconomy` draw for
  the fluctuation counter. Pass it to `generate` for ordinary vanilla
  seeded-game ordering. Omitting it starts the standalone terrain algorithm
  at `{seed, seed}`. The generator never mutates the caller's RNG table.
* `Clear.generate` is stock `GenerateClearTile` for temperate terrain. Both
  paint attempts and their actual terrain-dependent RNG consumption count,
  including failed rocky-walk steps. It returns a new immutable raster
  identity. `world.clear_ground(x,z)` yields 0 grass, 1 rough, 2 rocks, or nil
  off clear land. The input terrain and its RNG table remain unchanged.
* The final `world.rng_after` is the stock handoff to town generation for
  temperate, zero rivers, before any terrain/town gameplay. Custom scripts or
  NewGRFs that alter startup, and nonzero river generation, are not accounted
  for. The port does not claim exact buildings, industries, objects, trees
  or the first playable tick. Other climate-specific transformations are not
  mounted by this module.

## Board, storage and renderer

Coordinates are 1-based at the Lua boundary, 0-based in the native source.
`corner(x,z)` accepts the inclusive far fringe, repeats the final stock
corner where OpenTTD clamps slope reads, and returns an integer height level.
`tile(x,z)` is the stock playable-raster width/depth including void. Decode
with `TGP.describe(word)` or `Clear.describe(word)`: class 0 clear, 6 water,
7 void; shore/wet descriptor 0 dry, 1 sea, 2 coast. The clear overlay puts its
separate subtype in byte two; `Clear.describe` returns it as a third result.
Use that subtype for natural materials if the host has suitable assets;
share the real stock corner geometry in all cases.

`world.storage_options()` mounts it as a deterministic read-only base for
the existing sparse WorldStorage. Generator/version/config/seed/starting RNG
are part of its stable base identity. Use TerrainStream's normal view chunks
for clipped planar 3D coast and terrain faces. Internally the generator
retains one byte per stock corner, uses packed signed 16-bit rows for the
fixed-point pass, three numeric rows for octave interpolation, and a sparse
rim overlay for ordered coast softening. Map generation is still batch work;
the streamed views do not regenerate the map, and setting a large stock
dimension does not itself make the campaign renderer or town simulation
support that dimension.

## Verification

Run `lua5.1 tests/terragenesis_storage.lua`, then point the source differential
at a local OpenTTD 14.1 checkout:

```sh
python3 tests/terragenesis_upstream.py /path/to/openttd-14.1 lua5.1
python3 tests/terragenesis_upstream.py /path/to/openttd-14.1 lua5.1 --large
```

The harness verifies original source file hashes and compiles unmodified
`tgp.cpp` generator functions, stock Randomizer, map slope/water conversion
and `GenerateClearTile`; it compares every height, water/void, grass/rough/
rock output cell and both RNG boundaries. Fixtures cover both edge modes,
each coast side independently, random edges, high-bit seeds, extreme custom
heights/water, nonzero variety, and rectangular maps. The storage test
checks generated shoreline counts, byte-for-byte deterministic sparse
save/reopen, rejection of a wrong generation identity, and equal streamed
elevations at adjacent 3D chunk seams.

Source provenance: OpenTTD authors, GPL-2.0-only (see `COPYING.OpenTTD.md`);
`tgp.cpp`, `genworld.cpp`, `economy.cpp`, `core/random_func.cpp`,
`heightmap.cpp`, `tile_map.cpp`, `water_cmd.cpp`, `clear_cmd.cpp`,
`map.cpp`, and `map_func.h`, all pinned to tag `14.1`.
