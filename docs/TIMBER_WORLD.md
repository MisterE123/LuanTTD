# Default temperate timber scenario geometry

`mods/luanttd_core/timber_world.lua` is an isolated scenario/layer adapter,
not a player-funded industry command, and makes no changes to live Sim
entry points or rendering. It seeds only actual source OpenTTD 14.1
ordinary Forest and Sawmill layout **0** as completed map-generation
industries. Stock original-economy rates, site history and upcoming
periodic phase are explicit; new freight queues and carriers are still
owned by the eventual live timber mount.

## Untouched seed 1751

| Role | Exact 1-based map location |
| --- | --- |
| Alder Timber Forest anchor | (12,1), layout0, 18 footprint tiles |
| Forest Wood truck stop | (16,2), directly east of a real forest cell |
| Tidewater Sawmill anchor | (12,16), layout0, 8 footprint tiles |
| Sawmill Wood receiving gfx13 | (14,17) |
| Sawmill Wood receiving stop | (15,17), directly east of gfx13 |
| Sawmill Goods pickup in live service | (12,15), on the separate northern spur |
| Town Goods destination stop | (14,8), 9 stock acceptance eighths |
| Road depot | (11,12), adjacent to the west of the road spine |

The truck stop at (14,8) reaches three real stamped stock shop/market
houses: 3 acceptance eighths from Port Alder plus 6 from Mason Quay,
for 9 overall. It does not cover the sawmill. The mill stop covers
exactly 8 Wood acceptance from gfx13, and its same truck facility can
collect the processor's Goods. No old house, town site or coal cell is
overlaid or relocated. Site anchors are 15 tiles apart, passing the
actual conflicting-industry limit (distance ≤14 fails). The two
intentional footprint holes include (12,5) in Forest and (14,18)
in the Sawmill; neither is reserved or altered by placement.

Build the two road strings below with ordinary road drags (or expand the
waypoints by Sim.line and quote each continuous route). Existing public
roads retain public ownership and actual connection bits. These are
construction instructions for the fixture, **not** writes performed by
the site seeder.

1. (16,2) → (16,7) → (15,7) → (15,8) → (12,8) → (12,14)
   → (13,14) → (13,15) → (15,15) → (15,17).
2. (15,8) → (15,12) → (12,12). The reconnecting branch is necessary to
   return from the through Goods terminal without forcing an unsupported
   same-station reversal. On this test map ordinary road construction
   clears the woodland directly beneath chosen future path tiles.

Put truck stops on the two endpoints and on Goods (14,8), and put an
owned depot at (11,12). Stock directed road frames compile in both
directions with known prior arrival trackdir, and repeat on identical
paths: 371/373 frames for Forest↔Sawmill and 247/255 for Sawmill↔Goods.
To run both trucks with full-load orders at once, add a spur from
(12,14) to (12,15) and a fourth truck stop there. Use the southern
mill stop for Wood only and the northern spur for Goods pickup. A
covered truck waiting for full Goods in the wood stop's sole bay
would prevent wood from entering, so don't share that bay.
Use original Witcombe Wood and Balogh Goods engine definitions when
the timber loader is mounted. Stop names/receipt awards in the future
host come from stock transport, not this seeder.

## API and future mount

- Instantiate `W=Factory(Sim,Terrain,Timber)`. The entire primary
  scenario is available via `W.scenario_1751(s)`, returning native tile
  IDs and road waypoint arrays without mutations. `W.default_1751(s)`
  seeds the pair, not roads. `W.quote(s,kind,origin)` and
  `W.quote_pair(s,forest_id, sawmill_id)` are side-effect-free;
  `W.commit(s,quote)`, `W.commit_pair(s,quote)`, and
  `W.seed(s,forest_id,sawmill_id)` apply after rechecking the native
  shared-corner grid, mask, exact geometry, blockers, industry distance,
  topology version, and *both* prospective industry IDs. Neither source
  record nor protected footprint is written until all preflight passes.
- `s.stock_timber_industries` is keyed in a disjoint host industry ID
  band starting 0x1000. The resolver rejects rather than overwrites
  collisions with existing stock coal IDs. Within this tiny scenario
  map the reserved band is not the source industry *type* ID: those
  remain exactly Forest 3 and Sawmill 2.
- Each real footprint cell holds general `tile.stock_industry` with
  `chain="timber"`, `kind`, `layout=0`, `style`, local `x,z,gfx`,
  native `origin`, canonical industry `id` and host `site`. The
  original dirt/corner surfaces remain unchanged. `W.record(s,id)`
  returns that metadata and the true saved industry; `W.protected`
  needs no rendering or clock. The existing generic stock-industry
  marker protects all 26 cells from ordinary builds, clearing and
  corner edits. Only occupied anchors get `tile.site`.
- Add `W.facilities.stock_forest` / `stock_sawmill` to the future
  host Sim registry before placing the pair at initialization. These
  intentionally have empty generic `produces` and `takes`: never use
  the old per-day prototype supply/sale on these source locations.
  Bind the true records in the single-world clock per TIMBER_PORT.md.
- Parent/native renderer must branch by `tile.stock_industry.chain`
  before looking into the coal registry. Approved artist paths:
  `models/bl_<style>_<x>_<z>.obj` with styles `forest_0` and
  `sawmill_0`, and their own atlas. Native art mount is on the
  even-node footprint anchor (2*x, base+1, 2*z). At runtime read source
  tile gfx from the industry for dynamic tree state, not the initial
  immutable geometry tag. Render nothing on layout holes.

Run `lua tests/timber_world.lua` for the actual unaltered stock map with
both original towns and original coal scenario already placed. It covers
no-op/stale/tampered/refused pair transactions, independent ID collision,
spacing, shoreline, slope, exact occupied masks/holes, all-cell
protection, and live Sim road construction/route compilation. Dedicated
art mount and moving stock timber vehicles are separate gates.
