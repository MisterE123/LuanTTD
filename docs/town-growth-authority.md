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

## Municipal streets on ordinary generated maps

A town on the normal generated Temperate map can extend its own streets
and reach new buildable parcels during play. The original OpenTTD 16.0-RC1
street walk, layout masks, road suitability, bridge and tunnel scouts
select the work. `IsRoadAllowedHere` first considers the existing
foundation and neighboring roads. Its 1-in-8 unsuitable-slope branch
can make the live-only 1-in-10 downhill attempt, with the original
1-in-16 corner choice. Successful grading is visible immediately; the
road waits for a later attempt. These draws are not added to startup
map generation.

Only an admitted native command writes terrain, municipal road bits,
bridge geometry, or a tunnel. There is no player payment, and the town
cannot clear a private lot, an active industry, protected railway, or
occupied transport facility. The supported spans preserve open river
water below a bridge and surface roads above a bore. Changed cells
invalidate the nearby sea cache rather than restarting it for the map.
The original option that forbids town road construction still applies.

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
rail crossings, excavation through protected parcels, or unrestricted
replacement of player infrastructure.

A native 1024×1024 generated campaign had 832 towns and started the
observation with 24,052 municipal street tiles. Over the next 22
simulation days it reached 24,094 without player construction.
The existing 58 public bridges and one tunnel were preserved.
