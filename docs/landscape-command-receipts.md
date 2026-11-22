# Native player-command receipts for landscape ownership

**Detached command bridge.** Not wired to the hotbar, world startup,
landscape scheduler, or current release. It uses the **actual native
planner and mutation** for the supported commands, with an authority
footprint forecast and a separate post-write receipt.

## Supported surface

- `{tool="road", ids={...}}`: ordinary private road drag (or single-tile
  build), existing explicit road bits or ordinary dry ground.
- `{tool="clear", ids={...}}`: ordinary trees, houses, and private roads.
  Uses the normal house-demolition surcharge, reputation, and source
  town population changes. Native plan decides affordable, prohibited,
  and no-op behavior.
- `{tool="raise", x=x, z=z}` and `{tool="lower", x=x, z=z}`: one corner
  click, including **all** stock propagated corners. Ordinary sea/shore
  can be cleared if the live coastal planner accepts it. No level drag
  or other terrain/government/infrastructure command.

IDs and coordinates on these specs are physical host coordinates
(one-based); authority normalizes them to the stock LFSR stride. Drag
order and duplicate IDs go to the native planner intact. The adapter
accepts an existing company and validated shared-corner world, not
company creation. Inputs and expanded native footprints are capped at
256; the original landscape quote can still traverse its native
propagation before this wrapper sees and enforces the cap.

Special or unknown tile fields are outside the scope. This includes
stations/depots, public-road writes, void, industries/landmarks,
rails/crossings, tram, directed roads, bridge/tunnel/water facilities and
fences/farm overlays. Listed protection layers also veto touching their
records. Ordinary road planning reads cardinal neighbors (so verify
these do not require special geometry); those adjacent cells are never
allowed to appear as new writes from a drag forecast. Global routed
worlds are deliberately disallowed in this slice, not just routes using
the selected tile. A mount must supply a pure veto for any ephemeral
actors as well as declare any extra side-layer providers; this proof
accepts no such providers. The conservative top-level overlay naming
guard is an extra fail-safe, not a discovery mechanism for arbitrarily
named future layers. Re-audit a host before enabling more commands.

## API and execution

```lua
local Factory = dofile(modpath .. "/openttd/landscape_commands.lua")
local Commands = Factory(Sim, Authority)
local C = Commands.bind(state, world_name, existing_company, authority)
local spec = {tool = "road", ids = {first, second}}
local advisory, reason, mode = C.quote(spec)
local ok, receipt, mode = C.run(spec)
```

The side-layer declaration is optional
`opts.additional_layers`; any nonempty declaration is unsupported.
Optional `opts.untracked()` is a pure guard called by the owner to
return whether a non-saved actor makes the current world out of scope.
Never register unaudited actors while this narrow bridge is in use.

- `C.quote` gives native `cost`, ordered `dirty` host IDs, typed
  `changes` and expected corner `peak` where applicable. It performs no
  finance, terrain, or membership writes. The returned table is only an
  advisory copy; retaining or altering it authorizes nothing and does
  not modify the bound owner's data.
- `C.run` re-quotes, preflights the typed transaction with the authority,
  then uses `Sim.build` or `Sim.landscape` to make the actual edit.
  It checks native cost/peak and attests the real returned dirty IDs
  (no render list or guessed pointer rectangle). Both native command
  paths use their original planner immediately before writing.
- Success returns `true, receipt, "sparse"` (or `"unchanged"` for a
  no-op). `receipt` contains native message/dirty IDs and verified
  cost; it is **not** part of serialized campaign state. Ordinary
  native denials and unsupported scope return without writing.
- This wrapper only runs at a tick boundary. Before a writer, the
  authority can return `"dense"` for stale or insufficient proof; the
  caller may abandon sparse state and use an independent normal path.
  After an attempted write, no automatic retry, rollback, or scheduler
  continuation is authorized. Other tools remain out of scope, not
  automatically wrapped by the module.

The **only** production-source change is a backwards-compatible,
read-only `Sim.landscape(..., "footprint")` quote selection returning
`true, price, {corners, tiles, terrain_revision, topology, allowance_after}`.
It returns the existing planner's propagated damage and coordinates, not
a duplicate land validator. This mode does not create a company.
Existing boolean `true` quote behavior still returns exactly two values
and retains its historical company-opening side effect. Normal
`Sim.landscape` writes, pricing, partial policy, terrain checks and
command registrations are unchanged.

## Evidence

`lua5.1 tests/landscape_commands.lua` loads actual stock-format
TerraGenesis 128² seed 1751 with generated towns, stock houses, forest
and coast. Wrapper and direct native reference worlds compare **every
saved field** after each accepted operation; the test uses a complete
reference scan to verify no frontier or house membership was missed.
It demolishes an existing generated house, removes a tree, builds and
removes a three-tile private road, and raises and lowers real coastal
ground. The raise consumes clearance and propagation: 4 corners,
10 actual dirty tiles and $71,120. An unrelated stale render dirty
queue stays byte-for-byte unchanged. Rejections verify no finance or
authority revision changed, including facility adjacency and in-use
or unreviewed side structures. The existing authority test separately
proves that a typed tidal write can re-activate a tile at a later slot
in the **same** tick. These are headless source/host differentials,
not native visual or SQLite qualification and not integrated gameplay.
