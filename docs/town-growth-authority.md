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
does not yet provide OpenTTD’s in-game change callback for existing
worlds. The native monthly worker test exercises the actual funding
action with no vehicles, grows houses after a paid command with growth
set to None, then verifies the three monthly decrements and no further
building after two worker reopens. Some construction branches still
lack stock behavior, and we
have not yet proven whole-town placement/RNG parity.

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
The stock **Allow towns to build roads** option defaults to on. Turning it
off only blocks new town roads: founding a world still creates initial
streets, and live towns may still find house lots through existing
streets, drive-through stops, bridges and tunnels. A controlled live
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
