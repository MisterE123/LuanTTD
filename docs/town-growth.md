# Temperate town growth (isolated OpenTTD 14.1 source port)

The isolated rules return building proposals without modifying the
board. The opt-in live adapter is described below. Source: OpenTTD 14.1
`src/town_cmd.cpp`, `src/town.h`, `src/station_kdtree.h`,
`src/timer/timer_game_tick.h`, and `src/table/town_land.h` (GPL-2.0).
The official source inputs and hashes are checked by the test.

## What the isolated code does

- `openttd/town_growth.lua` implements the stock house-count radius and zone
  rules, station service check, funded/unfunded growth-rate tables,
  city/difficulty multipliers, actual cargo goals, economy month and funding
  state, and 70-game-tick growth counter. Service uses each station sign's
  tile, including another company's station, not its catchment, cargo
  rating, assigned town, or a vehicle visit count. Either actual loading or
  actual unloading can qualify a station through age 20 inclusive. Stock
  station ages advance every 185 game ticks. Unfunded/no-service eligibility
  is a source 1-in-12 monthly draw. A failed build retries after no more than
  70 game ticks, rather than after another full growth period.
- `openttd/town_growth_houses.lua` carries all 31 stock temperate-buildable
  root IDs and stock order, zone mask, years, population, footprint, unique
  church/stadium flags and probability; `openttd/town_growth_build.lua`
  handles the source's weighted selection without replacement, alternate
  footprint checks, and ordinary road-walk/grid inputs.
- Construction starts at stage 0 with no occupants or production. Every
  fourth physical root tile visit all parts advance a stage. The twelfth
  visit completes the building, adding its population once; neither that
  visit nor earlier ones emit passengers/mail. Later visits use the existing
  stock house tile-loop and cargo production.

## Live house-only preview

In a road-first, shared-corner campaign, set `bayline_stock_town_growth = true`.
The default remains off. The preview requires and enables the stock road
clock/loading and source house supply; it is not part of the broad optional
workbenches preset. Existing houses are counted from the real map; their
completed source HouseSpecs determine starting population rather than the
old fictional site totals. Turning the setting off in an existing preview
suspends new starts; houses already under construction still finish, the
stock clocks remain mounted, and the legacy growth threshold stays off.

This first mount takes service dates from real stock road stations only
(passenger, mail and other freight when those paths own the loading
callback). Existing unknown historical station times start at 255; new
stations begin inactive. Station ratings age on their existing 185-tick
phase after the town callback rather than using a second counter. Empty
bus arrival alone is not service. The calendar remains the campaign's
existing 30-day-month, 74-ticks-per-day calendar. The eligibility decision
uses that economy month boundary, not a separate made-up speed.
Non-road station clocks and external scenario goals are not mounted.

Placement is limited to five named original 1×1 types with established
LuanTTD art: cottages, old houses, houses, town houses, and shops/offices.
Only existing roads are walked. A candidate must be unoccupied, ownerless,
dry and flat according to all four shared corners. The final check refuses
independent transport/industry layers, crossings and above/below structures.
No forest, farmland, buildings or terrain are modified. Foundation,
framing and roofing use original stage meshes; surrounding ground remains
unchanged. Clearing a preview house follows the current player construction
rules and updates source house counts and population. Demolition/cost and
town-authority rules themselves are not newly ported by this adapter.

`tests/town_growth_live.lua` covers real bus service, a missed service report
for an empty visit, census, candidate protections, save-copy timing, and
demolition. `tests/town_growth_sqlite.sh /path/to/luantiserver` starts the
real game three times: default-off, enabled with paid bus service, and
restored with expansion disabled. The server verifies native construction
node changes and a SQLite restart in mid framing. On seed 1751 the test
building was placed at tick 2148, saved in stage 1 at tick 3404, completed
at tick 5129 and first generated actual cargo at tick 6409. Those are
fixture observations, not accelerated or hardcoded play mechanics.

## Source adapter contract for further expansion

1. Initialize a persistent `G.new(id,x,z,opts)` state per city, using actual
   authored house roots for `num_houses`, the town sign's square-grid tile
   coordinates, and explicit city/layout fields. Supply existing IDs,
   per-part `house_counts`, unique landmarks and population rather than
   inferring from scene meshes or treating every multipart tile as a house.
   Keep the town state's rate/counter/flags, site records and simulation RNG
   in the same save as actual map changes. Expose a versioned feature flag;
   do not alter the original scenario at load.
2. Use an economy-month change for `G.month(town,stations,setting,rng32)`, not
   an arbitrary simulation interval. Run `G.tick(town,attempt)` once per
   stock game tick at the landscape town callback, after house tile visits
   and vehicle actions. Pass a stable, dense array of indexed station signs
   with `x,z,time_since_load,time_since_unload`. Unknown clocks default to
   unknown service. Reuse existing source station clocks where maintained;
   do not increment them again or count stops merely visited. For modes
   without clocks, increment at the station small-tick phase and reset only
   on actual positive cargo movement via `G.station_move`.
3. Construct `B = dofile(".../town_growth_build.lua")(G,catalog)`. Give
   `B.grow(town,board,{year=calendar_year,allow_roads=false},rng32)` a live
   read-only `board.tile(x,z)` view with compatible kind, source road bits,
   ownership, protection/bridge flags, slope and maximum height. In the first
   mount permit houses only on flat unoccupied town parcels with art vetted
   through `board.house_supported(id,x,z,spec)`. Recheck every proposed tile
   immediately before atomically committing; fail if a right-of-way, yard,
   rail/tram, town marker, industry, crossing, river/levee, or any independent
   layer occupies it. `board.clear_quote` is a non-mutating query and cannot
   make a protected tile clearable. Update model/markers and catchment/RNG
   state for the new footprint together. After commitment call
   `B.house_committed(town,proposal,stations,setting)`; return true from the
   `attempt` callback only once the build actually happened.
4. Store every `proposal.parts` record with its true owner/root coordinates
   and construction state. Call `B.advance_house(h,parts,house_specs,on_complete)`
   in the physical house branch before cargo production, using the existing
   stock tile-loop, not a new clock. Its true result suppresses production
   for that visit. A separate terrain callback that marks a part completed
   immediately before the existing cargo callback needs a same-visit guard.
   Sum real completed populations in the completion hook and recalculate
   catchment/invalidate stat displays where appropriate.
5. Do not enable town road growth until a transaction adapter supplies
   `road_quote(town,x,z,bits)`, `clean_road_bits(town,x,z,bits,approach)`,
   and the source `road_allowed(town,x,z,travel,rng32)` query for the
   original/better layouts. It should quote/commit existing ordinary
   municipal road and corner data atomically and invalidate the directed
   route caches without touching player infrastructure. A flat cleared
   seed-road proposal is supported without a cleaner, but success still
   requires a real host command.

## Verification and boundaries

```sh
lua5.1 tests/town_growth.lua
TMPDIR=/path/to/qa_temp python3 tests/town_growth_upstream.py /path/to/OpenTTD lua5.1
```

The differential compiles the actual scheduler, spatial service/radius,
town zone, weighted selector and stock footprint functions against minimal
board/clock shims. It checks 12,000 rate/radius/service cases, 6,500 scheduler
cases, every original catalog row, and 7,000 site selection cases covering
year, nearby hazards, layout, multi-tile height, existing unique buildings,
and draw count. The Lua fixture drives source-style road walking into a
building, asserts actual multipart ordering and population, and uses the
existing passenger production after completion.

This is not full-world OpenTTD growth parity. The road/lot search has focused
fixtures, not a whole native growth differential. The detached/house-only path refuses
automatic terraforming/clearing, bridge/tunnel creation, crossings, competing
town road expansion, non-temperate goals, NewGRFs, and existing house
replacement or decay. It returns one safe plan per attempt, even where the
stock search can perform an extra-house build before continuing. Any broader live mount (road building, more house types or more station modes)
needs independent timing, save/load and visual QA. See the separate
[ordinary municipal road adapter](town-growth-authority.md#municipal-streets-on-ordinary-generated-maps)
for supported live streets and spans.

## One growth callback per stock tick

The live owner still checks every town in ascending TownID order on
each stock tick. It now shares one callback across those checks, using
the town argument supplied by the original growth countdown. The board
and station view remain lazy and shared only for that tick. This does
not change when a town can grow, add roads, or draw random numbers.

On one generated 1024×1024 campaign, allocation tracing isolated
**10.824 MiB → about 0.030 MiB** of temporary Lua allocation per game
day in the town tick. Two alternating native Luanti 5.15.2 runs measured
median overall daily worker CPU of **759 → 711 ms** and **772 → 680 ms**.
At the same completed day, all 1,559,990 checked state tables and alias
mappings, including 1,048,576 tiles, were equal. These are measurements
for that campaign, not a claim about client frame rate.

```sh
lua5.1 tests/town_growth.lua
lua5.1 tests/town_growth_live.lua
lua5.1 tests/town_rebuild.lua
tests/campaign_tick_worker_native.sh luantiserver /tmp/town-tick-check
```

## House cargo without per-tile callbacks

Pass the tile coordinates, house, and tick to a shared cargo sink rather
than allocating a closure for every visited house and another for every
production pass. The sink skips catchment lookup entirely when no bus
stops exist and allocates a ratings list only when a stop qualifies.
Stock random draw order, cargo scaling, and rebuild order are unchanged.

On a generated 1024×1024 campaign, allocation traces removed roughly
**2.0 MiB per simulated day**. Two 50-day alternating native Luanti
5.15.2 runs measured median daily worker CPU of **627 → 539 ms** and
**645 → 575 ms**, with peak process RSS about **124–127 MiB** lower.
The longest single day was slower in the two optimized runs, so this
is a steady-state gain rather than a guarantee against individual stalls.
Complete saved state (including shared references) matched at the same
completed day in the 1024×1024 campaign and a 128-vehicle mixed campaign.

```sh
lua5.1 tests/town_passengers.lua
lua5.1 tests/town_passenger_runtime.lua
lua5.1 tests/road_mail_runtime.lua
lua5.1 tests/town_growth_live.lua
```
