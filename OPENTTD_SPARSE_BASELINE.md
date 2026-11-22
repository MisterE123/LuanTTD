# Development-only OpenTTD snapshot overlay

`mods/bayline/import/openttd_sparse.lua` mounts a validated
`luanttd-openttd-map/1` snapshot as a read-only baseline for
`mods/bayline/world_storage.lua`. The starting terrain is the actual
OpenTTD north-corner height data, not generated noise or a reconstruction.
Stock road and tram topology and typed road records survive too. This is
not exposed in the game. It does not resume, modify or export a playable
OpenTTD save, restore any pools, or turn snapshot metadata into live objects.

```lua
local Storage = dofile(modpath .. "/world_storage.lua")
local Map = dofile(modpath .. "/import/openttd_map.lua")
local Sparse = dofile(modpath .. "/import/openttd_sparse.lua")(Storage, Map, core.sha256)
local base = Sparse.prepare(validated_snapshot)
local world = base.new_world()
local n,w,e,s = world.tile_corners(x,z)
local class,road_bits,tram_bits = world.tile(x,z)
local revision = world.stats().revision
-- Example: set a tile's display/topology payload to the four-way road.
local patch = {{kind="tile",x=x,z=z,value=Sparse.pack_tile(2,15)}}
local new_revision,changed_or_error = world.commit(revision,patch)
local bytes = world.encode()
local loaded,load_error = base.load_world(bytes)
```

- Coordinates start at 1. `base.source_tile_id(x,z)` uses the original
  raw source width, including the far void column. `base.logical_tile_id(x,z)`
  uses the logical width (original width minus one). In a 256² source,
  `(1,2)` is raw ID 256 and logical ID 255. The corresponding
  `source_tile_xy` and `logical_tile_xy` are inverse lookups in
  their own domains. No index from one domain is an input in the other.
- The far row and column remain true corner samples but no gameplay tile
  maps there. Original void tiles are readable but not editable, and
  this overlay keeps far-edge corner samples fixed. A stock minimum
  64-cell side has 63 logical tiles; the primitive privately pads it to
  the storage minimum and does not expose or accept edits in the padding.
- `world.tile` returns class and optional stock road/tram masks in
  northwest, southwest, southeast, northeast bit order (`-Z,+X,+Z,-X`).
  A zero mask differs from absence. `base.source_road_tile` returns a
  detached record of original metadata (including owners, pool IDs and
  unsupported flags). It always describes the source, never an overlay
  edit. Road values are tile class and topology only: no edits to
  station/vehicle pools, bridge behavior or command semantics.
- The content identity is SHA-256 over a versioned, canonical header:
  dimensions and freeform-edge flag plus digests of the exact byte-packed
  corner plane, class plane and numeric-ID-sorted normalized road
  records. Audit/provenance fields are not used instead of content; the
  original save SHA is reported separately. Altering the source snapshot
  after `prepare` or mutating a returned road record cannot affect the
  baseline. Shared probes verify reads without allocating override chunks.
- `world.encode` writes only sparse changes, bound to the precise
  baseline ID; keep the source snapshot or regenerate it from an
  unchanged original. Loading rejects another baseline, incorrect
  dimensions/seed, malformed tile words and locked padding. The binary
  format is described in `WORLD_STORAGE.md`. It is not `.sav`.
- `world.snapshot` and `world.apply_job` preserve storage's bounded
  byte-plane/revision protocol. Keep the ticket in the main VM. A snapshot
  includes source-compatible topology words and the far corner fringe;
  use `world_storage.snapshot_tile`/ `snapshot_corner` and
  `Sparse.unpack_tile`. The overlay still enforces its own edit bounds.

The baseline uses two bytes per source cell plus sparse road metadata,
without the previous dense Lua terrain-number array. JSON extraction,
validation, hashing and the source data itself still scale with map area;
this is not a streamed importer. Base records are stock-format observations,
not a claim that all observed infrastructure is implemented.

## Repeat the native check

```sh
python3 tests/openttd_sparse.py --luanti /path/to/luantiserver \
  --openttd /path/to/14.1/openttd --share /path/to/openTTD-14.1-data
```

Use the 14.1 data directory with OpenGFX installed. The script can also
replay a private saved fixture with `--save FILE --oracle-log FILE`.
The oracle and Luanti probe run in disposable profiles and verify the
original input hash after the test. No saves, stock artwork or logs are
distributed.
