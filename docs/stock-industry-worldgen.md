# Stock industry world generation

This slice ports the map-generation controller from
[OpenTTD 14.1 `industry_cmd.cpp`](https://github.com/OpenTTD/OpenTTD/blob/14.1/src/industry_cmd.cpp)
and the relevant [temperate definitions and tile layouts](https://github.com/OpenTTD/OpenTTD/blob/14.1/src/table/build_industry.h).
It works on a generated terrain-and-town board, not Harbor Valley's
authored scenario locations.

The stage keeps source map-area density scaling, the editor density
branch, the stock industry pool limit, the independent forced pass,
and weighted choices for the remaining slots. An included, eligible
industry gets a forced attempt group before the weighted choices.
The stock retry ceilings are 10,000 positions per forced group and
2,000 for each weighted choice. A failed group leaves a shortfall;
there are no hand-selected replacements, forced land clearances, or
extra probability draws after failure.

## Scope

The Coal-only factory supports **Coal Mine (type 0)** and **Power
Station (type 1)**. Supplying the optional stock Timber kernel adds
**Sawmill (type 2)** and **Forest (type 3)**. Temperate initial appearance
weights are 8, 5, 5 and 5, respectively. Eligible normal new-game types
get forced attempts in source ID order before weighted choices. The
Coal-only factory keeps its existing schedule and draws when Timber
is not supplied; the Timber roster is deliberately not enabled by this
detached port.

Candidate layout selection includes all original layouts: four for
coal, three for power and two each for sawmill and forest. Only layout 0
is approved for native placement. An unsupported layout draw counts as
a failed attempt; it does not skip draws or substitute a shape. The
sawmill footprint has eight occupied cells and forest has eighteen.
Unported industry types contribute no weights. Thus this is source
scheduling over a restricted supported roster, **not** seed parity with
an unrestricted OpenTTD world.

Sites follow source edge and freeform void rules; company/structure and
water exclusions; closest town by Manhattan distance with lowest-ID
tie breaking; default one industry of each type per town; and the
inclusive 14-tile Chebyshev exclusion for stock conflicting types.
Coal and power exclude each other; sawmill excludes forest; forest
excludes sawmill and paper mill (type 14) if one exists in the input
board. The source forest-specific geography check limits only Arctic
forests to the highest possible snowline plus two tile levels. There is
no extra height or existing-tree test for Temperate. The mixed generator
still mounts only Temperate. Layout holes are not occupied by graphics
or clearing. The
TerraGenesis industry platform query uses the exact expanded bounds
and corner height, including the surrounding-corner guard. This native
slice builds only where it requires **no terrain edits**. Single-corner
terraform quotes can be exercised without mutation, but a leveling
plan needing writes is still rejected by placement. A poor seed can
legitimately omit one or more selected industries. Other climates,
NewGRF callbacks, funding/prospecting, industry objects, dynamic
production-driven placement, and full terrain leveling are not covered.

## Interface

Load `openttd/industry_worldgen.lua` as `factory(Coal)` or
`factory(Coal, Timber)` with the existing stock kernels.

- `Gen.generate(board, opts)` reads a zero-based, power-of-two source
  board. Provide `width`, `height`, `freeform`, `tile(x,z)` and
  `towns={{id,x,z},…}`. Optional existing industries use
  `{type,x,z,town}`; the board data are never mutated by a quote.
- The tile reader returns `kind`, `slope`, `base`, and
  `corner_height`, the tile's own NW corner. For flat records `base`
  also suffices. Boolean `vehicle`, `bridge`, `industry`,
  `protected`, or `water_ground` and non-nil `owner` rule out
  clearing. `kind="trees"` is allowed on otherwise suitable sites.
- `opts.random()` must return the next raw uint32 from the unchanged
  stream after towns. Each position draws tile, creation seed,
  initialization bits, then layout. Accepted records add the source
  startup fields, worked initial rate draw slots for smooth production,
  color/counter draw, and one random byte per tile. Only the execution
  phase consumes those accepted-site extras.
- `opts.commit(plan)` mounts the already checked industry and must
  return true. Use plan `x,z` and cell `offset_x/offset_z` for native
  tile addresses; convert absolute source coordinates to one-based
  once. `Gen.record(plan,id,{year=…,original=…})` builds the matching
  Coal or Timber kernel record. The Forest starts at 13 wood production
  units; the Sawmill accepts wood and processes it into goods, but starts
  with zero autonomous production. Use the same `original` choice when
  generating and building records. The proof uses normal 100% cargo
  scale. The driver records stock initial construction
  stage 2/counter 3. A fresh-world snapshot taken after initialization
  can explicitly request `after_first_visit=true` to expose the
  completed graph, since the first tile visit completes each piece.
- Optional settings: `density=0..6`, `custom_count`,
  `multiple_per_town`, `platform=0..4`, `editor`,
  `original=false` for smooth rates, and `enabled={[0]=true,[1]=true}`
  (also IDs 2/3 with Timber) for an explicit subset. Default production
  is the original economy. Smooth initialization consumes all sixteen
  stock rate draws per accepted site, even for a zero-rate Sawmill.
  `result.shortfall` reports selected groups that exhausted retries.
- World pipeline is clear ground → towns → industries → objects →
  trees. Do not reseed or run tree generation with the stale preindustry
  RNG. Objects are not part of this controller.

## Verification

```sh
lua5.1 tests/industry_worldgen.lua
lua5.1 tests/industry_worldgen_timber.lua
python3 tests/industry_worldgen_upstream.py /path/to/openttd-14.1 lua5.1
```

The differential checks the pinned source hashes and compiles the exact
OpenTTD placement scheduler, initial random-layout calls, nearest-town
restriction, platform code, and initialization draws with a bounded
art/geometry host shim. It compares all created coordinates and types,
attempt and reset counts, and both final RNG words, including a map where
no supported site can succeed. It covers the original Coal-only
fixtures plus mixed weighted/forced scheduling, alternate-layout
rejection, sea-level land and smooth timber rates. The two Lua fixtures
independently check actual Coal/Timber startup and first tile-loop
completion.
