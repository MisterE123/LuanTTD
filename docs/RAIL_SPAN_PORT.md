# Stock normal-rail bridge and tunnel planning

The pure rail bridge and tunnel planners quote OpenTTD 14.1 commands. They do
not change terrain, ledger balances, tiles, traffic, or render state.

```lua
local Site = dofile(source .. "rail_span_site.lua")
local RailBridge = dofile(source .. "rail_bridge.lua")(BridgeGeometry, RailConstruction, Site)
local RailTunnel = dofile(source .. "rail_tunnel.lua")(
  dofile(source .. "road_tunnel.lua"), RailConstruction, Site, RailTrack)

local bridge, reason, tile = RailBridge.plan(board, first_tile, last_tile, bridge_id, opts)
local tunnel, reason, tile, cause = RailTunnel.plan(board, portal_tile, opts)
```

- `board.tile(id)` returns a tile record with **raw** shared-corner `base`,
  `slope`, `max_z`, and `kind`. `board.xy(id)` and `board.id(x,z)`
  (or `board.tile_at`) preserve OpenTTD's axes. A bridge head from a prior
  plan stores its own foundation-adjusted base, not the map's raw base.
- `board.clear_quote(id, record, role, owner)` is a **read-only** delegated
  landscape quote subject to auto-clear/no-water policy. If omitted, the
  planner knows ordinary stock ground, coast, rail and span rejection
  rules and refuses unknown cases. Use a staged clear-set in this adapter if
  a multi-tile object may be affected, as in OpenTTD's command journal.
- `board.tunnel_in_way(id, level, probe_side)` reads existing underground
  occupancy. Omit it only on maps with no underground structures to query.
  `board.max_x` or `opts.max_map_x` supplies the last zero-origin X index
  if a directional stock lookup needs it.
- `board.terraform_quote(exit, mask, false, excluded)` returns
  `{cost=..., plan=..., slope=...}` or `nil,reason`. It must run the terrain
  lowering planner without clearing the entrance or exit twice. The
  transaction must apply this plan atomically with the two tunnel portals.
  A mismatched exit with zero lowering mask requires no terrain transaction:
  OpenTTD 14.1 accepts it without rechecking the final slope. Native art can
  separately decline a portal shape that it cannot represent safely.

Both plans separate rail stock, structure and site prices, include both
portals in stock length, and expose the infrastructure counter delta.
Their portals have the `kind`, `owner`, `railtype`, `dir`, `other`,
`skip` fields directly consumable by the normal rail follower. A rail bridge
replacement never clears its old middle tiles and retains reservation
state. When integrating, keep the exact existing PBS ownership records
instead of deriving a train identifier from the raw reservation boolean.

Default prices are stock medium/no inflation (rail 100, bridge 275
coefficient base, tunnel 450 per base unit; rail removal -70 and bridge
removal +50 per tile). Live callers can supply adjusted prices and
availability. A geometry-only bridge quote must not be presented as the
complete bridge cost. Geometry and grade use the same stock foundation,
ramp and middle-clearance port used for existing road bridges.

## Verification

- `lua5.1 tests/rail_span.lua` covers span portal follower integration,
  exact deck/ramp heights, blocked overhead/ownership, live PBS
  preservation in bridge replacement data, and a real shared-corner
  tunnel exit excavation that stays read-only until applied.
- `python3 tests/rail_span_upstream.py SOURCE_TREE lua5.1` compiles the
  pinned bridge availability/replacement and price snippets and tunnel
  scan/clearance/price branches with a fixture board and 18,272 comparisons.
  Bridge ramp foundations are checked separately by the existing
  `tests/road_bridge_upstream.py` suite.

Multi-consist runtime traversal, occupancy mutation, native span rendering,
and actual tool/ledger integration are not part of these planners.
