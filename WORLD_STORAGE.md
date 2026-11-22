# Sparse world lattice, version 1

`mods/bayline/world_storage.lua` is an isolated storage primitive for eventual
large gameplay worlds. It is not loaded by the current campaign. It contains
no terrain generator, map renderer, game-entity store, dispatcher or OpenTTD
save-file importer/exporter.

## Geometry and providers

- Native tile dimensions are independently 64–4096. Tile coordinates start
  at 1, X across each row and Z across rows. Zero-based tile IDs remain
  `(z-1)*width + x-1`. For actual OpenTTD save interop, the importer must still
  use the source width (including void boundary) when converting raw IDs.
- There is one global corner lattice, inclusively `(width+1) × (depth+1)`.
  `tile_corners` returns north, west, east, south, in the same order as
  `openttd/terrain.lua`. Neighboring tiles read the same shared sample.
- `new(width,depth,{base_id,seed,corner,tile})` takes a uint32 seed and
  deterministic, side-effect-free providers `provider(seed,x,z)`. The base ID
  is an ASCII name/version that must change if any provider output changes.
  Corners are uint8; adjacent base heights must differ by at most one level.
  The module checks returned values on demand, not every unallocated cell.
  Tiles are an application-defined uint32, not invented map-generation rules.
- The default world has no allocated chunks. Reads never populate a cache.
  Each edited 32×32 chunk stores only non-base records; reverting its last
  override deallocates it. A far corner belongs to the existing last chunk.
  `stats` exposes the revision and counts without exposing mutable storage.

## Transactions and optional worker use

`commit(world,revision,patch)` takes at most 8,448 single-coordinate records
`{kind="corner"|"tile",x,z,value}`. Duplicate records and malformed values
reject the entire patch. It checks the resulting cardinal corner edges as a
batch, stages only changed chunk copies, then publishes with no callback or
yield in between. The return is `revision,changed` or `nil,error`; no-op
commits leave the revision unchanged. These are storage invariants only,
not terrain command prices, ownership, bridge clearance, recursive earthworks
or other OpenTTD rules. The adapters are responsible for those.

`snapshot(world,x1,z1,x2,z2)` gives a detached data object and a separate
opaque ticket. Each dimension is at most 64 tiles; a 64² snapshot has 20,609
bytes of plane data (4,225 corner bytes and 16,384 tile bytes). The corner
plane includes the one-sample far fringe so edge tiles are complete. The byte
planes are immutable strings and can be passed directly to Luanti async
jobs. `snapshot_corner(snapshot,x,z)` and
`snapshot_tile(snapshot,x,z)` are pure readers using absolute coordinates.

Keep the ticket in the single owning (main) VM. After the job returns,
`apply_job(world,ticket,patch)` checks world identity, scope and the exact
snapshot revision before running the same validation and copy-on-write
transaction. Successful jobs consume their tickets, including no-ops. A
corner on the snapshot fringe may also be shared by an adjacent tile outside
the window; validation uses the adjoining live corner when needed. Current
staleness is deliberately global: any real intervening patch invalidates
jobs, even on unrelated chunks. A future scheduler can retry with a new
snapshot or introduce dependency-based revisions; workers never mutate
live state directly.

## Canonical binary format

`encode(world)` returns a binary string. `decode(bytes,{base_id,corner,tile})`
requires the exact versioned base provider, validates records and returns a
new world at revision zero. Use a binary-safe transport; never use C-string
functions. The layout is:

| Part | Encoding |
|---|---|
| Magic and version | Four bytes `BLS\x01` |
| Dimensions; seed | Two little-endian uint16s and a little-endian uint32 |
| Provider ID | One byte length (1–127), then ASCII ID |
| Changed corner and tile counts | Two little-endian uint32s |
| Corner records | Sorted by global corner ID, uint32 ID + uint8 value each |
| Tile records | Sorted by global tile ID, uint32 ID + uint32 value each |

World revisions, iteration order, chunk boundaries, and work history do not
appear in the bytes. Baseline-only world metadata is `21 + #base_id` bytes.
Saving visits only modified records and sorts each plane; memory and time
can grow if an application modifies most of the map. This is an
in-memory sparse primitive, not a disk-backed chunk database. The bytes
carry no integrity checksum and contain no entity, multiplayer or campaign
state. Integrators must choose how they persist/durably replace the blob.

## Checks

```sh
lua5.1 tests/world_storage.lua
tests/world_storage_native.sh /path/to/luantiserver
```

The pure suite covers the max dimension without dense allocation,
cross-chunk edits, boundary corners, invalid/atomic batches, canonical
save bytes and malformed input. The native test sends real binary snapshots
through Luanti's separate async VM and checks that a stale result is
rejected and the current result commits exactly once.
