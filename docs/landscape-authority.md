# Authoritative landscape invalidation, detached

This is an adapter for the existing **sparse landscape scheduler**, not
a playable large-world mount. It exercises the invalidation boundary
identified in [the live callback audit](landscape-live-audit.md). It
does not change Sim, startup, tool behavior, the clock implementation,
or released builds.

## Contract

The same owner that commits map writes preflights every membership edit,
then publishes an independently captured receipt before the next
landscape slot. Neither the renderer's `s.changed` queue nor a bare
`s.topology` increment authorizes a sparse cache change. The authority
starts from an already seeded scheduler whose members exactly match the
supplied read-only candidate predicate.

```lua
local O = Authority.new({
  world = "my-world-instance", revision = 41,
  width = 48, depth = 36, log_x = 6, log_z = 6,
}, scheduler, current_candidate)

local entries = {{kind = "corner", x = 10, z = 12}}
local t, reason, mode = O.preflight({
  schema = Authority.SCHEMA, world = "my-world-instance",
  revision = O.revision(), changes = entries,
}, "boundary")
local ok
if t then
  ok, reason, mode = O.run(t, "boundary", function()
    -- Only now mutate the owner board and return the actual receipt.
    -- For a supported corner plan: map the command's returned dirty
    -- host IDs to {kind="tile",host=id} in a plain dense array.
    return commit_native_edit_and_describe_writes()
  end)
end
-- Any failure after the writer began is terminal to this authority.
if not ok and mode == "dense" then
  O.abandon()
  -- Leave the sparse loop before taking the ordinary dense path.
end
```

Trusted callers label each transaction `boundary` (before starting the
next tick's scan) or `slot` (inside the synchronous current callback).
The phase must match at execution. Owner-scoped tokens are single use and
revision checked again. The adapter supports the following dependency
types:

| Record | Effect footprint / invalidation |
|---|---|
| `{kind="tile", host=id}` or `{kind="tile", x=x, z=z}` | Any native tile record change affecting class, house, cover, ownership, industry membership, or protection. Recheck the tile and eight neighbors, clipped physically. |
| `{kind="corner", x=x, z=z}` | Coordinates include the far grid corner; every such corner touches up to four physical tiles. Invalidate the union of those tiles and their eight-neighbor dependencies. Enumerate **all** propagated corners (not just the pointer/drag endpoints). A writer can attest the same physical footprint by returning the exact dirty native tile IDs. |
| `{kind="layer", layer=name, host=id}` (or `x,z`) | Native protection layers recognized by the coastal predicate: `level_crossing_tiles`, `bridge_above`, `aqueduct_above`, `tunnel_below`, `rail_bridge_above`, `rail_tunnel_below`. Recheck that tile and eight neighbors. The layer name remains distinct in the receipt; a generic dirty cell cannot attest it. Support different layer names only after auditing their host dependency. |
| `{kind="field", host=id}` (or `x,z`) | Field register only. An added/removed record changes membership here; existing neighboring fields stay visit candidates regardless of fence state. Field planting that removes trees or changes native tile records requires a `tile` entry as well, so coast dependencies are not silently missed. |

Coordinates on input are **one-based physical**. Host IDs are dense
row-major with physical width. All output/scheduler IDs use **zero-based
stock** stride and only for real tiles. The two strides differ for a
48×36 authored region on a 64² landscape lattice. Dependency invalidation
is deduplicated and numerically sorted. `O.affected(token)` returns a
copy of the sorted stock IDs. Receipt equality is exact per normalized
effect class and layer, modulo duplicate entries. Corner geometry and
plain tile dirtiness are intentionally equivalent as _notifications_;
the authority does not approve a terrain command's geometric legality.

`current_candidate(stock_id, x, z, host_id)` must be a deterministic,
side-effect-free read. It returns a boolean, or nil if relevant source
data is missing or the result is unproved. In a real host it must
distinguish an off-map neighbor (known) from an unloaded in-map neighbor
(unknown). The adapter validates all implicated candidates during
preflight and again immediately before writing; a mismatch with the
scheduler is local evidence of stale membership. It re-evaluates
these cells after the write, with stable sorted removals before sorted
additions. Same-tick future slots can be inserted before the writer
returns to the landscape dispatcher. If anything can fail after a native
writer ran, no further sparse step is permitted.

## Fallback and limits

- Missing/unsupported input, staleness, or capacity at a **boundary**
  before a writer is invoked may return disposition `dense`. Discard
  the sparse owner before entering the independent dense path. A wrong
  world or mismatched phase returns `abort`, not permission to write on
  another board. Inside a slot, preflight/execute failures return
  `abort`; dense suffix replay has not been proven.
- Unexpected/missing receipt, failed native writer, missing post-write
  reads, or failed scheduler writes poison the authority and return
  `abort` even at a boundary. These failures do **not** authorize replay,
  rollback, or a second attempt at the native write. World writers must
  remain serialized with the source cursor. Only a separately recovered
  authoritative state may be used to choose a future loop mode.
- Bounds are 4,096 typed records, at most 16,384 distinct affected cells,
  and the scheduler's 65,536 active ceiling (lower profile caps are
  supported). Before writing, reserve conservatively as if every
  currently inactive affected cell becomes active. This can reject a
  harmless mutation near capacity, which is safe at a boundary.
  Added work is proportional to the change footprint, with a sort and
  at most three candidate validations per affected tile, plus the
  scheduler's bounded rank work; no full-map rebuild or active-set clone.
- A dishonest/incomplete writer can lie about a footprint; read
  validation cannot detect a silent disjoint edit or infer missing
  topology-layer reports. The current live callers do **not** all have
  typed planners and receipts. For example, a public landscape
  financial quote alone is insufficient: the host must expose the exact
  canonical corner plan for the executable command, including its
  clearance/budget prefix and rollback behavior. Until command coverage,
  source snapshots, authority adoption, and a safe failure strategy are
  independently verified, keep this detached. No claims for runtime
  multimodal world growth, asynchronous mutation, or playable 4096².

## Evidence

```sh
lua5.1 tests/landscape_authority.lua
lua5.1 tests/landscape_dynamic.lua
```

The fixtures exercise generated-style physical 128² geometry with the
actual `Sim.landscape` player command. One raised corner costs $250,
returns four dirty host tiles, and reports nothing through the visual
journal. Sixteen exact dependency cells suffice to admit a newly
effective sea source; adding and removing a real protection-layer
record changes its membership even without any tile-record mutation.
A full-board reference check in the **test only** verifies no frontier
is omitted. The physical flooding test then uses the same
`Flood.visit`/native `water_flood_world.visit` callbacks and a saved
noncanonical stock head: two same-tick effects at tick 256, equal final
tile data and source cursor versus the dense source walk, while visual
dirty lists are intentionally ignored. It also covers rectangular
host/stock addressing and far-edge clipping, stale/foreign/malformed
inputs, mismatched phases, readiness retry, an unattested layer edit,
the pre-write capacity ceiling, and bounded operations at 4096² on a
sparse stub. The test is Lua differential, not native SQLite/visual QA.
