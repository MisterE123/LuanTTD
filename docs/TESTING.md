# Release validation

The Linux test used Luanti 5.10.0 from Debian packages, a loopback dedicated
server, and a real desktop client rendered in a temporary Xvfb session.

- **Simulation:** Lua 5.1 regression suite. 127 assertions plus per-seed asserts
  for 100 map seeds. The suite checks delivered passenger/mail/freight cargo,
  all four transport modes, the coal-to-steel chain, cross-mode transfers
  without premature payout, traffic reservations and posted rail hold signals,
  construction rollback, competing ownership, loan handling and model unlocks.
- **Persistence:** Native server test generated a station node, paid a fare,
  shut down with a bus in transit, reopened the same SQLite world, matched the
  saved route, orders, progress and finances, and earned another fare. The
  headless probe also verifies that the core simulation is not tied to active
  visual mapblocks or vehicle entities. A second world verified two following trains preserved headway across a restart and both paid passenger fares.
- **Native GUI (v0.1.0 baseline):** In a blank world, placed road and two stops using the map tools,
  bought a bus, selected its destination in the dropdown, added the order,
  dispatched it, and saw fare revenue and delivered cargo in Finance. In a
  second world, built the starter line, saw its vehicle marker and financial
  results, and opened the 3D survey.

Engine screenshots, when supplied separately, are from the actual test client,
not from a browser imitation. All other test data stayed in throwaway worlds.

## 3D milestone (v0.3.0)

Native Luanti 5.10.0 Linux client: entered the world with the hotbar visible,
opened the Inventory and the right-click palette, dispatched the starter route,
saw the Blender bus running on its road, flew the camera, selected Road, and used
two separate world clicks to build and pay for a three-tile road. The server
test additionally checks world targeting, directly building a road and terminal,
and that all ten vehicles have registered OBJ meshes. Existing rail, economy,
and restart tests still pass.

Private reference run: OpenTTD 14.1 with OpenGFX 7.1. Both a seeded new world
and the shipped title network ran on Linux. The latter shows moving vehicles
at multiple elevations, readable station names, waterfront activity, and
visually varied terrain and towns. This was a visual baseline, not a measured
performance or matched-route comparison. Those files are not shipped here.

## Unreleased fidelity work

- Core regression: `lua5.1 tests/sim.lua`, 138 assertions after adding
  depot access, ownership, orders, departure and actual paid service.
- Dedicated Luanti 5.10.0: all five integration phases passed. In the
  disposable graphical Linux fixture, straight road, corner, four-way
  junction, and roadside shelter displayed a continuous road surface, and
  a real simulated bus produced actual fare feedback. The fixture was
  prebuilt, not a fresh-world UI service playthrough. No sloped road test
  or release-grade playthrough has passed yet.
- `python3 tests/slope_upstream.py /path/to/OpenTTD-14.1 lua5.1` compiles the
  two pinned upstream C++ functions verbatim in a test harness and checks
  the Lua classifier and integer height samples. The smooth sampler is
  checked at the corners of all legal generated shapes. Neither the
  sampler nor the foundation transform is wired to the legacy scene yet.

### Road architecture checkpoint

Blender 4.3.2 source exports and `python3 tests/road_asset_meshes.py`:
seven native-scale mesh files; the shelter placements stay outside the
asphalt. The engine integration verifies mesh registration and readability.
In a graphical Luanti 5.10 fixture viewed from survey and street angles,
checked the front bay lined up with the connected road, shelter bench,
curb and sign were visible, and the bus collected passengers and earned
fares. This is not a new release or a pass for the remaining scenery.

### Integrated scenery, terrain port and native flat service

- `python3 tests/scenery_meshes.py`: 13 original Blender assets exported in
  native mesh-node units, checked for grounding, triangulation, material UVs
  and footprint; the native service run also showed the new homes and trees.
- `lua5.1 tests/terrain_rules.lua`; `lua5.1 tests/terrain_view.lua`:
  corner-grid legality and transactional planning; continuous and diagonal
  surface intersection. `lua5.1 tools/build_terrain_meshes.lua` verifies
  the triangulation of all 18 terrain shapes against the sampler.
- In Luanti 5.10, inspected a grassy coastal hill in 3D at survey and
  street height. This mode does not allow players to edit the shared corner
  grid and does not port construction or ramp driving yet.
- `python3 tests/terrain_rules_upstream.py /path/to/OpenTTD-14.1 lua5.1`:
  800 matched cases of upstream corner edits and propagation.
- `python3 tests/road_slope_upstream.py /path/to/OpenTTD-14.1 lua5.1`:
  155,952 cases matching the foundation and road-piece rules.
- `python3 tests/income_upstream.py /path/to/OpenTTD-14.1 lua5.1`: 57,600
  cases matching the ordinary cargo payment branch. NewGRF callbacks are not
  implemented; the legacy game still uses its original payout while the port
  waits for cargo-distance and transit-age integration.
- `tests/native.sh`: use real desktop mouse/keyboard commands in graphical
  Luanti and a deterministic camera-only aid in a disposable copy. Built 10
  flat road tiles, two stops and a depot; purchased a bus; picked two stop
  orders in 3D; started service; earned $781 from 30 passengers. Restarted
  and reached $1,302 from 60 passengers with orders and road intact. Repeated
  on the integrated scenery and non-overlapping palette. The OpenTTD
  side-by-side service and sloped road driving remain release gates.

### LuanTTD road-grade integration (unreleased)

- OpenTTD-derived half-road construction and foundations now operate on the shared corner grid.
- `lua5.1 tests/road_build.lua` covers ramps and foundations, rejection without
  spending, flat crossings, parallel-road separation, reciprocal edge/grade
  checks, and a working depot-to-stop bus. World prices, unsupported
  structures, and exact traffic behavior are not OpenTTD-equivalent yet.
- `python3 tools/build_sloped_road_art.py` checks 16 bitmask textures and 512
  compatible edge pairings. Road ramps are sloped geometry, not upright blocks.
- `BAYLINE_NATIVE_GRADE=1 tests/native.sh` starts a disposable Luanti world with
  two known ramps. It builds and runs the route through the actual client,
  checks bus position and pitch against the ramp geometry, and restarts with
  the preview setting turned off to ensure the saved world retained its grid.
  The fixture is not the stock OpenTTD side-by-side acceptance run.
  In the LuanTTD client the two ramps joined the flat road continuously,
  and high/low views confirmed the corrected physical bus tilt in both
  directions. The route carried 30 passengers for $781, then 60 for
  $1,302 after restart, with the preview flag removed on reload.

### Fresh-world road-first playtest

`BAYLINE_NATIVE_FRESH=1 tests/native.sh` uses the default player profile and
normal world generation (seed 1751, no terrain replacement). The
test observes state but cannot invoke the aim teleport in this profile. It
uses ordinary relative mouse look from the same spawn as a player, keyboard
hotbar selection, direct 3D construction, and ordinary control windows. Verified a 10-tile road, both bus stops, depot,
purchase, physical stop picks, 30 passengers and $781, then restart with the
route carrying 60 passengers cumulatively and earning $1,302. This remains
one tested startup path, not general OpenTTD parity or a release.

#### Stock comparison, OpenTTD 14.1

In a separate unmodified Linux 14.1 session, seed 1751, built a three-tile
extension and two drive-through stops in Defingley, chose depot orientation,
purchased a MPS Regal Bus, placed two world orders and started service. The
bus reached a stop and the game displayed its first-service news. This is a
workflow comparison, not a matched map, distance, costs, or timing test.
Two high-value differences: stock towns have streets before players build;
and the station tool exposes acceptance/catchment before committing.
LuanTTD now shows planning cost and the nearby source in the 3D bus stop
preview. Denser functional streets, stronger catchment feedback, and
like-for-like timing and finance comparisons remain worth doing.

Stock service follow-through: the OpenTTD bus carried 16 passengers in the
inspected frame, and its company ledger recorded +£89 road-vehicle revenue.
The first arrival was visible about 8 seconds after dispatch. Revenue
was still zero around +64 seconds and was positive by +82 seconds. This was a
within-city route, not a benchmark against LuanTTD's inter-town corridor.
Passenger queues began empty in the stock run; our prototype's immediately
available catchment stock makes the first fare arrive earlier.

### Public streets and starter settlements

- `lua5.1 tests/town_layout.lua` checks the two authored town neighborhoods
  across 60 seeds: sidewalks and parcels don't replace playable street
  topology, all municipal edges join, and the indicated starter right of way
  remains open. These are authored starting towns, not a port of town growth.
- `lua5.1 tests/municipal_roads.lua` checks public/private routing, grade
  joins, stops and depots on public access, acquisition and safe removal,
  and service across municipal streets. Public streets are protected in
  this build; the upstream town-authority demolition rules are not ported.
- In the shared-corner rules, bus stops on existing corners and junctions
  are rejected as they are by OpenTTD's drive-through stop tool. The private
  single-half-line starter end stop remains a local variant, not a full port
  of OpenTTD's orientation/bay placement UI.
- `python3 tests/town_prop_meshes.py` checks the original market, corner
  shop and green. `python3 tools/build_town_streets.py` validates asphalt
  pixel alignment while generating the sidewalk surfaces.
- Re-ran the road-first mouse-only route on the integrated town build in
  Luanti 5.10: completed all player actions, inspected Port Alder at the
  lower camera altitude using normal Shift/mouse input, then restarted.
  The original stops, orders and service survived and reached 90 cumulative
  paid passengers. Reviewed survey and street-level images for the new
  parcel silhouettes, open sidewalks and road joins.

### Passenger service and fare integration

- `lua5.1 tests/passenger_economy.lua` exercises initially empty queues,
  service activation, a paid trip between two stops in the same town,
  source/age retention through transfers and upstream allocation vectors.
- The default fresh-world Linux mouse-only run asserted both stops started
  empty, caught the first bus arrival before revenue, observed passengers
  board, and checked a genuine fare. On the test's 10-tile route the first
  paid trip carried 15 people for $76; after restart it reached 60 riders
  and $281 total. These are LuanTTD results with the test clock, not exact
  OpenTTD travel-time or finance parity.
- The two original arrival and fare cues are validated mono Vorbis assets.
  The graphical harness disables audio, so it does not validate listening
  balance. The events were verified in game via the overlay and state.

### Rounded road turns

`lua5.1 tests/road_motion.lua` verifies render-only turn tangent and
continuity through the asphalt, without changing simulated travel or
rounding a station or slope. `BAYLINE_NATIVE_FRESH=1 BAYLINE_NATIVE_TURNS=1
tests/native.sh` built an 11-tile L-shaped route and observed a live
intermediate bus pose (x 36.486, z 24.732, yaw 0.242 radians) inside the
paved bend rather than only an instantaneous heading snap. It also
verified fares and resumed service after restarting.

### Station-rating kernel (not wired into gameplay yet)

`python3 tests/station_rating_upstream.py /path/to/OpenTTD-14.1 lua5.1`
compiles pinned stock `UpdateStationRating` in a fixture. Checked 28,000
conditions including callback-field decoding, random queue loss and pickup
expiry, and checked the pinned constants. The port does not yet replace
the road campaign's initial allocation rating. The next integration needs
per-stop timer persistence and actual load/no-load/full-bus state changes.

### Camera flight regression

`BAYLINE_NATIVE_FRESH=1 BAYLINE_NATIVE_CAMERA=1 tests/native.sh` compares
identical mouse sweeps while stationary, flying forward, ascending and
descending in Luanti 5.10. The old implementation sent 89 absolute move
packets and retained only ~35% of the stationary yaw sweep while moving
forward. The corrected build sent four packets during initial spawn only,
retained ~94% during movement, kept the full range of pitch response, and
showed no altitude drift after release. The bus construction and
restart flow also passed with the new movement. Movement does not require
granting flight privileges or changing the user's engine settings.

### Section hotbars, true tile selector and road presentation

- `lua5.1 tests/hotbar.lua` checks that each of the six section buttons opens
  a tool hotbar and Back pops one level even for nested menus. Bulldozer,
  Switch Bend and Cancel Line are actual Roadworks tools.
- `lua5.1 tests/tile_selector.lua` checks all 19 2×2 profiles, matching the
  actual terrain/road surface, and private per-viewer markers. In the native
  profile the engine's small black voxel outline is disabled.
- `lua5.1 tests/road_lanes.lua` checks model widths and swept footprints,
  right-side lane offset, depot entry and corner tapers. `tests/road_motion.lua`
  checks model nose orientation and bounded shortest signed rotation at
  the angle wraparound. This is the 3D presentation, not a pathfinder port.
- `lua5.1 tests/passenger_crowd.lua` checks one figure per waiting person
  within the available platform space, small randomized spawn offsets, zero
  motion, no double figures and a same-position opacity fade on boarding.
  A straight 1.7-node curb has room for 32 with two staggered rows; smaller
  curved shelters fill sooner and the station marker gives the exact count.
  Short opaque leases (0.41 to 0.56 seconds) stay visible until their lease
  ends. Removed figures take a 0.36-second alpha fade rather than renewing.
  The native Lua API sends single-particle texture tweens on Luanti 5.10.
- Linux fresh-world mouse-only test validated opening Roadworks, Back,
  building and bulldozing a temporary road, real stop indicators, an 11-tile
  turn and a bus narrow enough to fit its side of the road. Service earned
  fares after restart. The native fixture observed the moving model and
  actual local particle emissions, not merely planned positions.

### OpenTTD road follower port (model-only)

`python3 tests/yapf_road_follow_upstream.py /path/to/OpenTTD-14.1 lua5.1`
compiles the pinned upstream transition code over synthetic tile/vehicle
records and checks 34,000 road track-status and CFollowTrackRoad cases.
This particular test covers the follower only. See the live integration checks below.

### Road YAPF cost and destination

`lua5.1 tests/yapf_road_cost.lua` checks cost and estimate formulas with the
real translated directional follower, including a junction segment boundary,
an integer speed penalty, uphill threshold, depot entry, stop continuation,
two bays, bridge skip, articulation and closest station rectangle.

`python3 tests/yapf_road_cost_upstream.py /path/to/OpenTTD-14.1 lua5.1`
compiles unmodified `CYapfCostRoadT` from the hash-pinned upstream source
against a synthetic tile/follower shim and compares 24,000 seeded scenarios.
It checks the actual segment end tile, direction and cost, or rejection. It does
not compare the YAPF search, station occupancy in a live world, or drive a bus.

For the live search test, set up a straight flat east–west road, with a fork
at x=1 and rejoin at x=5, and an alternate route one row away between them.
Order a bus to a destination beyond the rejoin. In the baseline there is a
plain road at (3,0). In the alternate scenario change only (3,0) to an empty,
aligned drive-through stop that is **not** in the bus orders. Use a fresh
vehicle to avoid a cached choice and record the chosen branch and arrival in
both OpenTTD 14.1 and LuanTTD. The source-derived expectations are the short
route first (500 versus 984 through the rejoin), and the long route with the
extra stop (984 versus 1,300). The Lua cost test represents this scenario; see the running-engine checks below. A follow-up
should remove a cached junction exit while leaving an alternate path open.

`python3 tests/yapf_road_search_upstream.py /path/to/OpenTTD-14.1 lua5.1`
compiles the unmodified upstream generic YAPF controller and binary heap over
controlled follower, cost and estimate inputs. It compares complete expansion
order, closed counts, route found status and best parent chains in 10,000
seeded searches with both stock node-key modes. `yapf_road_cost.lua` also
checks actual segment search and choices over the synthetic two-route map,
including cached-choice invalidation after removal of a junction exit.
This test isolates the controller and heap; it does not measure native vehicle movement.

The native fresh-world passenger check requires a real bus boarding event,
private standing-particle emissions, and same-position alpha-fade requests in
a congested queue. Counts up to curb capacity are represented directly; above
capacity, a boarding event consumes a proportional visible sample even if the
remaining queue still fills the platform.

`lua5.1 tests/road_yapf_board.lua` uses saved LuanTTD tile records (not the
direct abstract fixture) to run the stock road port over an east/west fork,
depot, private end bay and intermediate through stop. It exercises stock
direction and coordinate mapping, reversal, geometry across road ownership
boundaries, and direction-specific queue length and bay occupancy hooks.
Its separate runtime integration is driven through native departure, movement and fares below.


### Live road YAPF comparison (OpenTTD 14.1 and Luanti 5.10)

Run `python3 tests/openttd_yapf_runtime.py /path/to/openttd /path/to/share/openttd`
with installed language and baseset assets (OpenGFX by default). A small AI
builds two equivalent four-tile-spaced road forks on verified flat land,
buys stock buses and records the tile sequence through each fork. It starts
fresh each time, binds on loopback only and does not change the engine.
Stock OpenTTD took the straight fork when clear and the longer branch when
the short fork contained an unordered drive-through stop.

With `BAYLINE_NATIVE_FRESH=1`, repeat `tests/native.sh` with
`BAYLINE_NATIVE_YAPF=plain` and `BAYLINE_NATIVE_YAPF=stop`. Both use mouse
and keyboard to build a flat fork of the same size, place stops, buy a bus,
set orders and run service. The observer verifies the actual bus mesh reaches
the corresponding branch. Approach geometry and orders outside the fork vary;
this demonstrates the tested branch choice, not time or full traffic parity.
The visual test retains boarding, positive fare and save/restart checks.

## Native bus movement, station ratings, and Trackworks

- `python3 tests/road_motion_upstream.py /path/to/openttd-14.1/src` checks generated
  movement tables and differential headings/commits using upstream source.
  Pass the folder containing `roadveh_movement.h` directly, alongside
  `roadveh_cmd.cpp` and `direction_func.h` (copy the header from `src/table`).
- `lua5.1 tests/road_yapf_board.lua` verifies an actual source route converts to
  depot, bay, through-stop and corner frames without position jumps. It
  checks the two rotation-only frames in an inside bend.
- `lua5.1 tests/station_rating_live.lua` drives the real daily simulation
  through a fare, station expiry and a new service. The stop's rating
  changes which stops attract local passengers and how queues are reduced.
- `BAYLINE_NATIVE_FRESH=1 BAYLINE_NATIVE_PASSING=1 tests/native.sh` plays the
  normal road scenario and verifies save/reload. For the final local test
  only, it dispatches a second bus in opposition; the two actual meshes
  must pass at the right lane offsets with positive clearance.
- `BAYLINE_NATIVE_FRESH=1 BAYLINE_NATIVE_TRACKWORKS=1 BAYLINE_NATIVE_GRADE=1 tests/native.sh`
  uses the opt-in in-game commands to build flat and graded 3D track,
  including a curved and a parallel arrangement, and confirms that the
  graphical world loads the same track nodes again after restart.
  `python3 tests/rail_art.py` checks all supported asset masks and edges.
  These are track construction tests, not a running train service.

`tests/road_speed_upstream.py` compares 24,000 exact speed, sub-speed,
directional distance, and accumulated progress cases and tests a blocked
retry. `tests/town_passengers_upstream.py` checks all 110 vanilla house
archetypes, 18,000 production traces, and ten tile schedules.
`tests/town_passenger_runtime.lua` exercises the authored house mapping,
selective allocation, and three-tile Chebyshev catchment together.
Fresh native profiles verify both runtime flags and a paid fare; use the
flags `BAYLINE_NATIVE_STOCK_CLOCK=0` and `BAYLINE_NATIVE_STOCK_HOUSES=0` to
rerun the pre-port behavior on a disposable fixture.

`tests/rail_yapf_cost_upstream.py` and `tests/rail_yapf_search_upstream.py`
compile the pinned stock template and compare rail costs, destination
decisions and exact search order. The Trackworks graphical test uses
`/trackroute` to survey seven real built pieces, then invokes `/trackrun` and observes the native
locomotive mesh on the first arc and final straight. `tests/rail_motion_upstream.py`
checks the stock per-piece kinematics; the proving run has no stock train
acceleration, traffic or orders.

`BAYLINE_NATIVE_QUEUE=1` holds a genuine bus at its stop, dispatches a
following bus from a depot, and then releases the leader. The follower
waits for two simulated days before release and stays at the same stock
coordinates, then reaches that station. `tests/road_traffic_runtime.lua`
also checks same-lane traffic, opposite lanes and simultaneous depot
departure on the interleaved tick loop.

`BAYLINE_NATIVE_TRACKWORKS=1 BAYLINE_NATIVE_RAIL_FACILITIES=1` builds real
rail station/depot meshes and an ordered pilot. Stops the server with the
pilot moving; after restart the same locomotive reaches its precise
platform location. No multiple-train operation is enabled.

`BAYLINE_NATIVE_LANDSCAPE_BRIDGE=1` uses the hotbar and mouse to check a paid terrain corner edit and
a two-click timber bridge with a price preview, verifies both head meshes and every interior deck
mesh, and confirms the raised corner and structure reload. The dedicated
`BAYLINE_NATIVE_BRIDGE_RUN=1` fixture sends a bus across, verifies the
native mesh at deck height, pays a fare, restarts, and repeats. The wood bridge artwork checks grade and seams in
both axes. `BAYLINE_NATIVE_LEOPARD=1` buys the later real bus and runs the
standard passenger-service trial in an era where the model is available.

`BAYLINE_NATIVE_BRIDGE_RUN=1 BAYLINE_NATIVE_STEEL=1` repeats the paid route
and restart on the steel-girder catalogue style 2.
`tests/road_mail_service.lua` verifies real depots, selective truck-stop
orders, house-level mail, separate ratings and actual fare in simulation.
`BAYLINE_NATIVE_MAIL=1` exercises the optional postal loader meshes and the
purchase, orders and paid delivery of an actual mail van in native Luanti.

`tests/road_tunnel_upstream.py /path/to/tunnelbridge_cmd.cpp` compares
4,530 source construction costs and four entrance visibility frames.
`BAYLINE_NATIVE_TUNNEL_RUN=1` verifies a moving bus hides inside the hill,
emerges at the correct lane and elevation, and earns fares after reload.


### Native concrete bridge and electric tramway checkpoint

- The short concrete bridge uses original editable Blender art and stock
  style ID 1. Structural tests check 144 seams, 30 matching road-surface
  profiles and lower-road clearance in both orientations. The dedicated
  Linux Luanti test showed real passengers traveling on the elevated concrete
  deck at 1.52 nodes and paid counts of 14 before restart and 28 after.
- In the Linux tram test, used actual mouse targeting and the Tramways
  hotbar to lay paid track, rotate the platform direction, and build a
  depot and two passenger platforms. The same single streetcar ran through
  the junction and the timetable-free pilot alternated through stops
  after both one-half turnaround stubs. It served the first two stops,
  survived a real SQLite server restart, and reached its fourth stop.
  The test asserts complete native depot/junction/platform meshes and the
  streetcar's wheel datum. It does not claim live mixed traffic or cargo.
- Native profiles: `BAYLINE_NATIVE_FRESH=1 BAYLINE_NATIVE_TRAM=1 tests/native.sh`
  and `BAYLINE_NATIVE_FRESH=1 BAYLINE_NATIVE_BRIDGE_RUN=1 BAYLINE_NATIVE_CONCRETE=1 tests/native.sh`.


### Native coupled railway crossing checkpoint

`BAYLINE_NATIVE_FRESH=1 BAYLINE_NATIVE_RAIL_DISPATCH=1 tests/native.sh`
builds two independent straight track directions through a diamond, places
two directional path signals from the real Linux client, and orders two
coupled locomotives to separate platforms. The observer freezes the test
only when the first train's head has left and its rear carriage alone still
holds the crossing. At that snapshot the opposing signal and lamp entity
remain red, the opposing train waits, and four moving-stock mesh objects
exist. The test restarts the actual engine/database at this same point,
verifies the persisted state, and shows the other locomotive proceed only
after the tail event. Both arrive at different platforms. This tests PBS
admission and physical reservation release for the pilot, not the whole
OpenTTD signaling or rail service system.


### Native tick-based road service and ferry checkpoints

- Tick-based loading preserved boarding effects and payouts in native GUI
  bus and post van services. A follower yielded outside an occupied bay,
  preserved separated poses through a restart, and entered after the
  leader cleared. Fresh opt-in passenger fares reached 8 before restart and
  29 after; mail bags increased from 5 to 12. The mail fixture observed a
  saved arrival at tick 3943, payment at 3964 and onward departure at 3984.
  Invoke native profiles with `BAYLINE_NATIVE_STOCK_LOADING=1` plus
  `BAYLINE_NATIVE_FRESH=1` and either `BAYLINE_NATIVE_QUEUE=1` or
  `BAYLINE_NATIVE_MAIL=1`.
- `BAYLINE_NATIVE_FRESH=1 BAYLINE_NATIVE_SHIP=1 tests/native.sh`: built
  two complete docks and a two-tile depot via mouse on the default
  coastline; the real native ferry mesh sailed at the actual 0.50-node
  waterline. It moored at a navigable berth next to the first pier and
  continued to the other dock after a server restart. Fourth docking
  occurred after 246 stock movement steps. The source movement test
  additionally exercised locks and aqueducts off the native campaign.


### Reverse shuttle and elevated aqueduct

- `BAYLINE_NATIVE_RAIL_SHUTTLE=1 BAYLINE_NATIVE_FRESH=1 tests/native.sh`:
  one coupled locomotive and coach switched direction twice. The first
  east visit occurred at stock tick 468, a real restart preserved the first
  reversal, and the next west/east arrivals were ticks 928 and 1388.
- `BAYLINE_NATIVE_AQUEDUCT=1 BAYLINE_NATIVE_FRESH=1 tests/native.sh`: built a
  5-tile aqueduct for $70,000 in the prepared valley, dug the missing elevated
  canal approach, ordered the ferry at real docks, and observed it traverse
  the raised water surface at 1.5 nodes. Ground road and river nodes remained
  independent below. The ferry reached the other ordered dock. Channel and
  underpass clearance are separate Blender/native asset tests.
- `lua5.1 tests/ship_ordered_berth.lua`: the ship passed a closer unordered
  dock without loading, resumed from a serialized mid-route position, and
  found an alternate valid berth at the intended dock.


### Moving lock and uphill/downhill ferry

`BAYLINE_NATIVE_LOCK=1 BAYLINE_NATIVE_FRESH=1 tests/native.sh` builds a
three-part lock with the actual hotbar. At a stock intermediate height of
3/8, Luanti measured both the ferry datum and movable chamber surface
at 0.875 nodes with two distinct closed gate objects. This exact status
survived a server stop and SQLite world reload. The ferry continued
uphill to one berth, sailed back downhill through the same lock, and
reached the other berth. The original gate and wall models additionally
passed continuous hull/draft clearance and exact water-seam checks.


### Native airfields and saved flight

`BAYLINE_NATIVE_AIRFIELD=1 BAYLINE_NATIVE_FRESH=1 tests/native.sh` places two
country airports using normal hotbar and mouse on the default coastline.
The dedicated server saved the actual airborne positions and target at
stock tick 325. The client measured the original airplane mesh at 22.875
nodes of elevation, then after a real engine restart observed touchdown,
ground taxi to a stock stand at 0.5 nodes, and completion of a return leg.
The pinned FTA separately tests runway/stand contention and near/far
taxi roles, without claiming commercial or multi-plane service.


### Native paying ferry service

`BAYLINE_NATIVE_PAID_FERRY=1 BAYLINE_NATIVE_FRESH=1 tests/native.sh` uses
two physically modeled docks serving ordinary stock households.
The ferry docks in adjacent navigable water, takes actual timed pickups,
unloads, settles fares into company accounts and continues the next
settlement after a SQLite shutdown/restart. The test verifies delivered
units and money against the passenger service ledger and verifies one
matching house, road loading and paid ferry station clock. The pure suite
also saves during unloading, verifies no duplicate fare, and checks
stock-day motion increments.


### Native coupled train on grades

`BAYLINE_NATIVE_RAIL_GRADE=1 BAYLINE_NATIVE_FRESH=1 tests/native.sh` uses
one natural shared-corner ramp up to a one-level crest and a second ramp
down to an ordinary destination platform. The locomotive and coupled
coach have separate stock height samples and ride each authored rail
profile. The graphical client observed opposite ±atan(1/2) pitches;
a real restart while partway up preserved the pitch state, and the
train descended and reached its platform. Unsupported rail foundations
and graded facilities remain outside the preview.


### Native passenger rail and ferry on one world clock

`BAYLINE_NATIVE_PAID_RAIL=1 BAYLINE_NATIVE_FRESH=1 tests/native.sh` runs a
real coupled shuttle and ferry concurrently. Both collect passengers
from one source-house stream and pay into the same company account.
The engine saved and reopened the shared world and both settled more
passengers afterward. The test reconciles the two mode ledgers to the
one company, and verifies matching station, house and road clocks. A
separate full-world Lua fixture runs paying bus, rail, and ferry together
and checks actual carriage position, berth distances, timed incremental
boarding, separate owners and no date/production duplication.


### Paid direct railway construction in 3D

`BAYLINE_NATIVE_RAIL_BUILD=1 BAYLINE_NATIVE_FRESH=1 tests/native.sh` uses
the actual hotbars to place a bare-ground depot ($720), drag thirteen
rail tiles ($1,560), place a three-tile platform on existing track
($1,050) and place a path signal ($65). The test then chooses the
depot and platform by mouse to dispatch the real coupled train and
observes it arrive. No coordinate commands build or dispatch the line.
The pinned quote differential covers 46,204 construction/safety cases.


### Stock coal freight, industry art and payment

`tests/road_coal_live.lua` checks the mine's stock clock, physical placement,
stop supply and acceptance, the loaded road vehicle, finance, and restore.
`tests/coal_industry_upstream.py` and `tests/road_coal_service_upstream.py`
compare the covered ordinary source branches against the pinned reference.
In the real Linux client, use the optional freight hotbar to construct loading
stops, purchase the coal tipper, assign both stock destinations using world
clicks and start service. The physical loaded mesh moves beside the animated
mine, the power plant consumes exactly the delivered tons, and payment persists
through a real SQLite world restart (20 t/$140, then 40 t/$280 cumulative).
Run with `BAYLINE_NATIVE_FRESH=1 BAYLINE_NATIVE_COAL=1 tests/native.sh`.


### Orders in the world, outlined footprints and paid fixed-wing service

Native Luanti: construct and dispatch a ferry by clicking an actual owned
depot and both docks in **Ferry Operations**. A restart preserves the ferry
and the next bank-side berth instead of routing onto a pier. Another native
run uses **Order trimotor** to pick both 12-tile fields with no route command.
For the paid case, build beside two actual towns in a new default-seed world.
Restore the airborne aircraft, land and board at real terminal tiles, earn
25 passengers/$122, then restart and see 50/$243 cumulative. The amount is
identical in the airline status and company ledger; the town and station
counters run on the same source tick. The timed source flight/cargo tests
enforce the supported role and do not claim air mail or competing aircraft.

`BAYLINE_NATIVE_FRESH=1 BAYLINE_NATIVE_PAID_AIR=1 tests/native.sh`


### Vehicle passing and railway span builds

Ordinary stock road overtaking is mounted only on a fully verified straight
road window. Lua differential fixture compares 53,632 source decision,
controller timer and cancellation cases. Graphical fixtures use two actual
vehicle meshes, stop or move the leading bus, save the overtaker on the
opposite lane and restore it on that lane. The same model returns to its
normal lane. Current road/station regressions retain ordinary yielding.
Curves, stop tiles, articulated vehicles, bridges and tunnels are not
passing zones. The host adds an explicit conservative anti-overlap check;
stock comparisons do not describe that host guard.

`BAYLINE_NATIVE_FRESH=1 BAYLINE_NATIVE_OVERTAKE=stopped tests/native.sh`
(or `BAYLINE_NATIVE_OVERTAKE=moving`)

The native Rail Engineering fixture uses prepared terrain and connecting
rail, then builds timber bridge and paired tunnel portals with mouse
clicks, orders a locomotive and carriage by mouse, pauses and restores
on the actual bridge deck. Both cars hide and return at correct ends,
the rear releases each run of reserved track, and the train reaches its
platform. Stock source differential and render clearance tests are separate.

`BAYLINE_NATIVE_FRESH=1 BAYLINE_NATIVE_RAIL_SPAN=1 tests/native.sh`


### Road–rail crossing in the real desktop client

Native Luanti uses existing terrain/approach fixtures, then places the
crossing and dispatches a train by mouse. It charges $100 for the stock
rail-over-road branch. A real bus already inside causes rail to wait while
red lamps and closed arms render. A native SQLite restart retains both
movements and the red gate; an opposing bus waits outside. On resuming,
a carriage alone keeps the gate down. After it clears, the gate opens,
the train reaches its platform and the waiting bus reaches the far stop.
Supported cardinal mesh extents are checked for separation during the
two yield states. The isolated compiled test checks stock branching;
the safer physical-admission rule belongs to the Luanti host.

`BAYLINE_NATIVE_FRESH=1 BAYLINE_NATIVE_CROSSING=1 tests/native.sh`

The optional `lua5.1 tests/rail_paid_runtime.lua air` fixture settles
all four separately owned modes on the same 74-tick clock after two
reloads: bus 175/$385, rail 141/$531, ferry 77/$231, and air 25/$147.


### One-way physical route guard and owned steam

`BAYLINE_NATIVE_FRESH=1 BAYLINE_NATIVE_ONEWAY=1 tests/native.sh` performs
the actual east-oriented drag with mouse input. The client sees both the
stock boundary signs and interior paint. YAPF routes the allowed way, but
not the prohibited way. The same drag restores both directions. Change
a sign in front of a bus already committed to the old direction, save at
its physical hold, reload, reopen it by mouse and verify the bus reaches
its original stop. The Lua fixture independently tests an exact same-pose
detour and the pinned C++ differential covers 18,000 source cases.

`BAYLINE_NATIVE_FRESH=1 BAYLINE_NATIVE_RAIL_OWNED=1 tests/native.sh` uses
prepared track and catchments, opens a real depot with Inspect, pays the
exact $12,866 price of stock IDs 0 and 27, picks two distinct platforms in
the native scene and restores a real original steam locomotive and active
carriage while passengers board. An independent isolated native fixture
proves correct train ID, fare, reversal and position state after restart,
and the Lua span test includes running the same owned train over a
timber bridge, through a tunnel and across a level crossing.


### Rail coal loading, transport, unload and industry receipt

`BAYLINE_NATIVE_FRESH=1 BAYLINE_NATIVE_RAIL_COAL=1 tests/native.sh` builds
and buys the original steam coal set with native mouse input on unchanged
seed 1751. The loader/receiver models occupy the actual stock wagon's
service tiles. The moving model fills when the real stock wagon holds
coal, persists through process restart, and unloads/cashes its 30-ton load
at the plant. Running costs count only the source running front-engine
ticks, and the paid visit cannot repeat in its parked completion state.

A separate two-process engine fixture `tests/rail_coal_live_native.sh`
keeps the competing real road truck active: 30 t/$232 rail and 40 t/$280
road post together, the one plant gets exactly 70 t, and source rail
running charges settle $120 plus their preserved fractional remainder.

### Actual native passenger bay pair

`lua5.1 tests/road_bay_live.lua` buys three buses at the same depot
and executes stock selected parking rows, exact shared entrance and
individual release, a paused serialized snapshot, and onward fare.
`tests/road_yapf_board.lua` verifies both approach and departure
tables match the actual second-bay pose without snapping. The stock
bay and adjacent drive-through rules have a separate compiled
differential in `tests/road_stop_occupancy_upstream.py`; only the
one-tile pair is mounted in this build.

`BAYLINE_NATIVE_FRESH=1 BAYLINE_NATIVE_ROAD_BAY=1 tests/native.sh` in
Luanti 5.10 was driven with the mouse from the untouched seed. It
built both termini and depot, bought three buses, used the native
full-load order control, observed two original 3D models exactly
0.50 units apart in their assigned bays and the third waiting outside.
The same parked buses and waiting approach survived a SQLite restart;
the third then entered and the first paid for 30 riders. A node-level
observer identified the installed model and actual engine mesh
positions independently of the source pose calculation.

### Directional road-stop route cost

`lua5.1 tests/road_through_live.lua` runs an actual depot bus into a
through stop on the direct leg of a fork. At its stopped stock pose,
it adds eight length units in that direction only. The next route
chooses a detour (1700 empty-direct to 1784 occupied-detour); the
opposite route remains 1700. The route choice persists after copying
the saved state. This does not add multi-tile station construction.
The separate stock dual-bus junction lab demonstrates actual stock
predicates may permit screen-box overlap during a merge before the
proposed headings match. It is not a universal rigid-body collider.

### Paired native Kirby services and repeating coal

`BAYLINE_NATIVE_FRESH=1 BAYLINE_NATIVE_RAIL_PAIR=1 tests/native.sh`:
in a prepared signed test railway, bought and ordered both complete
steam trains with physical GUI input. A real locomotive and wagon of
each were visible; SQLite preserved the first wagon's sole merge
claim and the second train on red. After both resumed, each delivered
40 passengers to a distinct terminal, at $240 and $281, and parked.
Independent economy charges were $83 and $120 in that run.

`BAYLINE_NATIVE_FRESH=1 BAYLINE_NATIVE_RAIL_COAL=1 tests/native.sh`:
from untouched seed, built/loading stages and wagon by mouse, SQLite
restored the physically loaded 10-ton wagon, then the train returned
empty and loaded again. Actual power receipts totaled 60 tons/$468
after two orders, with $152 operating expense. The native depot Park
after next delivery button parked the empty train in place.

### Native forest, sawmill and Goods

`BAYLINE_NATIVE_FRESH=1 BAYLINE_NATIVE_TIMBER=1 tests/native.sh`
opened the untouched starter's visible 18-tile forest and eight-tile
sawmill, built all roads and four true truck stops by mouse, paid
for both actual stock lorries and set the first Full load orders.
The visible Witcombe loaded mesh switched at 10 tons before a
native SQLite restart. On the resumed clock the sawmill received
40 tons ($384 in wood freight), and the actual covered Balogh
delivered 28 crates to the town ($181). Wood and Goods each posted
separate operating costs. `lua5.1 tests/road_timber_live.lua` also
asserts the saved queues remain distinct from the prototype, source
acceptance thresholds, monotonic shared clock, and separate pickup.

### Actual growing town and second steam type

`BAYLINE_NATIVE_FRESH=1 BAYLINE_NATIVE_TOWN_GROWTH=1 tests/native.sh`:
mouse-built, bought and paid service at the two towns, then watched
a physically placed lot start at tick 6588. Actual native foundation,
framing, partial roof and finished named house meshes each displayed.
The framed house restored with new starts disabled, population increased
from 426 to 456 at completion (tick 9481), and only a later tile visit
(10505) produced real source cargo.

`BAYLINE_NATIVE_FRESH=1 BAYLINE_NATIVE_RAIL_OWNED=1 BAYLINE_NATIVE_OWNED_DEFAULT=1 BAYLINE_NATIVE_JUBILEE=1 tests/native.sh`:
built the complete default-seed starter track, depot, source signal and
platforms by mouse; bought the #8 Jubilee and #27 passenger coach for
$22,241, boarded with the dedicated model (not a substitute), saved and
restored the boarding point, and earned fares while reversing at both
ends. The native desktop run posted seven delivered riders at $47 and
$216 expense so far. A separate stock-ceiling replay observed exactly
112 units, collected $192 and debited $238 with a different load/cadence.

### Native South Coast Yate

`BAYLINE_NATIVE_FRESH=1 BAYLINE_NATIVE_SHIP_COAL=1 tests/native.sh`:
on untouched terrain with the explicitly placed South Coast industries,
mouse-built both docks and the actual ship depot. Bought the stock
Goods #211 ship for $32,500 and paid only $507 to refit the same hull
to coal. The original native model loaded at the real water berth;
at 10 tons it saved and reopened on that waterline. It then delivered
all 160 tons and booked $325; the measured running expenses were $549
at that point. A separate headless native two-process test retained a
partial ship load alongside a completely independent passenger ferry
and real competing road truck. The shared power station received the
truck and ship's total exactly once, with no separate production clock.

### Optional 3D junction clearance

`BAYLINE_NATIVE_FRESH=1 BAYLINE_NATIVE_JUNCTION_CLEARANCE=1 tests/native.sh`
uses a prepared ordinary three-arm road. Both real buses were purchased
and ordered by mouse. The second yielded for 28 actual movement attempts
at the first shared junction. The two stock bus meshes were observed
apart, their exact approach state restored, and both went on to their
stops. The measurement and visible safety feature are distinct from
the reproduction of stock 14.1's permissive viewport merge. The
source YAPF choices and normal lane following are unchanged.


### Purchased country aircraft

- `lua5.1 tests/airport_owned.lua`: rejects unauthorized/invalid/missing-art
  purchases, reads both source prices, saves the real hangar and dispatcher,
  and tests fixed-point running money with no repeated charge on restart.
- `python3 tests/airport_roster_upstream.py /path/to/OpenTTD-14.1`: extracts
  both stock model rows and compiles the pinned C++ purchase, economy-day
  and fractional-money functions for 900 independent cases.
- `BAYLINE_NATIVE_FRESH=1 BAYLINE_NATIVE_PAID_AIR=1 BAYLINE_NATIVE_OWNED_AIR=1 tests/native.sh`:
  builds two actual airfields by mouse on fresh terrain, buys the actual
  Coleman Count, orders the physical departure and destination, preserves
  airborne state while switching its original gear model, taxes its
  running ticks, and makes more real passenger deliveries across two
  SQLite restarts. The hangar purchase is debited once.

### Original MPS Regal bus

- `lua5.1 tests/road_regal.lua`: purchase must be from an owned road
  depot; checks 31-seat loading, an unused vehicle's sale at its
  depreciated value, and real paid trips and charges after restore.
- `python3 tests/road_bus_catalog_upstream.py /path/to/OpenTTD-14.1`:
  extracts rows #116–118 and compiles the stock scale,
  depreciation and company fractional-debit functions to compare 1,205
  successive economy days across five price settings.
- `BAYLINE_NATIVE_FRESH=1 BAYLINE_NATIVE_STOCK_REGAL=1 tests/native.sh`:
  mouse-builds the complete starter line and depot, buys the genuine
  31-seat #116 bus, checks its loading, fares and exact costs, then runs
  another paid trip after a real SQLite restart with new Regal
  purchases disabled. The pre-existing active Regal keeps all its
  rules and does not turn into a Town Flyer.
- `BAYLINE_NATIVE_FRESH=1 BAYLINE_NATIVE_JUNCTION_CLEARANCE=1 tests/native.sh`:
  the fixture leaves the clearance setting unspecified. Verifies the
  fresh default, model separation, both actual buses' arrivals and
  that the same saved rule and pre-junction poses survive restart.


### Paid pair on one actual country runway

- `lua5.1 tests/airport_owned_fleet.lua` purchases in the order #1/#2
  and dispatches in reverse, so the port must use genuine vehicle
  creation order. Both routes pay, share the same country terminal
  queue and clock, and continue across a saved state.
- `BAYLINE_NATIVE_FRESH=1 BAYLINE_NATIVE_AIR_FLEET=1 tests/native.sh`
  uses real clicks to buy, build and order the complete layout. The
  native fixture pauses at a genuine stock runway hold, reopens the
  exact two poses/flags from SQLite and observes both paying again.
- The isolated native airport pair geometry oracle also checks the
  real Sampson aircraft near shared taxi paths and the two stands.

- `lua5.1 tests/road_bay_apron_live.lua`: a real three-arm road immediately
  outside a full stock two-bay terminus previously let the waiting bus
  reach into the 3D turn, creating a circular wait. This checks the
  incoming bus now holds outside the whole apron, then enters and earns
  fares after restoring. Use the two-bay/all-workbenches desktop test
  together to validate this combination from a completely fresh map.


### Three original buses on the stock public depot market

- `lua5.1 tests/road_stock_market.lua`: follows an actual seeded public
  offer boundary, original retirement and visible-art prerequisite;
  operates a purchased #118 Foster on a paying road in 1995. The
  selected start, seats, receipts and tick charges survive restore.
- `BAYLINE_NATIVE_FRESH=1 BAYLINE_NATIVE_STOCK_FOSTER=1 tests/native.sh`
  builds the starter road by mouse at a genuine 1995 market, verifies
  the original 37 seats and depot charge, selects both stops in 3D,
  sees the real Foster on its own right lane and at a paid stop, and
  confirms continued stock charges and fares after a native restart.

### Return to a road depot

- `lua5.1 tests/road_depot_return.lua` drives a paying bus to a real
  stock stop, uses YAPF's any-owned-depot endpoint to choose a nearer
  depot than its purchase site, checks OpenTTD's frame 11 door/hide
  transition and resumes the unchanged service after reload.
- `BAYLINE_NATIVE_FRESH=1 BAYLINE_NATIVE_STOCK_REGAL=1 BAYLINE_NATIVE_DEPOT_RETURN=1 tests/native.sh`
  repeats the full operation through native clicks, including building
  the closer depot, scheduling the stop, hiding the real mesh, a
  second SQLite restart, and further paid running.


### Live Farm, Factory and Town Goods

- `lua5.1 tests/farm_workbench_live.lua` mounts the real 74-tick road
  world, builds the actual loops, buys three exact stock trucks, and
  moves all three through the stock pickup/production/payment clock
  before and after a saved copy. No duplicated transport exists.
- `BAYLINE_NATIVE_FRESH=1 BAYLINE_NATIVE_FARM=1 tests/native.sh` checks
  the same native loading across actual built streets and delivered
  Goods, with original fields, 3D structures, payload and van. See
  `FARM_FACTORY_PORT.md` for the industrial source-pin checks.


### One authoritative clock with no viewers

- `lua5.1 tests/campaign_step.lua`: one rate-limited stock-day entry
  point, discarded pause interval, only distinct dirty terrain IDs
  persisted, and a catch-up refresh when a player returns.
- `tests/campaign_offscreen_native.sh`: actual zero-player Linux
  Luanti server runs a paying stock route, reopens its SQLite world,
  earns a new fare with nobody connected, then proves that opting
  out pauses the same saved world. No graphical client or worker
  thread acts on the authoritative campaign.
