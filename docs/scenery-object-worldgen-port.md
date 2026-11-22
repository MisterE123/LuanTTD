# Stock temperate landscape objects

`openttd/scenery_object_worldgen.lua` ports the stock OpenTTD 14.1 vanilla
temperate object generation phase. It places the actual transmitter and
lighthouse spec on eligible terrain. It does not add mandatory landmark
locations, decorative placeholders, company HQs, or NewGRF objects.

* Transmitters go first. The nominal budget is 15 per 256×256 tiles, rounded
  up by stock map-area scaling. They need an unbridged flat clear tile at
  level 4 or higher. Source `CircularTileSearch(..., 9)` excludes nearby
  transmitters. The initial linear edge wrap and the clipped four-ring walk
  are preserved, including the classic first-column case.
* The nominal lighthouse budget is 8 per 256×256 perimeter, scaled by map
  side lengths. Freeform-edge games also reduce this by the exact count of
  `MP_WATER` along the source perimeter. An attempt chooses a border side
  and position from one Random draw, requires that the border tile actually
  be `MP_WATER`, then searches up to 19 tiles inward until it reaches an
  unbridged flat clear tile at level 0–2 or hits an invalid tile. An ordinary
  non-water map does not invent coastal placements.
* Each available spec has the source size-scaled 1,000-attempt cap and halts
  when its target or the supplied object-pool capacity is met. Failed attempts
  consume their single draw. Each success consumes two additional draws from
  source `BuildObject`: the unowned object's four-bit colour and its
  `MakeObject` tile's independent eight-bit randomness. This is true even
  when the renderer does not vary the stock colour. Both default specs have
  one view, a 1×1 footprint, and source introduction date 0. They are
  available only after date 0 under the source's strict generation test.

## Host interface

```lua
local Objects = dofile(modpath .. "/openttd/scenery_object_worldgen.lua")
local result = Objects.generate(board, industry_rng, StockRandom.next_random, {
  date = stock_date, -- actual day number; default 1 gives same eligibility
  capacity = free_object_slots, -- optional, not the count already occupied
})
result.each(function(x, z, record)
  -- Commit a true MP_OBJECT (10), not a house/road or cosmetic tile label.
end)
local tree_rng = result.rng_after
```

The 1-based board supplies `width`, `depth`, `freeform`,
`tile(x,z)`, and the completed `towns={{id,x,z},...}` list. Tile input
contains stock `class`, `slope` (0 flat), `height` (flat tile level),
`bridge_above`, and existing `object_type` when applicable. Every occupied
tile must retain its class, including non-origin industry pieces. Unknown
or outside cells are never buildable and terminate an inward lighthouse
search. The nearest association uses Manhattan distance and lower town ID on
ties, matching the stock KD-tree ordering. The stock stage assumes a town
exists once actual building is allowed.

Each immutable placement copy contains `class=10`, `type`/`object_type`
(0 transmitter, 1 lighthouse), `kind`, `town`, `colour`, `random_bits`,
`date`, `view=0`, `height`, `height_levels` (spec structural height:
10 transmitter, 8 lighthouse), and 1×1 dimensions. Use `result.object(x,z)`
for random access. `result.stats` gives perimeter-water count, attempted
and accepted totals, target shortfall, and RNG draws. This module does
not write terrain, UI, meshes, player commands, or persistent state.

Vanilla phase order is terrain/rivers → rough/rock clear → towns →
industries → **objects** → trees. Preserve the actual terminal state
from industry generation and apply the typed object records before forest
generation. A partial earlier stage yields a valid scoped object phase
on the actual board, not a vanilla seed's full opening map.

## Verification and source

```sh
lua5.1 tests/scenery_object_worldgen.lua
python3 tests/scenery_object_worldgen_upstream.py /path/to/openttd-14.1 lua5.1
```

The differential compiles pinned `GenerateObjects`, the original stock
ObjectSpec table/availability logic, both candidate routines, real
`BuildObject` behaviour and `MakeObject` bit writes, map search/scaling and
the Randomizer. Inputs include freeform and classic rectangular maps,
mixed coast and height, occupied/bridged tiles, no suitable candidates,
zero dates/capacity, and the actual seed-1751 host geometry after the
currently mounted town/coal-power stages. Exact placement order, anchor,
type, colour, tile random, town association and RNG cursor are checked.

Source by OpenTTD contributors, GPL-2.0-only, tag `14.1`,
`object_cmd.cpp`, `object_map.h`, `table/object_land.h`, `newgrf_object.cpp`,
`map.cpp`, `map_func.h`, `tile_map.cpp`, `core/random_func.cpp`; ownership and
town tie ordering from `company_type.h` and `core/kdtree.hpp`.
See `COPYING.OpenTTD.md`. No upstream art is bundled.
