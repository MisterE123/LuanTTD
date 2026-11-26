# Stock town world generation

This is the temperate ordinary-OpenTTD town placement and creation
controller. The source reference is
[OpenTTD 14.1 `town_cmd.cpp`](https://github.com/OpenTTD/OpenTTD/blob/14.1/src/town_cmd.cpp)
and [`map.cpp`](https://github.com/OpenTTD/OpenTTD/blob/14.1/src/map.cpp).

The port preserves map-size-scaled suggestions or a configured custom
count; the larger-town lottery; random tile wrapping; alignment for 2×2
and 3×3 road layouts; coordinate hash selection for randomized layout;
distances to edges and other towns; and the two stock searches that move
a water candidate to a coastal site. Flat clear and tree tiles are
eligible. Distances use Manhattan geometry, including strict rejection
only below 20 tiles between centers. A circular search takes the first
match on a tie, preserving enumeration order. Towns that cannot grow a
nonzero population are retried instead of leaving physically empty
centers. The soft pass makes at most 20 position attempts per name; if no
town is created, the hard pass tries one name against up to 10,000
positions. The failed soft-pass names do not reserve names in the hard
pass.

## Interface

Load `openttd/town_worldgen.lua` with the existing `town_growth.lua`
and `town_growth_build.lua` modules. Pass a stock **zero-based** map
board into `W.generate(board, opts)`.

- `board.width` and `board.height` are powers of two between 64 and
  4096, `board.freeform` matches map settings, and
  `board.tile(x, z)` supplies `kind` and `slope`. Optional
  `water_ground` models `HasTileWaterGround` for coast/locks and other
  tiles with water ground. Without it ordinary water tiles count as wet.
  Supply an exact `water_distance(x,z)` only if the host caches stock
  sea distances, or let the controller scan directly.
- `board.towns` contains existing centers `{x,z,name}` in source
  coordinates; this list is not mutated. Optional `can_allocate` can
  expose a tighter available town pool, and `opts.rebuild_index` can
  update a host spatial index.
- `opts.random()` returns a full raw unsigned 32-bit value from the
  **same** world stream used to generate terrain. `opts.name(used,random)`
  returns `nameparts,name` or nil. Either the callback or controller may
  reserve the normalized display name in the supplied set. Never compare
  raw name prompts as unique strings.
- `opts.create(candidate,random)` receives zero-based `x,z`, chosen
  `layout`, `name`, `nameparts`, `city`, and `size`. The callback
  must return a record with **`population > 0`** to accept that center.
  Return a zero-population record only with `opts.remove` to roll back
  temporary writes, or roll back in `opts.create` and return nil.
- Call `W.initialize(town,growth_board,settings,random)` from the
  create callback. The town and its growth board may use consistent
  native one-based coordinates. Pass `year`, `commit(proposal,town)`,
  and optionally `initial_city_size`, `growth_setting`, cargo scaling
  or cargo key adapters. The commit callback should apply only native
  tile writes; `W.initialize` is responsible for population and house
  accounting. Keep the source-based initial counter for host IDs
  offset by one. World generation draws independent house completion
  lotteries; unfinished physical houses have their true counter and
  stage and do not inflate initial population.

## Verification and limits

```sh
lua5.1 tests/town_worldgen.lua
python3 tests/town_worldgen_upstream.py /path/to/openttd-14.1 lua5.1
```

The Python test checks pinned file hashes and compiles the actual
placement, circular search, coastal-distance and generation-loop
functions from OpenTTD. It compares full accepted-town records and both
RNG state words after each run. This oracle uses controlled terrain,
names and `GrowTown` outcomes. The separate Lua test exercises the real
ported house/road proposal entry point as well as rollback and hard
fallback. Neither test claims all OpenTTD house catalogs, foundations
and population match a full upstream generated save. The current
growth adapter limits what can be built on unfamiliar slopes, what
abstract structures can be cleared, and which native house models
can appear. Exotic climates, NewGRF names and buildings, and every
slope/bridge/tunnel case are outside this slice.


## Municipal streets, river bridges and road bores

In a fresh Temperate world, use the standard town layouts. Towns can
shape clear slopes, pave a graded street or clear eligible coast, and
cross a river or bore under a hill as their street grid grows. These are
public roads: they carry private bus routes and do not debit a company
at construction. Removing a town span uses the local authority's
rating and budget check, and does not erase the river or terrain above
the tunnel.

The growth walk uses the 16.0-RC1 `town_cmd.cpp` branches
`IsRoadAllowedHere`, `LevelTownLand`, `CanRoadContinueIntoNextTile`,
`GrowTownWithBridge` and `GrowTownWithTunnel`. The bridge scanner
distinguishes clear river/canal water, sea, coast and rocky water; it
preserves the source length budgets and bounded style lottery. The
native build commands determine final foundation, bridge head and bore
geometry. Failed candidates discard only their own municipal
structures and leave legal grading already performed. Industry sites
respect the original exclusion below a bridge.

Tests compile the pinned continuation and both span searches across
25,920 inputs with exact approach classifications, styles, endpoints and
random draw counts. The fixed ordinary 128×128 seed 798 (Mountainous,
water borders off, river setting 2, high towns) exercises both built
structures, regular sloped public streets, independent middle layers,
bidirectional stock road routing, save/reopen and priced council
demolition. The `LUANTTD_NATIVE_GENERATED_TOWN_SPANS=1` renderer replay
views the actual freshly generated bridge and tunnel from a real
Luanti client on the production campaign worker.

This scope does not yet add live municipal road expansion, all supported
foundation changes to public owned terrain, the native bore-exit
excavation fallback or other climates. Initial town placement keeps
the existing supported parcel and map classes.
