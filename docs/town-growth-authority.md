# Typed town house writes, detached

The detached house receipt qualifies one runtime TownTick construction
through the [landscape authority](landscape-authority.md). It is distinct
from ordinary live town growth and does not mount a sparse scheduler.

## Actual read and write paths

| Phase | Owner and activity | Membership consequence |
|---|---|---|
| Start/load | `Sim.mount_stock_town_growth` enables house authority when stock road/loading/corner features are already present. If needed it stamps existing `source_house` records. `town_growth_runtime.start` scans existing maps for roots/counts/population; a saved stock record is reused. | Bootstrapping still needs a known authoritative house register. This is not an O(1) startup migration for a sparse map. |
| Generated towns | `generated_campaign.towns` uses the source `town_worldgen` with the startup RNG. Its local transaction remembers changed cells to undo an unviable town. It may write houses and `Sim.seed_town_road` while `allow_roads=true`. | The pre-play authority is separate from the detached house receipt and from regular municipal upkeep. |
| Day/month preparation | `W.prepare_day` gives unproven road stations their initial 255 ages and clocks, and on the actual month edge rotates service histories. It runs town gates and RNG by sorted TownID using real station load/unload ages, not the legacy site delivered-unit total. | No house membership writes; do not skip it or call it twice. Eligibility and RNG affect subsequent house proposals. |
| Live TownTick | `stock_station_day` runs the physical landscape scan first, then commercial/vehicle/station-service work, then `W.tick` and delayed rating for this growth path. In pinned OpenTTD 14.1, `openttd.cpp` also calls `RunTileLoop`, then `CallVehicleTicks`, then `CallLandscapeTick`, whose first landscape callback is `OnTick_Town` in `landscape.cpp`. | A new house is created only after that tick's complete source slots. It cannot take a new slot in that past tick. Do not claim parity for unported adjacent stock callbacks. |
| Read-side site plan | `B.grow` searches the native town road graph and reads a stock source spec, nearby roads/stops, lot terrain and protection. It draws the **shared RNG** while deciding what to grow. The detached one-house proof disables road changes; ordinary generated towns can make municipal street plans. | A successful plan does not yet write a map cell; but the search cannot be rewound without also rewinding the shared RNG and earlier tick work. |
| House commit | `W` rechecks exact physical flat ground, protected maps, proposed house ID and root position, writes `house/source_house/h`, records town counters, last build, radii and growth rate through `B.house_committed`, and delivers visual dirtiness. The source timer later updates `grow_counter`. | This proof attests **one** physical host `tile` effect. Town count/rate writes do not alter other memberships. `s.topology` does not increment here. A visual append is not the receipt. New stage-0 house becomes a future landscape candidate immediately. |
| Subsequent physical visit | `town_passenger_runtime` invokes `W.advance_house` before ordinary house cargo. A 1×1 root advances counter/stage, not population until stage 3. Even the completing visit suppresses cargo; `H.produce_tile` later draws stock RNG and may serve passengers/mail. | The tile remains active throughout; stage changes and completion require no new membership registration. Source RNG and other callbacks retain their original order. |
| Removal | The existing ordinary `Sim.build(...,"clear",...)` calls `W.remove` before clearing the tile and updates town population/counts/reputation. | Not the construction hook. The separate detached [ordinary command receipt](landscape-command-receipts.md) already requires the real bulldozer's returned dirty cell. |

## Hook and side-effect boundary

The optional fourth parameter to `W.tick(state, tick, rng, write_house)`
installs the detached house writer and disallows municipal road edits
for that proof. This callback
receives the actual validated forecast and a synchronous, single-use
native write function; it neither chooses the lot nor draws RNG. It must
commit and return true, or stop the enclosing operation. It cannot
report a normal failed grow attempt or bypass the write.

```lua
local Receipt = dofile(modpath .. "/openttd/town_growth_receipt.lua")(Authority)
local qualified_writer = Receipt.bind(state, world_name, owner, side_guard)
W.tick(state, completed_landscape_tick, shared_random, qualified_writer)
```

`side_guard(host_id)` is the optional owner veto for unknown providers;
it must be deterministic and read-only. The proof supports clear flat,
unpaved 1×1 substrate for the current native temperate art only.
A protected infrastructure or farm record, unknown tile field, or
unreviewed provider aborts. Preflight uses physical host coordinates
within the exact owning completed tick and separate stock coordinates
for membership. It predicts exactly one `tile` write. Independent
receipt is derived from the actual house stored by the native writer
and validates location, type, town, root, random appearance bits,
stage/counter, and construction tick. It checks the expected shallow
town-ledger writes, house-spec count and total, preserved site/
population, no corner/topology or RNG mutation during the *writer*,
and no unannounced tile fields. No receipt or scheduler pointer is
saved. This trusted bounded writer proof does not detect arbitrary
disjoint writes by a malicious or future different mutator.

The hook runs **after source proposal draws**, even though the physical
tile has not yet been changed; it is not an entirely read-only
town-tick preflight. The authority therefore uses its `slot` disposition
(including the synchronous post-landscape phase of that tick), never
dense replay. A missing/stale/oversized request before a candidate
commit is terminal to the in-flight host operation if these RNG or
other tick side effects have already happened. If a mount cannot
support the required inputs, it must choose the existing dense
owner *before* entering such a tick, not retry after refusing a house.
No partial-tick rollback, dynamic dense fallback, or live mount is
provided here.

## Differential

```sh
lua5.1 tests/town_growth_receipt.lua
lua5.1 tests/town_growth_live.lua
python3 tests/town_growth_upstream.py /path/to/pinned-openttd-14.1 lua5.1
```

The 128×128 fixture places the existing authored 1751 town/road patch
on an actual larger corner/clock lattice, with a carried noncanonical
head. It is not a claim to generate a new 128-map scenario. A real bus
boards paying passenger traffic and source service gates admit Cottage
#25 on host tile **1290** (stock **1289**) **after tick 2148**. The
independent stock walk and sparse observer agree on its first eligible
physical visit **tick 2243, slot 32**; it is still stage 0 and never
produces early. A save-shaped copy and rebind resumes from that
construction counter. The house completes at **5059** and its first
stock cargo arrives from the house at **5571**. The unwrapped dense
`Sim.daily` state matches every persisted field of the test-local
receipt-enabled sparse path each day, including the carried head,
shared RNG, more than one real stage, vehicle/service traffic and town
population. A second run vetoes the exact house after its real planner
draws and proves no membership, map or house-count mutation and no
retry. This is headless Lua host/source QA, not native visual or SQLite
qualification and not full OpenTTD TownTick behavior.

## Permission to build transport stations

Bus and truck stops, tram stops, rail platforms, airports and shore
docks use the same OpenTTD 16.0-RC1 check. A **Permissive** council
skips this rating gate. Otherwise, if a town is strictly inside the
local authority radius, it must rate the building company **above
−200**. A town exactly on the radius does not govern the site. Ties go
to the lower stock town ID. Tracks and depots are not stations, and
airport noise is a separate restriction. The Local Authority panel
shows whether your company's current rating allows new stations.

The search indexes fixed town positions in generated maps and only
looks in nearby buckets. Tests match all 512 full-map reference
queries on a simulated 4096 × 4096 map, including edges and the strict
radius. The quote and final construction both check the current
rating, so a stale approval cannot spend company funds.

## RC1 growth scheduler baseline

The [compiled 16.0-RC1 scheduler comparison](../tests/town_growth_scheduler_rc1.py)
checks the actual radius, active-station, growth eligibility, counter, and
per-town tick functions. It covers 18,628 cases, including 128 consecutive
twelve-window traces with changing service, funding and recorded growth
outcomes. It verifies the RNG draw count and which tick calls for growth,
not which tile OpenTTD will build. A separate [house choice comparison](../tests/town_house_selection_rc1.py)
compiles current RC1 TryBuildTownHouse and the original stock specs. It
matches 12,000 controlled Temperate lots on house ID, origin, appearance
bits and random draws across all built-in road layouts. It checks
eligible but sloped lots, protected plots, equal-height foundations,
year windows, unique buildings, and all stock multi-tile footprints.
It does not compare the world walk or the host's final placement command.
Ordinary towns can now build houses on eligible wooded land through
the stock clear-before-build rule. The committed footprint alone loses
its trees, no company pays or receives a tree-clear rating penalty, and
private trees and developed plots stay protected. Native Lua authority
tests reopen the actual house and verify adjacent trees persist.

Live house construction also accepts unowned coast and rocky coast when
RC1's NoWater clear quote permits it. The municipal clear command
applies only to the committed house footprint. Adjacent river or actual
sea tiles and owned property are not cleared by this path.

Farm fields are ordinary clear land under RC1, not protected industry
buildings. Houses may replace an unowned crop tile. Municipal grading
also includes the stock field clearance price in its spending limit.
The field and its fence disappear only from cleared tiles; the farm
and neighboring fields remain. A native worker builds on a crop field
and reopens the checkpoint with the house and adjacent field intact.

An underground road or railway does not occupy its surface tile.
Ordinary live housing can grow above either bore on clear land;
grading that could alter its roof and construction beneath an
overhead bridge remain blocked. Separate native worker replays
grow a house above each mode, reopen both layers and check routing
through both portals without changing the infrastructure owner.

RC1's house construction counter uses three bits, not two. Each
stage lasts eight visits to the root tile; a newly started house needs
24 visits to finish. Multi-tile pieces advance together. The completion
visit adds population but cannot produce cargo; a later visit does.

Completed houses age on the stock year boundary and cap at 255; unfinished
buildings do not age. The rebuild check uses the saved completion year to
calculate the same age without a map-wide scan. The native generator test
checks that completed founding buildings retain the starting year through
the prepared checkpoint, and the compiled RC1 rebuild tests compare all
256 possible stored ages with several years of elapsed time.

On Better Roads and 3×3 Grid, a successful extra house can count as a
successful growth attempt even if the main roadside lot is already
occupied or cannot be built on. The worker now uses the normal countdown
after that real commit, without building or counting the extra house twice.
A new world can set RC1 growth speed under **Advanced options**:
None, Slow, Normal (the default), Fast or Very fast. This setting is
saved per world and reaches the worker on monthly eligibility, funding,
and house commits. None does not prevent initial towns from being
founded, and Fund New Buildings can temporarily bypass it. The setup
also supports changing this per-world setting during play. The host or
server admin can open **Finance → World rules**, pick a stock rate, and
press **Apply**. The authority worker saves it without rerolling any
growth state at button press: normal town updates pick up the new rate,
and changing to None does not demolish or cancel existing buildings.
The native monthly worker test exercises the actual funding
action with no vehicles, grows houses after a paid command with growth
set to None, then verifies the three monthly decrements and no further
building after two worker reopens. [Whole-town replay tests](stock-town-worldgen.md)
compare placement, RNG and the live map on several stock configurations.
Uncovered occupied-terrain, transport and climate cases still prevent a
claim of complete parity.

## Municipal streets on ordinary generated maps

A town on the normal generated Temperate map can extend its own streets
and reach new buildable parcels during play. The original OpenTTD 16.0-RC1
street walk, layout masks, road suitability, bridge and tunnel scouts
select the work. `IsRoadAllowedHere` first considers the existing
foundation and neighboring roads. Its 1-in-8 unsuitable-slope branch
can make the live-only 1-in-10 downhill attempt, with the original
1-in-16 corner choice. Successful grading is visible immediately; the road waits for a later
attempt. Eligible dry woodland uses RC1's tree-clearing quote as part
of the same corner change; a denied quote leaves the trees and heights
unchanged. These draws are not added to startup
map generation.

Municipal levelling can also leave an existing bridge or tunnel
untouched while changing compatible clear ground on the other layer.
`CmdTerraformLand` compares the proposed top with the absolute
bridge deck before raising, and the default 12-level separation when
lowering. Excavation cannot reach a verified tunnel's height. In two
native 16.0-RC1 captures, the town flattened a clear parcel below a
road bridge and lowered a ridge corner above a real tunnel without
changing either span. Each successful grade cost 250 and consumed
eight stock RNG words; rejected deck and tunnel edits changed nothing.
The Lua checks also exercise rail-bridge, aqueduct and rail-bore
geometry in the same terrain validator. Towns still cannot autoslope a
house: OpenTTD's `AutoslopeEnabled` excludes `OWNER_TOWN`, and its
automatic clear command cannot demolish a house as a fallback.

The same stock town can extend an ordinary street onto clear land below
an existing bridge. `IsRoadAllowedHere` in the Original and Better Roads
layouts rejects running parallel directly below a deck. Perpendicular
lookahead and the normal `GrowTownWithRoad` commit pass the native RC1
comparison without RNG changes. The Luanti worker grows and reopens
the lower street, and the routing graph still traverses the separate
company-owned bridge. A clear surface also admits municipal road above
a verified tunnel in either direction: the bridge-axis rule does not
apply to a bore. The native Luanti scenarios keep both road layers in
place after a worker reopen, with the original span ownership and
its two routed ends unchanged. House placement beneath a deck
remains prohibited.

Only an admitted native command writes terrain, road bits, bridge geometry
or a tunnel. The town cannot clear a private lot, active industry or
protected/occupied facility. As in RC1 CmdBuildRoad, it can add pieces
to eligible ordinary company pavement without transferring its ownership
or debiting the company. Road works, vehicles on the tile, and turning
one-way pavement into a junction still block that edit. The native
worker test checks the junction and the original owner after reopen. The same rule applies to normal roads that share a tile with stock tram
tracks: both companies keep their independent layers, and the stock
shared-foundation rules still apply. A tram on the tile blocks the
edit, but a planned future visit does not. The town cannot use a
tram-only tile as a road in its walk.

Towns can also add a perpendicular road crossing to a compatible plain
railway, without taking its rail ownership, releasing its reservation or
charging a company. A train physically on the tile blocks construction.
The stock setting **Allow towns to build level crossings** defaults to
on; turning it off stops new municipal crossings. The [compiled RC1
railway branch comparison](../tests/town_crossing_rc1.py) checks 15,848
cases, and a native worker test verifies that the two owners survive a
checkpoint and reopen. The ordinary pavement removal tool and layer
confirmation can remove only the public road; the stock local-authority
rating and extra-dynamite rules apply. A native transaction verifies
that the rail remains and only the requesting road company pays.
Incompatible track and protected facilities are not demolished to
force a crossing.

The supported spans preserve open river
water below a bridge and surface roads above a bore. Changed cells
invalidate the nearby sea cache rather than restarting it for the map.
In world setup's **Advanced options**, **Let towns build roads** and
**Let towns build rail crossings** are both on by default, as in RC1.
These are saved on the new world and survive worker or server restart;
changing the server-wide defaults does not rewrite an existing world's
choices. Turning off road building stops new municipal streets, not the
initial starting streets or live housing beside usable roads, stops,
bridges and tunnels. A 256×128 stock comparison with road building off
matches all 27,010 first-year ticks and 14 map/town snapshots, with no
road/span additions by town growth. A real Luanti SQLite restart keeps
the choices even against explicitly different server defaults. A controlled live
test starts at a real bridgehead and builds a house beyond the far
end without changing either the existing road or the bridge.

```sh
lua5.1 tests/town_municipal_roads.lua
python3 tests/town_road_grade_rc1.py /path/to/OpenTTD-16.0-RC1 lua5.1
python3 tests/town_spans_rc1.py /path/to/OpenTTD-16.0-RC1 lua5.1
tests/town_municipal_roads_native.sh "$(command -v luantiserver)" /tmp/native-town-roads
```

The source comparison checks 34,816 slope/RNG cases and 25,920 separate
stock continuation and span cases. The host tests cover actual shared
corner changes, municipal ownership, protected land, and directed
routing through both public portals after a checkpoint. In native
Luanti the worker writes, projects and reopens an extended street, a
river bridge and a road tunnel without any company construction input.
The test uses controlled starting terrain to exercise each obstacle. This does not implement town
excavation through protected parcels, or unrestricted
replacement of player infrastructure.

A native 1024×1024 generated campaign had 832 towns and started the
observation with 24,052 municipal street tiles. Over the next 22
simulation days it reached 24,094 without player construction.
The existing 58 public bridges and one tunnel were preserved.

### Following the town road network

The stock road walk visits the road selected at the town's starting
point before considering the ownership of the next road. A house can
therefore grow next to a neighboring town's road if it is the starting
road, without changing the road's owner or pavement. Crossing onto
such a road from a different tile still ends the search.

The [compiled road-walk differential](../tests/town_road_walk_rc1.py)
matches 3,200 RC1 traces, including visited tiles, headings, stop and
success results, and RNG draw counts. It exercises all four layout
budgets, existing networks with and without town road construction,
and bridge/tunnel exits. The traversal comparison controls the build
result at each visited tile; it is not a full town-growth simulation.
A native worker test confirms that a new house next to the neighboring
town's starting road persists while the road remains unchanged.

The [composed growth comparison](../tests/town_growth_visit_rc1.py)
uses the actual RC1 tile visit and road walk together. It checks 6,000
individual tile visits, then 800 towns across 12 successive growth
attempts apiece on changing boards. It compares the order of land,
house and road calls, success, RNG consumption, house counts and final
tile state. A separate 160-town test in the same harness links the
compiled RC1 growth-rate calculation and TownTickHandler to those same
road and building mutations. It compares eight monthly scheduler
windows with changing station service and funding, then disabled growth.
Eligibility, counters, growth actions, house counts and shared RNG match
in these controlled worlds. Station service and terrain results are
still supplied as inputs; this is not yet an unrestricted month-by-month
whole-game comparison with all transport and landscape actors running.

### Vanilla runtime matches across five months

The [live replay](../tests/town_growth_stock_replay.lua) starts from the
exact January 2 layouts, shared corners, landscape cursor, town and house
state, and two RNG words of real OpenTTD 16.0-RC1 runs. The 64×64 Temperate
references use seed 1751 and original roads. The single-town run uses
the stock six-day GameScript growth interval and follows the adjacent
earthwork tick, natural landscape activity, and housing through June 1.
Two further runs follow a pair of towns through March 1, one with stock
unserviced growth and one with the stock custom interval. The comparison
covers 45 snapshots total, including a multipart stadium, road and
house TownIDs, all road bits and all house stages, construction counters
and ages. These are controlled maps with no industries, companies,
initial forests or subsidies; they do not establish full-world parity.

An additional [four funded-town snapshots](../tests/fixtures/town-growth-rc1-one-funded.lua)
come from a separate stock game. An idle company took a loan and paid
for **Fund New Buildings** on January 1 using the regular town action.
The replay starts with three months remaining on January 2, reopens its
LuanTTD checkpoint on February 1 with two remaining, and matches March 31
and April 1 on both sides of normal expiry. The funding countdown, growth
state, town cargo statistics, every road and house, and both RNG words
match those stock snapshots. The original company never ran vehicles;
this verifies funded town growth and persistence, not company finance or
served-station parity.

Cargo reception uses the stock split between a station's associated town
and the industries it serves. A completed delivery counts toward that
town's monthly growth effect; only units not consumed by an industry
enter its town-only acceptance history. Covered houses can supply
acceptance without changing the town to which the station belongs.
Feeder transfers and replayed receipts do not count. The live bus
simulation, graphical ferry test and shared Goods pipeline verify totals.
The Goods test unlocks the stock growth gate on one month boundary and
fails it again when the next month contains no deliveries.

The monthly town callback now runs after animation and before the tile
loop of the last tick in the 74-tick batch entering the new month.
Funding and roadwork expiry, station service ages and authority ratings
no longer start 73 ticks early. An expiry probe observes the actual
tick callbacks on both sides of the boundary.
The mounted Industry and Station monthly handlers now run before Town
on that same tick. The generated-world test checks ten actual industry
cargo histories in January's final 73 ticks and at February's first tick.
Station acceptance keeps the stock last-month flag separately from
lifetime acceptance and rotates a shared physical goods record once.
New industry placement now runs at the same economy boundary, with
the Day placement before Month quotas and any other monthly work.
A newly opened offshore rig is physically present and runs its first
industry tick immediately. Refreshing the affected transport bindings
preserves running charges and existing presentation samples. Global
industry production order across all supported chains still needs broader
comparison.

### Active transport subsidies

The stock subsidy lottery now runs after the industry's monthly
production history and before towns rotate their own previous-month
history. It uses the same shared random stream as town growth. The
[compiled source comparison](../tests/subsidy_rc1_upstream.py) checks
1,700 cases against OpenTTD 16.0-RC1. The
[mounted live replay](../tests/stock_subsidy_world_replay.lua) matches
both RNG words, every road and house, and the actual passenger and mail
offers through April 1 in two stock three-town worlds. Those references
have no active transport or industries.

An open contract is awarded by the first qualifying **final** delivery
and persists across save/reload. Covered houses determine which towns
qualify, independently of the town in the station name. Industry targets
use actual station coverage; a feeder transfer earns no subsidy, and
multiple qualifying offers do not stack their multipliers. The Gazette's
**Active subsidies** page shows unclaimed and assigned routes, months
remaining, and jumps to the actual endpoints. Default awards pay triple.

Real road passenger and mail settlements verified $62 → $186 and
$67 → $201. A native tanker received $7,008 at twice the normal fare and
$10,512 at triple for the same 220 kL of real offshore oil delivered to the
refinery after reopening a partially loaded save. The award appeared once
in the Gazette and reopening again did not duplicate it. This does not
establish full active-transport or cross-industry town-growth parity.

The [numeric snapshots](../tests/fixtures/town-growth-rc1-1950.lua) can be
regenerated with [the reference extractor](../tools/record_rc1_town_reference.py)
from the corresponding stock saves; no game assets are embedded.

The live town terraform command now uses RC1's two sorted passes over
each touched non-void tile. Each pass draws from the same world RNG; the
first is validation, and only the second can leave rocks after lowering.
A non-rocky live cut or raise starts as bare soil. Rejected quotes use
no draws. This change is scoped to live municipal grading; it is not a
claim of parity for pregame or player-initiated terraforming. Full
growth parity still needs ordinary multi-town, industry, and serviced
scenarios. Enabling stock subsidies in the vanilla control advances
the RNG at February's monthly lottery, which the replay deliberately
disables rather than mimicking with extra draws.


### Town cargo supply

Every ordinary house emission credits its original town with the amount
produced, including houses outside station coverage. Only the whole
units actually added to station waiting cargo count as transported,
including the stock per-station rounding carry. The shared passenger
contest credits the town once across road, rail, ships and aircraft.
Mail uses the same source accounting with its separate station queues.
The Local Authority panel shows the worker's previous-month totals, not
an estimate based on current population or paid arrivals. Both months
persist through an owner restart. The vanilla replay now compares these
raw totals as well; the native ferry fixture verifies nonzero counts at
naturally generated ports through a paid service and reopen.


### Recovering a roadless town

The stock roadless fallback searches from the town center in RC1's
coordinate order. It skips non-flat natural ground even when a manually
built road could use a foundation there. An eligible flat tree tile can
be cleared for the first street. [8,192 comparisons](../tests/town_reseed_rc1.py)
verify choice, road bits and RNG consumption against the compiled
no-existing-street branch. A native worker test clears a flat wooded lot,
leaves the neighboring slope and protected industry intact, and projects
the new public road after reopening the checkpoint. This compares
supported natural land and woods, not every stock clear command class.

## Served rail, ferry, and airport stations

The town's growth check uses the station sign and the same load/unload
timers that drive stock rating. A physically present passenger platform,
dock, or airport now participates in the same RC1 growth check as a bus
or tram stop. An actual load or unload within 20 station age steps can
count; merely passing, arriving empty, or buying a vehicle does not.
Two separate facilities with the same number in different mode books
do not hide one another, and a stale dock receipt cannot count after the
physical facility is removed.

The native fixture earns real road, rail, ferry, and air receipts,
isolates each live station at a monthly town check, and verifies that
each one independently skips the unserviced-town lottery.

The same check reads the mounted, live coal/goods/oil and profiled freight
rail clocks and the coal and oil ship clocks. When multiple controllers
represent one physical station, the youngest valid load and unload ages
are combined and that StationID counts once. A neutral oil rig's dock
and helipad share that same station identity. Released freight designations,
detached oil berths and demolished or foreign facilities cannot qualify
from stale transport records.

Monthly council ratings use this same physical station view. An idle
owned platform, dock or airport is included even before its first
vehicle starts, and an owner-neutral oil rig does not alter a company's
rating. RC1 applies +12 for recent service or -15 for no recent service
at each nearby owned station, then clamps once after the station loop;
the ordinary low-rating recovery runs first. A cleared station without a
physical tile is outside this adapter. This is not the complete
OpenTTD authority, rating UI, or deletion lifecycle.

## Road types and house lots

The RC1 house lot test checks the eight surrounding tiles before choosing
a building. Empty land with no nearby road is allowed. A lot next to only
electric tramway, tram stops or tram depots is not. A nearby ordinary road
or road stop, including one sharing a tramway, makes the lot eligible,
even diagonally. Bridges, tunnels and waypoints do not count as the
road layer for this test. Initial growth, live growth and house
replacement share the same check. The oracle compares all 6,561 ordinary
road/tram/empty arrangements and 1,024 mixed-facility arrangements with
the RC1 function.

### Active RC1 bus comparison

The 64×64 Temperate, 1950 stock comparison starts the same MPS Regal on
ordinary town roads with two drive-through stops. The pinned RC1 GameScript
used the normal build, buy and order commands. Its actual vehicle snapshots
exposed an important mismatch: the live port had applied OpenTTD's old
constant acceleration and per-turn speed loss, not RC1's default realistic
mode. The generated campaign's original buses now take their acceleration
from the stock engine power, vehicle and passenger weight, traction, drag and
incline. Realistic curves and turnarounds use their stock speed limits rather
than the old immediate penalties.

The [compiled force comparison](../tests/road_acceleration_rc1.py) covers
13,356 cases, including acceleration, braking force and cargo weight. The
[ordinary motion replay](../tests/stock_road_acceleration_live.lua) matches
14 snapshots from the official executable on the same board, including actual
position, direction, movement state/frame, speed/subspeed/progress and a
downhill approach. The replay aligns to the exact vehicle tick field; the
stock pause command can land on either side of its most recent controller
tick. The separately tested Luanti client sees the generated-campaign Regal
running depot orders with its native mesh. This verifies physical motion before
the first stop; it does not certify active-station timing, mixed vehicle
clocks, full cargo/economy parity, or identical growth over a served month.


The next [active road economy replay](../tests/stock_road_day_live.lua)
ports the live calendar/economy phase separation from `vehicle.cpp`:
calendar aging precedes the landscape; wear, Reduced loading immunity,
depot checks and running costs occur after the tile loop and before
station load/unload. Each front uses its own road slot's fraction of the
74-tick day. The ordinary bus rate uses the stock Low running-cost base.
The original controller also boards only when it attempts to move from
the stop frame, and carries the blocked movement remainder into the next
leg rather than resetting both fractions at every departure.

The comparison reopens the active campaign before mid-January. The same
source snapshots independently verify both RNG words, reliability, road
station ratings, town passenger and mail production, and integer balances
through tick 2,509. Both February and March match the stock growth
interval and countdown; at the February boundary the stock seven paid
passengers, ratings and ages at both stops also match. This does not imply
full town parity: later RNG and exact cargo and finance totals still differ. It verifies the road pool in this road-only case,
not stock global VehicleID allocation across other modes.


The first active-service divergence was traced to the original engine's
`DoTriggerVehicleRandomisation` in `newgrf_engine.cpp`. Even with a vanilla
bus and no visual resolver, boarding into an empty body performs both
`NewCargo` and `AnyNewCargo`, drawing once per trigger from the shared
simulation stream. The stock bus purchase, full unloading and actual
depot entry also take their original draws. Base vehicles retain their
waiting-trigger bits without reseeding their visual bits. These are real
loading and movement callbacks, not time-based inserts. The
[compiled oracle](../tests/stock_vehicle_random_rc1.py) verifies 4,200
event sequences; the ordinary replay now matches both RNG words at the
February boundary and the town rebuilding countdown at both month
boundaries. Later cargo and RNG are still under comparison.


## Continuous served-town baseline

The new [continuous comparison](../tests/town_growth_rc1_coherent.lua)
uses **one stock RC1 executable run**, not separate paused games. A
normal 64×64 Temperate town has two drive-through stations served by an
MPS Regal. Each numeric observation is taken after a complete tick.
Starting with its actual January state and loan, the normal LuanTTD
runtime matches thirteen full checkpoints through the following January 1: both RNG words,
every recorded town house and road, the common height grid, growth and
rebuild countdowns, town ratings and cargo effects, both station
clocks and ratings, house Passenger and Mail generation/collection,
the company cash and its fractional part, and quarterly expenses,
income and paid passengers. Three packed reopens preserve the result.
The older independently paused samples remain a separate test.

Ordinary monthly company fees now use RC1's Company-priority phase
before Industry, Station and Town. Quarterly history rolls before
the new month's charges. Loan interest uses cumulative annual
rounding, including interest on negative cash, and the default
fixed overhead is 25. The overhead affects the balance but is not
counted as an operating expense. This replaces the ordinary world's
invented balance percentage and full-map per-tile upkeep scan.
[The compiled fee oracle](../tests/company_month_rc1.py) checks
12,012 cases. Source inflation, bankruptcy and optional
infrastructure maintenance are separate systems.

By July 1 the original 10-house town gains the same 11th house on
the same parcel, with identical construction state. Both have
delivered 119 paying passengers. The June maintenance visit also
matches: the fixture restores the stock 150-day interval and actual
engine reliability curve rather than using a fresh engine model.
Service dates, wear and breakdown state agree with the original
alongside the full town and economic checks. This is a road-only
Temperate baseline, not full cross-mode or new-game parity.

By December 1 both games show 231 passenger deliveries. In the November
checkpoint, eight passengers have already unloaded but their fare has not
yet been paid. RC1 credits the town and company delivery counters during
unloading, then records cash when loading ends. The LuanTTD runtime now
does the same, including when the game is reopened before cash settlement.
The second automatic service exposed a smaller ordering bug:
`FindClosestRoadDepot` returns a zero-cost target as soon as the bus is
physically on the depot tile, even while approaching frame 11. The stock
automatic-depot recheck consumes its usual `Chance16(1, 20)` draw here;
the host had skipped that branch until the bus was parked. Reversal
inclination now also follows the underlying straight track, not the
vehicle's turning state. Stock depot entry is the attempted movement
from frame 11, and departure retains the progress and subspeed that
were already earned before the depot hid the vehicle.

The resulting one-year stock run matches all 26,936 logical ticks of
both shared RNG words, bus poses (including both hidden service ticks),
and the two waiting queues including 8-bit fractional carry. Thirteen
full town and accounting checkpoints match, including the same 11th
house, its year-boundary age, and 252 passengers delivered. The test
checks the source observations in segments so a future divergence can
be located within its month. This does not yet certify multiple vehicles,
other modes, other climates or identical new-world generation.

New generated worlds now take the active engine-design draw from the
shared post-forest stream before settling the map. The disabled-disaster
clock still consumes its reset draw as in RC1. This is not a port of
active disasters or evidence of whole-world startup parity. See the
[compiled-source launch values](../tests/world_startup_rc1.lua) and the
[native generation comparison](../tests/campaign_generation_async_probe.lua).


## Shared drive-through stops

A second genuine RC1 run starts January 3 with two Regals serving both
drive-through stops. As in `IndividualRoadVehicleController`, a bus
blocked behind a stationary leader can load at its actual lane position
instead of crossing to the preferred stop frame. The next order begins
at that exact pixel and keeps the same spot in its movement budget.

This interaction changes the town's real service and growth clock.
The town then adds a curved street beside the active stop.
`CleanUpRoadBits` checks the connection facing a through stop, bay
or depot instead of treating the facility as a solid wall. The next
bus drives onto the new municipal tile in both games. The
[ordinary replay](../tests/town_growth_rc1_two_buses.lua) matches all
26,862 logical ticks through the following January 1, including both
buses, passenger queues, shared random words, actual streets and growth
counters, 293 paid deliveries and the finances across three reopens.

Both buses actually service twice. The source allows a non-loading bus
to take up an automatic service order from inside a drive-through lane;
later, it performs the stock active-depot recheck while the bus reverses,
using its logical Trackdir without interrupting the physical turn. At
the preferred stop frame, a moving leader must clear before the follower
starts taking passengers. These situations now run in the same stock
sequence, not as route-specific time adjustments. The verified recheck
is for an existing detour to the same depot; a different depot chosen
during a U-turn is not covered. This is still one active Temperate town,
not proof of multi-town or mixed-mode parity.

### One town with simultaneous bus and train service

A vanilla 16.0-RC1 Temperate town (64 × 64, seed 1751) has a running MPS
Regal bus, two actual road stops, a Kirby Paul Tank with one separately
purchased passenger carriage, and two one-tile railway platforms. The
road and rail services compete for passengers using the same stock
ratings and random stream. The source's subsidy-duration setting is
zero. The numerical test reconstructs the opening and builds its rail
infrastructure and consist through the authority commands. It does not
read a save or change the stock layout.

The [comparison](../tests/town_growth_rc1_mixed_road_rail.lua) follows
both services for 26,788 consecutive ticks, from January 4 through the
following January 1. This includes a train breakdown and recovery and
two automatic train depot services. The YAPF nearest-depot order,
inbound engine and carriage latches, depot track release, service
reliability, per-body Depot random triggers and departure all share the
actual worker motion and reservation code. No load or port checkpoint
teleports the train to the yard. The original passenger orders resume
after each service. The replay opens the packed world four times,
including while the train is heading for the first depot.

Both random words, bus motion, the train and carriage positions and
fixed-point speeds, carried passengers, mechanical train health, and the
waiting, fractions and ratings of all four stops match throughout.
Twelve monthly observations also check town streets, houses and
construction ages, growth timers, passenger/mail supply, and paid
passenger totals. The same observations match the company cash,
fractional penny, loan, and current and previous quarterly income and
expense ledgers. Train running costs use the original VehicleID
economy phase and the stock Low running-cost multiplier, not a
separate once-a-day train-side balance update. The [reference extractor](../tools/record_rc1_mixed_town.py)
records only numbers from the original execution.

Realistic acceleration is the normal RC1 rule for new campaign
services. The [compiled force comparison](../tests/rail_acceleration_rc1.py)
checks 15,120 cases covering cargo mass, rolling resistance, inclines,
tunnel drag, magnetic rail and braking against the original method.
In this town comparison the train's source VehicleID, rail StationIDs,
saved mechanical state, initial engine calendar, and per-body random
state are restored numerically. The same-runtime proof does not yet
establish a general shared vehicle/station pool (including effects,
other modes, buying, selling, and depot operations). The following generated-world check covers
ordinary owned purchases separately. Broader layouts, climates, and
tram, water and aviation competition are not claimed here.

#### Ordinary purchase starts the same train lifecycle

The [generated-world test](../tests/town_growth_rc1_ordinary_train.lua)
builds the route on an untouched generated Temperate board and purchases
a locomotive, a bus, and a passenger carriage separately through the
normal authority commands. Their physical stock VehicleIDs are 0, 1,
and 2 regardless of depot/fleet panel identifiers. Selling the parked bus
and buying another reuses slot 1. No source pose, date, reliability,
random seed, or cargo is inserted into the purchased train. Its condition
decays even while stopped at the depot; the normal passenger service
earns fares, independently selects its automatic service depot, enters it
with both physical bodies, and resumes its existing station order.

The [native Luanti test](../tests/town_growth_rc1_ordinary_train_native.sh)
repeats the purchase, construction and fare loop in the real worker,
checks that both shipped actor models are projected, and restarts the
server while the train is actually headed to the depot. The resumed
train services itself and returns to the original order, with 128
passengers already delivered in the fixture. The first-year stock replay
above remains a separate, stricter differential, not a claim that the
generated map or every active carrier now matches the original.

Fresh BaseStation IDs also cover road stops, tram platforms, rail
platforms, road and railway waypoints, docks, buoys, airports and the
single shared offshore rig. They determine the served-station
acceptance phase and ties in the common house cargo contest. Depot
facility-local labels and saved actor keys do not change. The physical
vehicle pool is live for road and rail; ship/air vehicle allocation,
simulation-only effects, general cross-mode motion order, some
facility expiry paths, and accounts in broader networks remain
separate parity work.

#### Shared stock station phases

The campaign now uses the original ordering from `StateGameLoop`,
`CallVehicleTicks`, and `CallLandscapeTick`: house production first;
one loading pass in the common physical BaseStation ID order; then
vehicle movement, town growth, and trees; then the small station rating
and staggered acceptance ticks. Road and commercial rail, ship and air
station adapters share that loading and rating sequence and the same
simulation RNG. This does not imply that their independent vehicle
movement controllers are fully interleaved yet.

The [simultaneous station-phase test](../tests/town_growth_rc1_station_phase.lua)
forces house production, a five-passenger boarding pulse, and rating
loss onto one tick. It checks that the lower-ID rail platform loads
before the higher-ID road stop and that both ratings happen after the
town callback, with the original shared random draw. The full mixed
year above and native generated-world depot/restart test are also
unchanged by this ordering fix.

#### Road and rail share the stock vehicle sweep

For the road/passenger-rail campaign lane, the controller sweep now uses
physical VehicleID order instead of moving every road vehicle before
every train. Each train executes both RC1 locomotive passes inside its
own slot. In the [generated crossing test](../tests/town_growth_rc1_vehicle_phase.lua),
two running stock buses have slots 0 and 2 around a train in slot 1.
For 4,810 ticks the lower-ID bus moves first, the train executes its
turn, and the higher-ID bus moves afterward. This is exercised with
normal buses and train orders on a generated board, a shared working
level crossing, 300 bus waits at its barrier and actual paid cargo.
The single- and two-bus replays and the full-year bus/rail comparison
remain exact. It does not port every level-crossing arbitration rule:
the existing contiguous crossing-group clearance and the separate
freight, tram, water and aviation combinations still need source work.


### Three years through stock house retirement

The 256×256 Temperate seed 1 mountainous reference now runs for 1,096
calendar days, including leap year 1952. All 81,104 observed RNG word
pairs and 18 map/town checkpoints are compared, with four packed
reopens. On December 31, 1952, at tick 82,360, TownID 44 selects the
still-eligible HouseID 25 at tile 31,072 with appearance byte 167. That
house expires for new construction in 1953, not during the preceding
day's last 73 ticks. The same source tick drives house placement,
replacement eligibility and the age epoch of completed construction.
The new year is visible to tile work only from the source midnight
tick, as in `StateGameLoop` and `TimerGameCalendar`.

The [native worker check](../tests/town_growth_rc1_goods_native.sh)
runs this profile through day 1,095, closes a real SQLite world,
reopens it, and verifies the restored final house, tile cursor, RNG
and all 47 town clocks against RC1. This is a stock growth baseline
for one full map; it does not cover all layouts, climate prerequisites
or active transport permutations.


### Original and linear town cargo generation

RC1's **Town cargo generation** setting is available under world setup
**Advanced options** and, for the host or a server admin, under
**Finance → World rules**. **Linear** is the stock default.
**Quadratic (original)** changes the distribution of passengers and
mail generated by each house, not the growth-speed setting of its town.
The option is saved with the world. It uses `TownGenerateCargoOriginal`
or `TownGenerateCargoBinomial` during both the pregame landscape pass and
live `TileLoop_Town` visits. Applying it during play affects future
visits and does not change cargo history, waiting queues, or RNG at
the time of the setting change.

The [Quadratic comparison](../tests/town_growth_rc1_fast_grid.lua)
matches 25 industry placements, six Fast-growth 3×3 towns, 14 complete
map/town snapshots and all 27,010 RNG ticks through the first year. A
native Luanti SQLite reopen retains the selected mode through the same
year, then applies Linear without advancing the clock or consuming RNG.

### Dense 1993 cities on stock 2×2 grids

A separate 256×256 Temperate seed 9354 has fourteen Very Fast-growth
cities, initial city-size multiplier eight, and 55 industries. It
exercises the large-city zone radii and later building catalog in a
denser street network. The [crowded replay](../tests/town_growth_rc1_fast_grid.lua)
compares 81,104 RNG ticks and 16 snapshots of the ground, road network,
house identity, construction, age and town cargo clocks from 1993 to
1996. It does not extend proof to other climates, multiplayer
competition or NewGRF building callbacks.


### Service survives removal of a stop until its station expires

OpenTTD retains a station's sign in its spatial index after removal of
its last facility. The station cannot accept a delivery, but it still
has a sign, owner and last service times. `CountActiveStations` and the
monthly rating pass use that index. The rating clock stops aging when
the station is unused, and `StationHandleBigTick` destroys the station
on its eighth staggered 250-tick check. On that last tick an earlier
town growth attempt can still see it; the next tick cannot.

The growth view follows that rule for deleted road stops, docks,
rail platforms and airports, without adding them back to orders,
catchment or routing. Removing the last facility captures the sign
and real service ages before clearing its geometry. Pending deletion
also reserves the physical station ID. The compiled RC1 test compares
7,001 mixed-facility cases at the town radius, 20/21 service-age,
expiry, closest same-mode sign (physical ID breaks ties), and the
rating-clock phase carried by a reopened road stop. The native
Luanti worker removes road, rail and air facilities with seeded
rail and air service clocks, then counts all three in February but
none in March. A second native run reopens the road stop at a new
site under its previous ID and verifies the exact tick window when
it next ages. Bulldozing a central platform no longer drops the
station from the town index if other platforms remain.

Ordinary rail placement also reuses an unused nearby rail sign,
unless the player requests a separate station. A native Luanti
quote and build move the original sign and resume its service age.
An already-running pinned OpenTTD source game supplied the rail
build/reopen fixture: physical StationID 5, the sign moving from
(68,63) to (69,63), the resumed rating phase 3, and exact station
and tile random draws. A new or reopened station gets a sign draw;
both new platforms and extensions draw once per tile in the source's
track-major order.

Airports reuse their same-mode sign and small-tick phase too,
unless you hold E during placement to build separately. The
country-airfield oracle matches station 5 moving from (60,36) to
(61,36), the same 25 ground and Built-animation random draws,
and the retained unload age changing from 20 to 21 at the source's
next rating update. Idle airports still consume one stock random
word on their staggered acceptance tick, together with the normal
physical station order. Six native RC1 idle pulses are checked.
Cross-mode joins and full pending cargo restoration remain incomplete.

### Live aircraft through the end of the freight region’s first year

A paid Coleman Count in the running bus, Wood and Goods economy
uses the real airfield construction/buy/order commands. It visits the
local terminal first when the hangar's airport is the first order.
The fuselage and shadow take separate stock VehicleIDs; rotary craft
reserve their additional rotor ID. Calendar aging, reliability, and
running settlement for the owned fuselage run in the common physical
vehicle day sequence. Airport tile visits, whole-unit new cargo, an
emptied cargo queue, and runway touchdown use the original animation
triggers' random words at their source call sites. Those draws affect
the town simulation even without NewGRF artwork.

In the pinned native 128×128 capture, a funded aircraft joins the
ordinary freight economy partway through 1950. The rest of the year
matches 15,693 consecutive world RNG pairs, 15,688 aircraft controller
poses, and seven snapshots of corner heights, housing tiles, town growth counters,
population, passenger and Mail production, and Goods acceptance.
The test checks cargo on board when the cabin empties before the
Mail hold, and saves and reopens during the run. An earlier road
freight rating can discard Wood before a later airport acceptance
trigger; both now use the same physical StationID order.

The paid controller ports high-speed Brake crash sampling,
the two-pass wreck timer, cargo loss and the eventual release
of the runway and aircraft slots. Timed smoke/explosion occupants
use the stock effect-vehicle pool. The default 100-day service
interrupt selects the target airport's hangar and resumes the original
orders after servicing, without loading at a terminal on the way there.
The exact capture exercises servicing, breakdown and a continuing
route. A forced-accident worker test takes a separate branch to check
a wreck and cleanup. The real Luanti worker also completes a
65-passenger and 8-Mail route and credits it once across process
restarts. These tests do not cover all airport layouts or shared
cross-mode stations, other climates, terrain around airport
foundations, or every service/replacement setting.


### A purchased ferry in a generated coastal region

A separate 256×256 Temperate seed 1751 starts in 1985 with 51 towns,
Very Flat terrain, no forced coasts, normal rivers and industries,
and a paid FFP Passenger Ferry added after day four. The build command
takes the original physical VehicleID and applies the stock engine
reliability. A newly built or reopened dock consumes the source
station-sign random word; adding another pier to a live dock does not.

In this run, the original ship controller’s berth stop resets speed,
the next order can reverse the ship by seeding YAPF with both track
directions, and water-tile routing uses RC1’s preferred directional
lanes and lock cost. The ship follows the stock day phase, including the
ship-specific breakdown reliability adjustment and trigger words on
first loading and fully emptied cargo. Running settlement is paid at
that physical economy phase.

The native RC1 replay matches all 27,010 world RNG pairs and 26,714
ship movement/cargo samples, with six exact snapshots of shared
corners, houses, and town counters and supply across three packed
reopens. A separate Luanti worker test checks boarding through a real
process restart. These specific two docks catch passengers but have
insufficient acceptance for a fare, so the test distinguishes activity
and loading from payment. It does not cover shared road/dock stations,
lost-route random navigation, or the full automatic ship servicing and
cargo/refit fleet.

### Wide, varied terrain and neighbouring town roads

The generated 512×256 Temperate seed 10873 starts in 1960 with 42
towns, 92 industries, random town layouts, Fast growth, high river
density and regional terrain variety. The source fixture isolates two
previously missed founding rules:

- On a Better Roads extra-house search, stock `ClearTile_Road` with
  Auto admits exactly one normal road bit if there is no tram. The
  town can replace that end piece with a house, on founding or during
  live play. It still cannot clear an occupied tile, working road,
  crossing, depot, tram or longer piece as part of this command.
- `IsRoadAllowedHere` can look ahead to another town's existing road.
  The road-walk stops when it lands on that foreign road. The lookahead
  doesn't transfer ownership or prospectively block the last approach.

The native map also exposes an otherwise unrelated shoreline mistake:
sea below a bridge remains sea for flooding purposes, so adjoining
coast doesn't dry out merely because there is a deck above the water.
The [wide replay](../tests/town_growth_rc1_fast_grid.lua) compares
27,010 RNG ticks and fourteen map/town snapshots, including two exact
founding tile witnesses and three packed reopens. The native Luanti
worker test also reopens the same map through SQLite and checks all
42 town clocks against the official final state.


### Found a new town during play

This is the ordinary RC1 paid company command, not the scenario
editor or GameScript command. **Town founding** defaults to
**Forbidden** like stock. In a new world use **Advanced options**,
or in a running world as host/admin use **Finance → World rules →
Town founding rules**. **Allowed** uses the world's layout;
**Custom layout** lets companies choose on each foundation.

Aim at a flat, clear site and open **Finance → Found town here**.
Choose a small, medium, or random-size town or city, with a stock
or custom name. Review the site and stock price before committing.
The worker rechecks permissions, land, name uniqueness and cash;
a failed or stale request does not spend money or advance RNG.
The new town joins normal growth, the local authority and airport
census, map labels and newspaper. Initial city-size multipliers
apply only to generation, not to cities founded by companies.

The source fixture builds Rivermark, a medium city with stock
random layout resolved to 2×2, at (68,63) for $26,250,000 in the
default economy. The port matches the initial 804 population
and six complete map/town snapshots across the year, all 27,010
RNG ticks and three packed reopens. The real Luanti worker checks
the debit, news and immediate durability, then restores the same
growth across a process restart. A graphical Linux client also
completed the ordinary quote and confirmation without chat.

A separate source replay founds a fifth town on July 1 with the
original bus, wood and Goods routes already running. The new city
starts with 714 people. Through January 1 the port matches every
RNG tick (13,617) and six map/town/cargo checkpoints after
founding, with three packed reopens across the year.
This case uses Medium construction costs in OpenTTD and compares
simulation, not finances. The default-price debit is verified
separately in the Rivermark case above.

## One station for a bus stop and an airport

In a generated game, select an airport build tool and choose its footprint.
If an owned bus-only station is within the stock join spread, the station
picker offers that station or a separate airport. The original sign and
town stay put when the airport is attached; selecting the airport or
the bus platform still gives a valid destination for that transport mode.
Buoys, waypoints, truck stops, tram-only platforms, standalone rail
stations, and docks are not offered as attachment targets in this slice.
A bus station with a rail platform is eligible; see the three-mode check
below.

- RC1 `station_cmd.cpp` (`FindJoiningBaseStation`, `CmdBuildAirport`,
  `BuildStationPart`) and `station.cpp` (`AddFacility`,
  `CheckStationSpread`, `RecomputeCatchment`) govern ownership, spread,
  geometry, the one physical StationID, and the preserved station sign.
  Building on an active bus station doesn't consume a new sign RNG word.
  Its rectangle bitmap is iterated for acceptance, while cargo producers
  use the actual coverage bits and cannot offer cargo through a hole.
- `economy.cpp` (`LoadUnloadStation`, `LoadUnloadVehicle`) serves bus
  and aircraft from the same passenger queue in arrival order. The
  commercial and road station views share rating state and count as one
  station during town growth. When the bus takes the last passenger,
  the attached airport consumes the same cargo-animation draw as RC1.
- A scheduled aircraft stop measures its learned travel and wait times
  to the source's 37-tick resolution
  (`timetable_cmd.cpp::UpdateVehicleTimetable`). A full-load retry
  samples the two ordinary passenger/Mail links using
  `linkgraph/refresh.cpp::LinkRefresher::RefreshStats`. These are local
  ordinary-order estimates, not a port of automatic CargoDist,
  conditional routes, shared timetables, or refits.
- Two native 16.0-RC1 traces of the 128×128 seed 1751 region include a
  purchased MPS Regal bus, Coleman Count, Wood and Goods trucks, and
  four towns. Each replay matches both random words on all 15,693
  ticks, the aircraft on all 15,688 poses, and seven town, housing
  and terrain snapshots to year end. Shared station ages, waiting
  totals including reservations, ratings, and the ordered physical
  list also match. With **Full Load All**, the native aircraft
  (VehicleID 5) waits ahead of the later-arriving bus (VehicleID 2),
  not behind it in numeric order. Lua uses the same worker commands
  and three earlier checkpoints plus a packed reopen during this route.
- A separate native Luanti worker test builds through the station
  picker query and ordinary quote/commit commands, runs both vehicles,
  restarts the SQLite world, and confirms continued boarding without
  losing the station identity. It is a logic and rendering-frame check
  in the worker, not a graphical mouse playthrough.

The same mechanism now supports bus/rail stations below. Other mode
combinations are still pending.

## One station for a bus stop and a rail platform

Drag or place a rail platform near an owned bus-only station. If the
combined footprint fits the configured station spread, the normal
platform tool offers that bus station in the picker. The bus stop keeps
its sign and both facilities draw from one passenger queue. Orders still
target the proper facility for their mode. Removing the final member of
just one mode preserves the other member's physical StationID and rating
clock, and clamps the shared sign if needed.

The 128×128 stock Temperate reference has active bus, Wood and Goods
service at tick 12602. The original bus sign and station ID (6059 and 1)
remain when the rail platform goes down. A purchased Kirby and Passenger
Wagon run between the joined platform and a separate station with two
explicit non-stop orders. The port matches all 15,689 successive RNG
states; 31,376 locomotive/coach poses (including locomotive speed); 1,304
nonempty, arrival-ordered loading lists; and seven observations of the
region's heights, houses, four towns and cargo through the end of 1950.
The Luanti worker builds through the picker query and normal rail
quote/commit commands. After a real SQLite server restart, the same
physical joined station continues boarding rail passengers.

Two more RC1 captures allow intermediate stops. In the first, the train
stops at a platform that is also its previous manual destination without
inserting a duplicate order. In the second, a third platform is genuinely
unlisted. The native initial suppress flag delays recording it until the
first manual stop; later visits record the third platform in both directions.
The fixture compares real and implicit indices, last visited station, the
order rows, the same passenger and town records, and train motion. The
native Luanti worker retains both learned rows and resumes boarding after
restart. The station departure also exercises the two
`TrainLocoHandler` passes: the second breakdown check sees the order that
the first handler just changed, not the old loading order.

One road-side difference was exposed by the changed cargo results and
vehicle timings. An order to service can be issued in the middle of a
dead-end turn. RC1's `GetVehicleTrackdir` supplies the logical direction
for the nearest-depot search, but `RDE_TURNED` later invokes
`RoadFindPathToDest` from the marker's physical entry direction.
LuanTTD now preserves the remaining turn pixels and uses both original
queries rather than attaching the pre-turn trackdir as the outgoing
lane. The next economy day consumes the genuine service recheck RNG.

This verifies ordinary non-stop passenger rail orders, not trains that
may stop at unordered intermediate platforms, other station mode
combinations, or automatic cargo distribution.


## One station for a bus stop, airport and railway

A bus station can now take both an airport and a rail platform through
the normal station picker, in either order. The stock spread check uses
all existing facility tiles before accepting the build. The original
StationID, sign, passenger and mail catchment, ratings and passenger
queue belong to the shared station. Aircraft use the airport's
hangar and layout, and trains use the actual platform length and
per-wagon loading tile. Those facility coordinates do not become
new station identities.

OpenTTD 16.0-RC1's `CmdBuildAirport`, `CmdBuildRailStation`,
`Station::AddFacility`, `CheckStationSpread`, and
`UpdateStationSignCoord` supply the construction and sign rules.
The station tick processes vehicles in arrival order before the
individual movement passes. On an ordinary 128×128 Temperate map
with a bus, Wood and Goods service, a Yate with Full Load All and a
Kirby with a passenger coach joined physical StationID 1. The replay
matches 15,689 random-state checks, 12,012 nonempty loading lists,
15,688 passenger/mail station records and aircraft movement samples,
plus the locomotive pose, coach planar motion and seven housing/town
snapshots. At tick 13,571 all three modes load at the same station
with the same queue order as OpenTTD. The regular Luanti worker also
keeps one station and resumes service for all three after a process
restart. Removing a stop, airport or rail platform leaves the remaining
facilities on the original StationID and clamps the station sign to
their remaining extent. An empty station still follows the stock
expiration clock. Docks, cross-mode joining without a bus facility,
and specialized freight-rail platform combinations remain outside
the supported construction paths.
