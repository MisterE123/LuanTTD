# Rail electrification host adapter

This host powers the electrification workbench described in
[the player guide](electric-rail.md). It deliberately limits the broader
stock command to infrastructure the current game can revalidate and
render. The stock rules are in [the railtype source port](railtype-port.md).

## Server API

Create `W = dofile(mod .. "/rail_electrification_world.lua")(Sim, Terrain, Track, RailTypes, Spans)`.

- `W.tile_type(S, id)` is the canonical reader. It returns 0 for a legacy untyped `build == "stock_rail"` tile, 0/1 for a typed tile, and nil for nonrail or invalid records. On successful conversion, each dirty native tile stores explicit `t.rail_type` (including 0 on a downgrade). The board adapter should expose this as `board.tile(id).railtype`; railtype and the track bitmask are independent. Do not copy the type into stations, depots, or signal records.
- `W.quote(S, owner, ids, target, ctx)` returns a transient single-use ticket or `nil, reason, detail`. `ids` is a dense ordered list of unique tile IDs (an already interpreted drag); `target` is ordinary rail 0 or electric rail 1. A successful ticket exposes `price` / `cost`, `ids` (the exact tiles to change), `target`, and `skipped` (foreign tiles that could not change). Copies of tickets are not commit authority. Requote on reload.
- `ctx.availability(S, owner)` is required. It returns the authoritative available stock railtype mask, optional hidden mask, and whether electrification is disabled. Use the shared company/runtime bridge, not a hardcoded mask in UI. `ctx.prices(S, owner)` may supply the current `{rail,clear_rail}` price subset; if omitted, use stock medium/no inflation. If the nonpersisted survey tool is mounted, supply `ctx.is_clear(S)`, returning true only when no survey locomotive is active.
- `W.commit(S, owner, ticket, ctx)` returns `true, price, dirty_ids, receipt` or `false, reason, detail`. An expired ticket is rejected across reload, topology changes, or corner revision changes. Commit recomputes prices, affordability, availability, placement and protected/occupied/reserved state. It does not trust client-visible ticket fields. It applies all type edits and the matching cash, expense and monthly expense exactly once, advancing `S.topology` once. The returned `receipt.infra` is a source-derived delta, not a second infrastructure ledger.
- After success, invalidate/update the returned tiles and whichever neighbours native wires require, then run the usual campaign save. The Lua transaction itself never performs renderer or save callbacks. Preserve the existing signal, station/axis, depot direction, track mask, site terrain and owner. Fresh non-typed construction and removal must not leave stale `rail_type` metadata when the typed workbench is wired.
- A separately qualified `ctx.span_art_ready(S, record)` opens owned wooden rail bridges. The shared span type and both portal records are changed together; middle tiles are refreshed but their underlying ground records are not overwritten. This is not the same `tile_type` reader as ground rail. The span prices and layer behavior are documented in [the source span comparison](RAIL_SPAN_ELECTRIFICATION.md).

## Exact scope and fail-closed choices

Empty ordinary non-rail and foreign standard-gauge ground can be skipped, like stock drag conversion. Already-target tiles are unchanged. Unknown protected structures, separately selected stacked ground rail, unknown rail placements and malformed records abort the whole quote. Ordinary rail uses the flat, single-piece policy (all six single pieces), valid signal records, complete homogeneous owned platforms and enclosed depots. Wooden rail bridge ramps are part of the bridge, not independently converted. The old one-way survey must be cleared. Tracks currently occupied (including a purchased consist in its depot), reserved/search-claimed, or on an accepted active route cannot change. Existing stock route/physical reservations are left alone; broader stock reserved-route rebuild and conversion under traffic are not claimed.

The mount requires the typed Trackworks board, YAPF/occupancy, rail
removal/construction, depot purchase gate, and the original native
catenary and vehicle models. The adapter itself does not create graphics
or infer missing art from a track's type.

`tests/rail_electrification_world.lua` verifies actual Sim/Trackworks building and depot purchase records, seven flat pieces for $476 and a restored-state downgrade for $84, budget/tariff/terrain/occupancy races, unsafe placement refusals, ownership skips, signal/depot/platform preservation and terrain state retained across copy/reload. It is not a GUI test.
