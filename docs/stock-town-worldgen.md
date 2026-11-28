# Stock town world generation

This is the temperate ordinary-OpenTTD town placement and creation
controller. Placement targets [OpenTTD 16.0-RC1 `town_cmd.cpp`](https://github.com/OpenTTD/OpenTTD/blob/16.0-RC1/src/town_cmd.cpp) and [`map.cpp`](https://github.com/OpenTTD/OpenTTD/blob/16.0-RC1/src/map.cpp); the placement module retains its 14.1 provenance for inherited helpers.

The port preserves map-size-scaled suggestions or a configured custom
count; cyclic city allocation from a single random offset; random tile wrapping; alignment for 2×2
and 3×3 road layouts; coordinate hash selection for randomized layout;
distances to edges and other towns; and the two stock searches that move
a water candidate to a coastal site. Flat clear and tree tiles are
eligible. World generation requires 12 of the surrounding 25 tiles to have
non-rough, dry clear land or trees within the stock height band. Suggested
counts scale to map size, add random variation, then scale by land coverage.
Distances use Manhattan geometry, including default strict rejection
only below 20 tiles between centers. A circular search takes the first
match on a tie, preserving enumeration order. Towns that cannot grow a
nonzero population are retried instead of leaving physically empty
centers. The soft pass makes at most 20 position attempts per name; if no
town is created, the hard pass tries one name against up to 10,000
positions. The failed soft-pass names do not reserve names in the hard
pass.

In New World, choose **Custom** under Town density to use a specific count
from 1 to 5,000. In Advanced options, set that count, the stock city
frequency (0 disables cities), initial city-size multiplier, and minimum
town separation. The custom count is a target: unsuitable sites are
still rejected, so a small or very wet map may place fewer towns.

## Interface

Load `openttd/town_worldgen.lua` with the existing `town_growth.lua`
and `town_growth_build.lua` modules. Pass a stock **zero-based** map
board into `W.generate(board, opts)`.

- `board.width` and `board.height` are powers of two between 64 and
  4096, `board.freeform` matches map settings, and
  `board.tile(x, z)` supplies `kind`, `slope`, `base`, `max_z`, and `rough`.
  The host may provide the stock-compensated `board.initial_land_count`. Optional
  `water_ground` models `HasTileWaterGround` for coast/locks and other
  tiles with water ground. Without it ordinary water tiles count as wet.
  Supply an exact `water_distance(x,z)` only if the host caches stock
  sea distances, or let the controller scan directly.
- `board.towns` contains existing centers `{x,z,name}` in source
  coordinates; this list is not mutated. Optional `can_allocate` can
  expose a tighter available town pool, and `opts.rebuild_index` can
  update a host spatial index.
- `opts.random()` returns a full raw unsigned 32-bit value from the
  **same** world stream used to generate terrain. `opts.name(used,random)`
  returns `nameparts,name` or nil. Either the callback or controller may
  reserve the normalized display name in the supplied set. Never compare
  raw name prompts as unique strings.
- `opts.create(candidate,random)` receives zero-based `x,z`, chosen
  `layout`, `name`, `nameparts`, `city`, and `size`. The callback
  must return a record with **`population > 0`** to accept that center.
  Return a zero-population record only with `opts.remove` to roll back
  temporary writes, or roll back in `opts.create` and return nil.
- Call `W.initialize(town,growth_board,settings,random)` from the
  create callback. The town and its growth board may use consistent
  native one-based coordinates. Pass `year`, `commit(proposal,town)`,
  and optionally `initial_city_size`, `growth_setting`, cargo scaling
  or cargo key adapters. The commit callback should apply only native
  tile writes; `W.initialize` is responsible for population and house
  accounting. Keep the source-based initial counter for host IDs
  offset by one. World generation draws independent house completion
  lotteries; unfinished physical houses have their true counter and
  stage and do not inflate initial population.

## Verification and limits

```sh
lua5.1 tests/town_worldgen.lua
python3 tests/town_placement_rc1.py /path/to/openttd-16.0-RC1 lua5.1
```

The Python test compiles the pinned 16.0-RC1 town-count and generation-loop
functions against controlled terrain, names and growth outcomes. It compares the
accepted towns and random state over 256 generation traces and site admission
over 6,000 cases, plus 120 coastal searches against the stock spiral and water-distance code. The separate Lua test exercises the real
ported house/road proposal entry point as well as rollback and hard
fallback. Neither test claims all OpenTTD house catalogs, foundations
and population match a full upstream generated save. The current
growth adapter limits what can be built on unfamiliar slopes, what
abstract structures can be cleared, and which native house models
can appear. Exotic climates, NewGRF names and buildings, and every
slope/bridge/tunnel case are outside this slice.


## Municipal streets, river bridges and road bores

In a fresh Temperate world, use the standard town layouts. Towns can
shape clear slopes, pave a graded street or clear eligible coast, and
cross a river or bore under a hill as their street grid grows. These are
public roads: they carry private bus routes and do not debit a company
at construction. Removing a town span uses the local authority's
rating and budget check, and does not erase the river or terrain above
the tunnel.

The growth walk uses the 16.0-RC1 `town_cmd.cpp` branches
`IsRoadAllowedHere`, `LevelTownLand`, `CanRoadContinueIntoNextTile`,
`GrowTownWithBridge` and `GrowTownWithTunnel`. The bridge scanner
distinguishes clear river/canal water, sea, coast and rocky water; it
preserves the source length budgets and bounded style lottery. It searches
the full RC1 radius for an existing parallel road bridge, distinguishes
signalled track from rail depots and other facilities, and respects the
stock level-crossing setting when checking a route beyond a span. The
native build commands determine final foundation, bridge head and bore
geometry. Failed candidates discard only their own municipal
structures and leave legal grading already performed. Industry sites
respect the original exclusion below a bridge.

Tests compile the pinned continuation and both span searches across
31,104 inputs with exact approach classifications, styles, endpoints and
random draw counts. The fixed ordinary 256×256 seed 1 (Mountainous,
water borders off, many rivers, high towns) exercises both built
structures, regular sloped public streets, independent middle layers,
bidirectional stock road routing, save/reopen and priced council
demolition. The `LUANTTD_NATIVE_GENERATED_TOWN_SPANS=1` renderer replay
views the actual freshly generated bridge and tunnel from a real
Luanti client on the production campaign worker.

Live municipal road expansion is covered separately in [Town growth and authority](town-growth-authority.md). Some foundation changes, complex or protected bore excavation, and other climates remain outside this slice.

## Ordinary RC1 founding and full-year authority baseline

A native OpenTTD 16.0-RC1 128×128 temperate game (seed 1751, Original
streets, four towns, city frequency 1 in 3, Normal growth, improved forests)
provides the numeric checkpoint fixture in
`tests/town_growth_rc1_generated_region.lua`. The test starts LuanTTD's
ordinary campaign generator, not an imported map. Fourteen snapshots from the opening playable tick through the next
January 1 match the reference elevations, tile classes, roads, per-house
build/age state, town clocks and production, and simulation RNG. The
ordinary authority runs all 27,010 ticks, with three packed save/rebinds.
The comparison includes the daily industry clock's stock draw at the
125-day threshold, even though this map has no industry. This includes a nonlinear site search and municipal
earthworks. During founding, as in live growth, RC1's executing terraform
command makes both altitude-dependent random passes; only the second pass
can mark an excavated tile as rock. Quotes do not consume a draw.

The regression runs this full year with both rivers off and stock Normal
rivers. Active industries, companies, disasters and subsidies are off in
these two same-seed comparisons; active industry and subsidy interactions
on newly generated maps remain separate parity cases.

### Normal-industry opening

The same 128×128 reference seed starts with eleven industries in RC1 and
LuanTTD. All placement/layout, starting production and initial counters
match; the final pre-play map and RNG also match after 1,280 landscape
ticks. This comparison isolates the startup phase, not live industry
behavior. The fixture is `tests/town_growth_rc1_industry_start.lua`.

The same live authority matches the source through the first running year:
**27,010 consecutive ticks**, the shared RNG on every tick, and all heights,
tile classes, house state, roads, and town cargo and clocks at fourteen stock
snapshots. The fixture also rebinds three packed checkpoints. Industry
production and monthly accounting walk the actual IndustryID order. Houses
and industries animate in one stock tile vector; removal swaps in the last
tile, which determines the next tick's random draw order. Stock subsidies
are enabled, but this run has no player company or routes.

Opening a human company consumes the stock company colour shuffle, manager
face and unique president-name draws on that same simulation RNG. Creating
the first company begins at the stock 100,000 cash and loan at uninflated
default settings. In a separate RC1 replay with one new idle human company,
its initial records and random state match exactly, then towns, roads and
houses match again through every checkpoint of the first year (including
actual new streets and houses). Packed reopens and repeat admissions must
not redraw identity. This does not assert finance parity for the full year,
late-company inflation, or mixed services.

### A normal region with passenger and freight services

On the same seed, a bus serves Wunnwell and a truck hauls wood to the
generated sawmill. Both routes are purchased and built, with normal stock
low vehicle running-cost settings and base construction prices. Commands
create the original vehicle types, depots, roads, through stops and orders.
The scenarios are built independently, not imported from a native save.

The corridor matches **27,010 consecutive shared RNG ticks**, fourteen
whole-map and town snapshots, and nineteen matched position, speed, progress
and load samples per vehicle. The year ends with **283 passengers and
80 tonnes of wood** delivered. The LuanTTD replay also reopens three packed
checkpoints. Source paths exercised include ordinary road `Station::AddFacility`,
the shared vehicle pool's industrial chimney occupants, freight acceleration
and servicing, `TileLoop_Industry` forest recovery, the stock depot-entry
frame, `LoadUnloadStation` cargo-received triggers and RC1 queue attrition.
This is one active road corridor, not full freight, finance or town-growth
parity. Other cargoes, modes, service densities and municipal interactions
still need comparisons.

The expanded circuit uses an original Balogh Goods Truck and adds a
native road delivery from the sawmill into Slarfinghill. It matches
27,010 consecutive shared RNG ticks, fourteen map and town snapshots
(including the monthly Goods acceptance record), and 23 physical
motion/cargo samples per vehicle. At year end the company has delivered
273 passengers, 80 tonnes of wood and 35 Goods to the town. The replay
reopens three packed checkpoints, and a separate dedicated Luanti run
reopens the actual worker checkpoint at day 128.

At a live junction the next tile and reachable entry directions now seed
the source YAPF choice. The road controller keeps the stock eight-segment
choice cache and discards unreachable entries. Its 3D clearance guard
still protects converging paths, but does not reserve both physically
separated lanes for one straight-moving vehicle. Unordered intermediate
station arrivals and their implicit orders are still unported; this
circuit does not use them.


### Shared depot and an unlisted road stop

The Goods and wood trucks can now start from the same depot. The Goods
truck makes an unlisted stop at the forest freight platform, departs
without advancing its manual destination, then picks up Goods at the
sawmill. LuanTTD uses RC1's station-stop flags and the RoadVehController
stop frame or stopped-leader trigger. The normal transfer is allowed
only at an owned platform for the same vehicle class. Ordered waypoints
remain non-stopping. The distinct-lane and same-path checks prevent a
3D junction's broad occupancy area from holding an otherwise clear
stock convoy; genuinely crossing paths still use the junction guard.

The permanent corridor replay compares 27,010 RNG ticks, 14 world
snapshots, and physical samples at the unlisted arrival, departure and
adjacent junctions. Three packed reopens preserve 265 passengers, 80
units of wood and 47 units of Goods delivered in the first year. The
dedicated native version also matches those totals and the RC1 town
clock across a real SQLite restart. This ports normal unlisted stopping
on road routes; the complete visible implicit list and shared order
cursor lifecycle are not yet ported.


### Rectangular map, Fast growth and 3×3 streets

On a 256×128 Temperate map (seed 98217), OpenTTD counts ordinary coast and both rocky water
subtypes as land when choosing the number of industries. In RC1's
Map::CountLandTiles, IsWaterTile means plain water rather than every
tile of the water class. LuanTTD had excluded coast, causing a missing
25th industry (a steel mill) and a different shared random stream.

The fast-grid replay compares all 25 industry placements and layouts,
six towns, three municipal bridge spans, 14 map/town snapshots and
27,010 random-state ticks against RC1 through the first year. It also
reopens the packed state three times. The no-company run does not cover
the effects of active routes or the other mapped layouts and settings.


### Additional growth settings and municipal excavation

The same full-year comparison also covers a 128×256 Slow-growth Better
Roads region, with 13 automatically selected towns and 25 industries,
and a 1975 256-square Very Fast-growth world with 22 towns assigned
all four stock layouts and 52 industries. Both use normal rivers and
industry. The checks compare 14 map and town snapshots as well as all
27,010 random-state ticks through three packed reopens.

Town-built road tunnels can now lower the shared raised corners on a
dry far portal before installing the tunnel. The controlled RC1
CmdBuildTunnel comparison has the uphill 3 slope, exits at 13, lowers
one corner, and yields the required complementary 12. It matches a
3,815 construction quote at Medium prices and eight shared RNG draws
on commit, with no draws on quote. The transaction refuses to excavate
protected neighboring structures, and does not change player tunnel
construction or support non-complementary exit geometry.


A separate hill-world regression checks an industry footprint with a
river-generated tree. The stock placement quote allowed the tile, but
the host rejected it when no preparatory leveling was needed. Generated
industry placement now clears those trees on the actual footprint before
the host writes it, preserving trees outside the layout.


### Rocky shore and steep municipal leveling

A 256-square hilly Temperate region, seed 1, distinguishes the source
ClearRocks water subtype from plain water. The town road cleanup keeps
a proposed edge pointed at rocky water, as RC1 does, without making
the rocky tile itself buildable. It changes the initial road walk on
the same RNG stream instead of flattening or clearing the water.

Live municipal earthworks can also validate a steep, undeveloped
neighbor independently of house placement. This reproduces the RC1
leveling attempt on tick 10,738 without allowing a house to occupy an
invalid steep footprint. The 47-town, 55-industry annual replay checks
all 27,010 random-state ticks, original industry placement and layouts,
14 map/town snapshots, and three packed reopens. The hills mode of the
dedicated Luanti check also verifies the final stock town clocks and
RNG after a real SQLite restart.


### Changing the growth setting in a running world

A separate OpenTTD 16.0-RC1 run changes Normal to None in February
and None to Very Fast in May using the stock server ChangeSetting
command. LuanTTD uses the same five values, populated from the
world checkpoint. Changing the value does not modify existing
growth counters immediately. Both engines match the growth clocks,
roads, houses, cargo production, and RNG at 20 samples and through
the entire year. The real worker persists None across a SQLite
restart, then applies Very Fast without regenerating the world.
