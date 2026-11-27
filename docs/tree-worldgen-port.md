# Temperate forests at world creation

`mods/luanttd_core/openttd/tree_worldgen.lua` is the stock OpenTTD 16.0-RC1 Temperate
normal-game forest generation stage. This is not uniform decorative tree
scattering. It preserves all RNG draws and writes in game order:

1. Draw a group count (25–56 before scaling to map area). Each group draws
   a center and four harmonic phases for the stock 16-vertex grove, then
   attempts 1,000 offsets. A tree must fit the source polygon; it no longer
   draws a fixed diamond on the terrain. The Lua adapter preserves the
   source float32 and integer boundary decisions.
2. Run six ordinary random placement passes with the Original placer, or two
   with the default Improved placer. Each pass has the stock, size-scaled
   attempt count.
3. After a successful Improved base placement, calculate
   `2 × tile base height` neighbor placements, scaled by `15 / map height limit`
   whenever the limit exceeds 15. An automatic limit uses the same terrain
   estimate and headroom flow as stock. Each placement searches up to 1,000 offsets, accepts
   Manhattan distance at most 16 and a base height within two levels, and
   stops at the first legal result. Already planted tiles block subsequent
   attempts. Terrain base is the minimum of all four corners, as in
   `GetTileZ`, not the north corner.
4. Species (IDs 0–11), stems (one to four), growth (0–6), and ground cover
   all come from the *same* candidate RNG draw. No extra cosmetic RNG
   affects placement.

The None placer produces no records and consumes no RNG. Planting accepts
ordinary clear ground or a broad shore, but excludes rock, fields, bridge
overhead, one-corner shores, flat sea/rivers/canals, existing trees, roads,
buildings, industries, and void. Genuine shore tree tiles retain the sea
water class while becoming stock `MP_TREES`, which provides no vehicle
tracks of its own. The runtime adapter must not turn them into navigable
sea or discard their shore geometry when rendering. Grass and rough
subtypes are rerandomized by the stock tree candidate, not copied from
the prior dry ground.

## Host interface

```lua
local Trees = dofile(modpath .. "/openttd/tree_worldgen.lua")
local Forest = Trees.generate(board, incoming_rng, StockRandom.next_random, {
  tree_placer = Trees.placer.improved, map_height_limit = 30,
})
Forest.each(function(x, z, tree)
  -- x, z: 1-based. tree: class=4, type, count, growth, ground, density,
  -- and water_class="sea" for the broad shore subtype only.
end)
local outgoing_rng = Forest.rng_after
```

Board fields are `width`, `depth`, `freeform`, and
`tile(x,z) -> {class,ground,raw_ground,density,slope,coast,bridge_above,height}`.
Use stock classes: 0 clear, 4 trees, 6 water, 7 void. Set `coast=true`
**only** for real stock coast. `slope` is the stock corner mask;
`height` is the tile base. For ordinary dry clear cells `ground` is
0 grass, 1 rough, 2 rocks, 3 fields, 4 snow, or 5 desert;
`raw_ground` defaults to it and can represent an underlying grade.
Density defaults to 3. Native temperate generation does not normally
contain snow/desert; tested source predicate and preservation still
handle those inputs. Read the current completed world board, not a
stale opening terrain snapshot.

The kernel calls no external services, never mutates the board or given RNG,
and does not place Luanti nodes. Result records are sparse and can also
be queried individually with `Forest.tree(x,z)` or the stable small
`Forest.encoded(x,z)` plus `Trees.decode`. Iteration is deterministic stock
placement order. Coordinate wrapping matches the original freeform/classic
edge rules. Shapes and artwork, growth/spread after startup, construction
clearance/rating/flood hooks and player/editor planting are not mounted
by this module.

## Phase ordering and release scope

Vanilla world creation runs terrain and optional rivers, rough/rock clear
painting, towns, industries, objects, and **then** `GenerateTrees`. Hand off
the actual terminal RNG words from those stages without reseeding. Passing a
previous stage's state is still a valid scoped forest simulation on the
provided board, but it does not reproduce the vanilla seed's forest layout.
Neither this detached kernel nor its fixtures claim full world startup,
landscape-loop equilibration, or a visually playtested integrated release.

## Proof and provenance

```sh
lua5.1 tests/tree_worldgen.lua
python3 tests/tree_worldgen_upstream.py /path/to/openttd-16.0-RC1 lua5.1
```

Differential compiles verified unmodified routines from OpenTTD 16.0-RC1
`tree_cmd.cpp`, `tree_map.h`, `tile_map.cpp`, `map.cpp`, `map_func.h`, and
`core/random_func.cpp`, with a typed synthetic map/host. It checks actual
TerraGenesis/clear-board fixtures and adversarial protected layouts, both
edge modes, all placers, varied seeds, rectangular sizes, high map limits,
and tightly obstructed neighborhoods. The proof
compares placement coordinates/order, species, stems, growth, ground,
density, sea class and exact RNG state and draw counts: 26 full runs,
19,545 tree placements and 193,162 shared RNG draws. The separate
[display-selector oracle](../tests/tree_display_rc1.py) checks stock silhouette
IDs and phases for all 12 TreeTypes. Finished art still uses four native
families, and is not credited for the missing stock silhouettes.
Source by OpenTTD
contributors, GPL-2.0-only (see `COPYING.OpenTTD.md`).

## Live worker tree visits

Each tree visit now passes a shared neighbor resolver and its current
coordinates to the RC1 rules rather than allocating a Lua closure. As in
the source, only a spread attempt reads a neighbor. The RNG draws,
direction choice, plantability, ground density and writes are unchanged.
An adapter regression exercises actual planting in all eight directions,
including consecutive visits in different worlds.

Four alternating native worker runs from the same generated 1024×1024
checkpoint measured days 18–25 after one warm-up day each. The median
simulation CPU time per day fell from 900 to 746 ms (17%); the mean
fell from 869 to 738 ms (15%). Both candidate replays produced the
same durable day-25 game state, including the shared RNG and every tile.
These timings cover simulation stepping in this world, not autosave,
networking, rendering or a guaranteed speedup on other maps.
