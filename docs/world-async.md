# Bounded authoritative terrain work in a Luanti worker

`mods/bayline/world_async.lua` is an opt-in library for the owner VM; it does
not change the current game mode or timers. It preloads pure terrain code
in the server async environment with Luanti's
[register_async_dofile and handle_async APIs](https://api.luanti.org/core-namespace-reference/#async-environment).
That VM has no live map/player API, and the worker is never given an
owner/storage handle, callback, or write ticket. The normal simulation VM
is the only application point. No worker registers a world edit or node.

## Integration

During mod init, before submitting jobs:

```lua
local Storage = dofile(modpath .. "/world_storage.lua")
local Worker = dofile(modpath .. "/world_async.lua")
local queue, why = Worker.new(core, modpath, Storage, {inflight=4, proposals=16})
```

If the async APIs are missing, `queue` is nil, with an explicit reason.
The caller should not claim background work or silently run a large
synchronous replacement. This is one service per owning subsystem;
do not create independent brokers to evade the queue limit.

From an ordinary owner callback, submit an absolute tile rectangle:

```lua
local id, err = queue.submit(world, 98, 100, 113, 115, {kind="raster"},
  function(result, failure)
    if not result then return end
    local mask, base, top = queue.profile(result, 100, 101)
    -- Publish as a detached cache with the result's world revision.
  end)

queue.submit(world, 98, 100, 113, 115,
  {kind="corner", x=106, z=107, mask=8, up=true, max_height=32},
  function(proposal, failure)
    if not proposal then return end
    local version, changed = queue.apply(world, proposal, function(owner, context)
      -- Check current authoritative permissions, budget and the real
      -- affected layers here. No external mutation while authorizing.
      return true
    end)
    -- Remaining authenticated command-side effects belong to the
    -- owner; this library does not run the game economy or renderer.
  end)
```

The demonstration authorizer above is for an isolated terrain test, not
permission to modify a live company world. A production mount has to
validate terrain protections, occupancy and transportation layers over
affected tiles and couple the storage update to actual company accounting.
The returned `cost` is the existing stock planner's operation count with
unit cost 1, **not** a billed price.

### Jobs and limits

- `raster` reads the existing source four-corner field and classifies
  each tile with the pinned OpenTTD 14.1 slope implementation. Output is
  three byte values per tile in row-major order: slope mask, base level,
  highest level. It does not decide water, vehicle routes or view state.
- `river_raster` is a separate version-2 raster for explicitly promoted
  source terrain. It adds flat/graded river cover and preserves the
  independent river random byte without changing the bounded input.
  See [typed detached river profiles](terrain-river-stream.md).
- `corner` quotes the existing pinned `Terrain.plan` (stock corner order
  and propagation) under the supplied maximum height. It cannot edit the
  snapshot's outer corner ring; an edit that reaches it fails with
  `NEED_WIDER_REGION`. Resize the request if possible; do not apply a
  clipped partial result. An optional `freeform_edges=false` applies
  stock actual-world border restrictions in **world** coordinates,
  never treating the clipped request itself as the whole map.
- Request size is at most 32×32 tiles. The two detached binary planes have
  at most 5,185 bytes combined, plus a fixed metadata envelope. The worker
  allocates a temporary 33×33 corner grid for a stock quote, not a map.
  Default limits are four workers in flight and sixteen unapplied
  proposals per broker (hard configured maxima eight and thirty-two).
  `cancel(id)` suppresses owner delivery but does not cancel engine CPU
  already in progress or free a slot early.
- Delivery checks the originating world revision, base identity, size
  and exact serialized region, then validates the result lengths,
  slope records, and canonical patch order/location. An edit anywhere
  in that authoritative world conservatively invalidates earlier jobs,
  even if disjoint. If the work is still needed, resubmit from a new
  snapshot. Results can arrive out of order.
- A validated terrain proposal can be authorized only by the same broker
  and exact world handle. The caller-facing result is an opaque authority
  token by object identity; altering its visible fields cannot change the
  retained patch. The owner authorization callback receives copies for
  inspection. The actual `WorldStorage.apply_job` checks the retained
  ticket, revision, region, and neighbor edges again; an intervening
  edit even during authorization is rejected atomically. No partial
  edit is committed, and a used proposal cannot be replayed.
- This is an async computation/owner-application experiment, not a
  multithreaded world simulator. Persistent vehicle, industry, economy,
  routing and world rendering remain on their existing paths.

## Evidence

```sh
lua5.1 tests/world_async.lua
tests/world_async_native.sh /path/to/luantiserver /path/to/new-private-evidence
```

Plain Lua compares 1,920 bounded quotes to the full pinned terrain
planner and exercises strict dimensions, malformed output, blocked
proposals, back-pressure, cancellation, authorization, cross-world
tokens, replay and revision changes during authorization.

The Linux dedicated test actually preloads and dispatches the worker. A
4096² lazy world takes **zero** base samples on construction; an overlapping
main-thread edit invalidates the in-flight quote. Recomputing from the
new revision applies the stock five-corner propagation, then an async
raster matches all 1,024 stock slope records. Only three sparse storage
chunks are touched. No live game mode gets enabled by running these tests.
