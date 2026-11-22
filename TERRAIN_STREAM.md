# Bounded 3D terrain streaming foundation

`mods/bayline/terrain_stream.lua` makes ready-to-render terrain profiles
from existing sparse worlds or the verified stock map baseline. It has no
production call sites. It does not allocate Luanti nodes, place buildings,
simulate fluids, or import a playable OpenTTD save.

## Source and view

```lua
local Stream = dofile(modpath .. "/terrain_stream.lua")(Slope)
local src = Stream.for_storage(WorldStorage, world, describe)
-- Or: Stream.for_overlay(validated_stock_world, Sparse.unpack_tile, ground)
local stream = Stream.new(src, {size=16, capacity=24})
local view = stream.update(camera_tile_x, camera_tile_z, 32, 4)
for _, chunk in ipairs(view.chunks) do
  local p = Stream.profile(chunk, chunk.x, chunk.z)
  local vertices, triangles = Stream.mesh(chunk, chunk.x, chunk.z)
end
```

A storage descriptor takes `(word,x,z)` and returns stock tile class `0–10`
and optional ground code: 0 none, 1 plain water, 2 coast, 3 coastal trees,
4 lock, 5 depot. For an imported map, the supplied overlay reads the actual
stock class and optional ground sidecar. No arbitrary tile value is
implicitly assumed to be a stock class. Without the optional ground data,
class-6 tiles are explicitly **unresolved water**, not guessed to be
coasts or rivers from slope alone.

- The camera is a logical tile, with a Chebyshev tile radius 0–64. Candidates
  sort by nearest tile's Chebyshev distance, then Manhattan distance, then
  stable row-major chunk ID. Chunks may extend past the radius so whole
  chunks are reused. Sizes 8–32 and a resident cap 1–64 are configurable.
- The work budget is 0–16 newly built chunks per update. Old chunks not in
  the chosen active set are dropped. `built`, `pending` and `excluded`
  distinguish new work, capacity-eligible work not yet built and work past
  the resident limit. A zero budget never samples the map.
- Windows and chunk descriptors are detached copies. Their payloads are
  immutable byte strings, shareable without copying cell tables. Holding an
  earlier window preserves the specific cached bytes from when it was
  published. Callers must release stale windows or they keep the strings.
- Each chunk includes the one-corner fringe. Profiles store slope, base,
  high, stock class, terrain-cover code and coast raised-corner mask as
  six bytes per tile, plus the storage tile-word plane. An 8-chunk,
  size-16 view holds 22,792 payload bytes plus small Lua book-keeping.
- `mesh` gives four absolute X/Y/Z vertices and two upward-wound triangles
  for a terrain tile, choosing the piecewise-planar diagonal from the
  pinned slope port. X/Z span two nodes per tile; the existing Luanti
  surface convention at corner `(x,z)` is `(2*x-.5,height+.5,2*z-.5)`.
  `height` uses the same stock continuous field. Both return no surface
  for void tiles. Coast corner order is stock W=1,S=2,E=4,N=8; masks
  distinguish ground above the base from shoreline-level corners, not
  ship track status or connected water.
- Route edits through `stream.commit(revision,patch)` or
  `stream.apply_job(ticket,patch)`. A tile edit only invalidates its own
  chunk; a corner edit can affect up to four neighboring chunks. Exact
  no-op edits leave their cached records valid. A source revision changed
  outside this wrapper safely clears all resident chunks because it lost
  the edit details. Source readers/descriptor are pure and must not yield.

## Verified ground flags

`python3 tools/openttd_save_ground.py game.sav --output ground.json` creates
a separate optional sidecar, never changing the save or overwriting an
existing output file. `import/openttd_ground.lua` validates and loads it as
an immutable read closure, matched to the snapshot's source-file SHA and
dimensions. The stock code uses actual MAP5 water subtype/coast bits and
MAPO water class bits for coastal trees (OpenTTD 14.1 `water_map.h`). This
does not decode ship objects, water levels beyond terrain, or water
classes for other tile classes. A render overlay's static source ground
metadata is used only on tiles of matching class, not a new canal builder.

## Verification

```sh
lua5.1 tests/terrain_stream.lua
python3 tests/openttd_ground_source.py /path/to/OpenTTD-14.1
python3 tests/terrain_stream_native.py --luanti /path/to/luantiserver \
  --save /private/stock-fixture.sav --oracle-log /private/stock-fixture.log
```

The Lua test visits 64² and 4096² sparse worlds, validates all 19 polygonal
slope profiles and shared seams, and tests budget, durable old windows,
valid regional invalidation and out-of-band revision safety. Generate a
private stock fixture and matching oracle log with the existing
`tests/openttd_save_map.py` harness: use `LUA_NTTD_SAVE_TRACE=1` and
`--retain-fixture /private/stock-fixture.sav`, saving its stdout to the
log. Native Luanti streams its stock 256² terrain without activating the
campaign. No fixture or original artwork is distributed.
