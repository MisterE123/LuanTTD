# Typed detached river terrain profiles

The campaign's OpenTTD 14.1 river generator produces the native tile kind
`MP_WATER` (6), detached terrain subtype 3, and an independent stock
random byte. Existing live gameplay already keeps those fields
separate. This change gives the **detached** sparse terrain and worker
paths the same information without mounting them into gameplay.

## Promote a generated raster

```lua
local Words = dofile(modpath .. "/terrain_word.lua")
local Storage = dofile(modpath .. "/world_storage.lua")
local Stream = dofile(modpath .. "/terrain_stream.lua")(Slope)

-- river_raster is the result of RiverWorldgen.generate with rivers enabled.
local opts = Words.storage_options(river_raster)
local world = Storage.new(river_raster.width, river_raster.depth, opts)
local views = Stream.new(Stream.for_storage(Storage, world, Words.describe))
local frame = assert(views.update(x, z, 0, 1))
local p = assert(Stream.profile(frame.chunks[1], x, z))
if p.water_class == "river" then
  local flat, stock_byte = p.river_flat, p.river_bits
end
```

The existing source `river_raster.tile(x,z)` and
`river_raster.river_bits(x,z)` are unchanged. The adapter's **existing
32-bit word** keeps class and subtype in the low byte, leaves byte two
available for existing clear cover metadata, stores the river byte in
byte three, and uses exact tag 1 in byte four to indicate its presence.
`Words.river(0)` means a known stock byte zero, not an unavailable byte.
River-only metadata is validated on base reads, live sparse writes, and
sparse replay when opened with these options. The base identity gains
`/r3p1`, so encoded saves cannot accidentally replay on a legacy raster.
No bytes were added to the generic `BLS/1` save envelope. For the measured
128² raster: 134 bytes for the legacy base identity, 139 promoted, and 147
after changing exactly one typed river word.

The synchronous stream emits `luanttd-terrain-view/2` and
`luanttd-terrain-chunk/2`. The former six profile bytes are followed by the
typed ground byte (255 for unknown); river-flat and river-graded are two
new cover codes, 10 and 11. Their geometry is still the exact shared
four-corner stock mesh. The random byte is read from the retained word,
not substituted from coordinates or skin. Version-1 chunk records remain
readable, without fabricated river metadata. A legacy source which
provides subtype 3 can still classify the river and grade but has no
known random byte. Shore trees keep their existing separate meaning:
subtype 3 on **class 4** is a coastal tree, not a river.

## Worker use

```lua
queue.submit(world, x1, z1, x2, z2, {kind="river_raster"}, function(result, err)
  if not result then return end
  local p = queue.terrain_profile(result, x1, z1)
end)
```

The typed request only runs on a promoted base. It still sends no more
than 32×32 four-byte tile words plus the 33×33 one-byte corner plane:
**5,185 raw bytes maximum**, before fixed metadata. The worker produces
a version-2 raster of at most **7,168 bytes**, plus metadata. The owner
checks the result schema, size, region, revision, and per-cell geometry
and typed cover against its own snapshot. The owner then attaches the
same bounded tile-word string it already held; workers do not echo or
write the words, RNG, or live map. A stale result is dropped even for a
river-byte-only edit. The original `raster` and corner proposal jobs
retain the existing version-1 envelope; the original raster is still
geometry-only.

## Verification

```sh
lua5.1 tests/terrain_river_stream.lua
python3 tests/river_worldgen_upstream.py /path/to/openttd-14.1 lua5.1
tests/terrain_river_stream_native.sh /path/to/luantiserver /new/private/evidence
```

All three fixtures use the exact seed-1751 128² TerraGenesis mountainous
map, low river setting, and minimum length 16. The pinned source
comparison checks the full post-widening corner plane, water/river
classification, independent random bytes, three terrain edits, final
RNG words and landscape head. The detached view checks all 16,384
tiles: 194 flat and 18 graded river tiles. At the X=80/81 chunk seam a
real inclined river joins a flat river without an elevation gap.
Typed malformed results and corrupt save words are rejected. A separate
Luanti dedicated-server worker tests 1,024 cells in a bounded window,
drops the stale job, preserves a deliberately edited river byte of
zero, and reloads it through real SQLite mod storage.

This does not mount a player renderer, introduce flowing native liquid,
change ship navigation, migrate imported stock save-file sidecars, or
enable whole-world multithreaded simulations. Source provenance is
documented in [the stock river port](stock-river-worldgen.md).
