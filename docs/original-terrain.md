# OpenTTD 14.1 Original temperate terrain

This is the stock **Original** generator, not TerraGenesis and not the
authored starter map. The source port is in
`mods/luanttd_core/openttd/original_terrain.lua`; the detached storage/renderer
adapter is `mods/luanttd_core/original_terrain_stream.lua`. Neither is mounted
by the ordinary campaign.

## Source boundary and provenance

The OpenTTD contributors' GPL-2.0 implementation is ported from the
[14.1 release](https://github.com/OpenTTD/OpenTTD/tree/14.1/src):
`landscape.cpp::GenerateLandscape` (Original temperate branch) and
`GenerateTerrain`, `heightmap.cpp::FixSlopes`, `map_func.h::ScaleBySize`,
`water_cmd.cpp::ConvertGroundTilesIntoWaterTiles`, and
`core/random_func.cpp::Randomizer`. See `COPYING.OpenTTD.md` at the game
root. The differential pins the exact source files by SHA-256.

Original's templates are numeric height samples stored in the base
graphics pack as MAPGEN sprites, not procedural hills recoverable from the
engine code alone. Different base sets can supply different height grids.
The optional local oracle uses [OpenGFX 7.1](https://github.com/OpenTTD/OpenGFX/releases/tag/7.1),
copyright the OpenGFX contributors, GPL-2.0. Its palette-valued
`ogfxi_logos.grf` source is verified by SHA-256. No GRF, sprite, tile art,
mask bank or extracted OpenTTD map is included in the project or required
to run the existing campaign. The project does not redistribute this local
QA oracle.

The Original port supports each stock power-of-two axis, from 64 through
4096, in square or rectangular maps, with all four ordinary terrain and
sea values, both freeform-edge modes, and a raw unsigned 32-bit generation
seed (some stock UI paths use UINT32_MAX as their generation sentinel).
It consumes one stock
random draw for stamp count plus one per attempted stamp (including
rejections), preserves all four source stamp orientations, and overlays
the maximum through the low palette nibble. On a full 4096² map the two
direction bits overlap high Z bits in the single upstream random draw;
that stock correlation is intentional. The two original edge-fixing
passes run across the full map, never per chunk. It then evaluates actual
sea versus shore using the stock flooding-direction mask and neighbors.
It deliberately stops at the initial shore conversion. River routing,
rough-ground/rocks, timber, towns, industries, map height imports,
non-temperate branches and TerraGenesis are not part of this port.

## Local input and differential

Given a local OpenGFX 7.1 installation, supply its verified logo GRF to:

```sh
python3 tools/extract_original_terrain_masks.py /path/to/ogfxi_logos.grf /local/private/mapgen.bin
sha256sum /local/private/mapgen.bin
TMPDIR=/path/to/qa_temp python3 tests/original_terrain_upstream.py /path/to/OpenTTD \
  /path/to/ogfxi_logos.grf lua5.1 --large
lua5.1 tests/original_terrain_stream.lua /local/private/mapgen.bin
```

Extraction is read-only on the source and only writes a new destination.
The current verified local GRF SHA-256 is
`20644db32d97b2e1d7d7d9b73b0484b904a86f9e91752d9fc5f86bebb7706e5a`;
the generated bank SHA-256 is
`7ff877ad58ebcdc15cb49824c5c2bab434b2c19d7e48319b38ad94434003f432`.
No other GRF variants are accepted by this extractor. The bank interchange
is eight ASCII bytes `OTMAPGEN`, then 37 records in stock order, each
with width byte, depth byte and row-major palette bytes. Production hosts
must verify the supplied bank identity before using it; the Lua reader
validates format and the adapter preserves the caller-verified digest
in its versioned storage identity. The standalone stream test without
a path instead uses generated test grids, not a replacement for the
private stock data.

The differential builds the actual stock RNG, stamp, scale, slope repair,
slope classification and water conversion routines against a thin map
shim. It compares every corner and tile class, plus the terminal RNG
state. Without `--large`, it checks the 294 maps in the exhaustive
64/128/256 small-map suite (6,815,744 tiles). With `--large` it also pins
the stock map size settings/limits and sweeps complete 512×2048,
4096×1024 and 4096×4096 cases for a combined 28,835,840 corners and
tile classes. It reads both results row-by-row from private temporary
files, not into one large Python buffer. Neither the differential nor
the stream checks assert parity after OpenTTD
places towns and industries or runs water tile loops.

## Native integration contract

Use one owner/storage instance per world and one small `view` per
player/camera. Regenerating the base is startup work, not something a
mapblock callback does. Persist the sparse overlay separately:

```lua
local G = dofile(modpath.."/openttd/original_terrain.lua")(Slope)
local Stream = dofile(modpath.."/terrain_stream.lua")(Slope)
local Host = dofile(modpath.."/original_terrain_stream.lua")(G, WorldStorage, Stream, Slope)
local masks = assert(G.read_masks(local_verified_bank_bytes))
local world = assert(Host.open({
  width=128, depth=256, seed=1751, terrain_type=3, quantity_sea_lakes=0,
  freeform_edges=true, masks_sha256=verified_digest,
}, masks, saved_sparse_overlay))
local view = world.view({size=16,capacity=24})
local active = assert(view.update(player_tile_x,player_tile_z,32,4))
for _,chunk in ipairs(active.chunks) do
  -- For a tile within this chunk:
  -- Stream.profile(chunk,x,z) ; Stream.mesh(chunk,x,z)
end
```

- The logical terrain axes and tile/corner coordinates are one-based in
  the adapter, the stock `(x,z)` indices plus one. The far tile row and
  column are actual void tiles, not playable space. A freeform map also
  has a void near row and column. Without freeform those near tiles are
  ordinary sea. The storage extra east/south corner fringe **clamps**
  to the final physical row/column as OpenTTD does for edge slope queries.
  Native policy should reject writes to the fringe and its aliased
  boundary corners until the transaction can preserve that equivalence.
- `world.corner(x,z)` returns a shared corner level. Adjacent cardinal
  corners differ by at most one. `world.tile(x,z)` returns integer
  `{class,ground,mask,base,high,word}` from authoritative sparse properties
  and the updated four corners. Class 0 is clear, 6 water, 7 void; ground
  0 is none, 1 sea, 2 shore. Base-generated words are class in the low
  nibble, ground in the next nibble. Extra adapter properties can use
  higher bits without aliasing the descriptor.
- A render profile has the stock steep mask and two true triangular
  terrain faces (see [terrain stream](TERRAIN_STREAM.md)). Sea and
  shore terrain are classified independently of visual surfaces.
  Apply a separate water surface at the stock level using the coast land
  mask, not a cube covering every mixed coastal tile. Void has no mesh.
  Terrain levels are not world Y nodes until the shared renderer converts
  with its existing `height + .5` convention.
- Stamp placement stores compact, three-byte accepted overlay recipes
  bucketed by starting row, instead of allocating Lua numbers for every
  corner. Replaying the commutative max overlays writes packed rows from
  a reusable 16-row band (65,536 mutable height slots at width 4096).
  Each exact FixSlopes sweep mutates just one 4,096-value row at a
  time and observes the already fixed neighboring row. The base retains
  one byte per physical corner plus row/VM overhead; no second class
  plane exists. Tile classes are computed on demand. A detached request
  copies only its bounded region. For 4096², the raw height payload is
  16,777,216 bytes. The Linux Lua 5.1 reference run measured 16,770 KiB
  retained Lua heap and 36,300 KiB peak process RSS (including runtime
  and transient buffers) and about 12.5 seconds of generation CPU
  for the rough, sea-value-0 test map. The 64² Explorer remains separate.
- `world.save()` only serializes differences. Reopen against the same
  dimensions, seed, edge mode, terrain and sea values, and mask digest
  (all are in the base identity). Wrong parameters fail, not silently
  rebase. `view.commit`/`view.apply_job` invalidate chunks touching
  changed corners; direct mutations through `world.commit` invalidate
  any attached views by revision. Treat storage access as a transaction,
  not as a land/water construction authorization. The caller must use
  stock terraform/clear and layer protection rules, and update mutable
  water properties explicitly. The immutable initial sea classification
  does not recompute just because an edited corner moved.
