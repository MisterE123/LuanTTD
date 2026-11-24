# Road construction and selective removal

In **Roadworks → Road Options**, use **East–west road** or
**North–south road** to lock the drag to that axis. **AutoRoad** still
chooses the axis by where you point; hold **E** for a connected bend
when using AutoRoad. The bend gesture is native to Luanti, not a stock
OpenTTD command.

**Remove road pavement** is a separate tool, not the Bulldozer. Drag or
click the desired half of a tile. Valid road-removal outlines are amber.
The price covers the pavement actually selected; the swipe skips tiles
it has no right to edit and where vehicles are physically present. If
the company cannot afford the full drag, the worker applies only the
affordable prefix. Select an axis of an empty conventional level
crossing to remove its road and keep the plain railway. A vehicle
actually occupying the crossing blocks the removal; a rail reservation
on its own does not. Bulldoze remains the tool for reviewing and
choosing structural layers.

Town-owned streets have a separate authority check. With Extra
Dynamite off, an inner stretch that connects on more than one side
can't be cut at a connected edge in the middle of the street. A
continuous sweep may still work from an already open end: as each
tile is removed, the next can become an edge. The worker quotes the
actual ordered footprint without changing the town's rating until
the player commits. The enabled defaults and council tolerance come
from OpenTTD, not a feature switch.

## Lay or remove only the tram track

Open **Roadworks → Road Options → Electric Tramways**. Click or drag
with **Lay tramway**. Dragging follows one axis and attaches an outer
half only if compatible tram track is already there. Plain track follows
legal OpenTTD inclines and shares a foundation with any parallel road.
The rails and overhead wires follow the slope; streetcars tilt as they
climb and descend. Tram depots and platforms still need flat ground. **Remove tram
track** leaves shared pavement,
town ownership and one-way signs in place. It skips another company's
track and track occupied by traffic or protected by the active test
streetcar; select a depot or stop with the layered Bulldozer instead.
Clearance uses the stock ELRL salvage price, including a refund on
ordinary flat track. Streetcar dispatch and recall are in **Tram Operations**.

## Choose the entrance of a stop or depot

Select **Bus stop**, **Freight loading stop**, or **Road depot** in the
hotbar, then **right-click** to open its layout chooser. Pick the
entrance direction and left-click the tile to build. At bus and truck
stops, an explicit layout also enables click-and-drag. Bays size along
a single strip; **east–west** and **north–south through** stops size
a rectangle. The whole footprint needs matching platform heights.
Adjacent compatible stops join into one station with shared orders.
Bus and truck facilities can coexist at one station; buses call at
passenger platforms, while mail vans and freight trucks use their
loading platforms. Each cargo keeps its own queue. Hold **E** while releasing to choose **New station**
or join an eligible owned station across a gap. The original spread
limit applies to the combined footprint.
**Auto orientation** is a quick click: an existing straight road sets
a through stop's axis, otherwise an entrance favors a neighboring
connection and checks the slope. It uses the same prices and adjacent
joining as a selected layout. Hold **E** for join choices in Auto too.
Explicitly oriented depots can be placed
before the connecting road; they also try to complete the missing
half of an existing street directly at the selected door. An empty
owned depot can be turned in place, but an active route through it
must finish first.

Explicit stops and depots use the stock slope, price, and foundation
rules for supported sites. Vehicles route to a reachable platform, not
the station sign. A stop's catchment comes from its actual platforms.
In **Roadworks → Stops & Waypoints → Remove road stop**, click or
drag to remove owned platforms without removing their through road.
Orders remain valid while at least one usable platform remains; the
tool won't remove a final platform that is still in vehicle orders.
Stops and waypoints fit below a road bridge, railway bridge or
aqueduct when the lowest deck leaves two levels of clearance. A depot
needs three levels. A low deck leaves the ground road untouched.
The tools protect unrelated facilities and competitor roads. A recently
removed station can keep its name and identity if rebuilt nearby.
The join picker also lists those stations; choose **New station** to
avoid reuse. Using one station across tram or other transport modes
is still separate work.

## Route a vehicle through a waypoint

Open **Roadworks → Stops & Waypoints → Road waypoint**. Click an
existing straight road. Drag across parallel streets to make a wider
waypoint; the worker locks the drag perpendicular to the first road
and checks the whole footprint. Hold **E** while releasing to choose
**New waypoint** or join an eligible waypoint across a gap.

In a bus or truck's **Orders**, add the waypoint from the destination
list or **Pick in world**. The order is labeled **Go via**. Vehicles
pass the signs without loading or stopping and continue to their next
real stop. Use **Remove road waypoint** to take down the signs without
removing pavement. Clear an active approach first and remove the
waypoint's orders before removing its last remaining tile.

A single road waypoint can cover different street directions; each
tile keeps its own axis. Rebuilding nearby can recover a recently
removed waypoint's identity, or choose **New waypoint** for a fresh
marker. The shipped path is for ordinary roads; shared tram stops and
unusual road-ownership cases remain separate.

The regression tests include an off-route waypoint that diverts an
otherwise shorter route, a paid bus service through the marker, and
a native mouse-and-hotbar placement and removal replay. The released
add-on signs retain original editable Blender geometry.

## Scope and evidence

Source: OpenTTD 16.0-RC1 (`07b339c`), `road_gui.cpp` sizing modes and
`road_cmd.cpp` `CmdRemoveLongRoad` and `RemoveRoad`. The tested
slope branch counts pieces rather than charging by tile. Where the
geometry and other way require it, a removal request can mirror the
requested piece or leave a new foundation. The pricing rules are the
ordinary campaign's base costs. Footprint and cost are checked inside
the worker when the drag is released, before spending, instead of
adding a second synchronous preview round trip. A stationary preview
keeps its complete result while the worker rechecks that same gesture;
a different drag never inherits the old quote.

- `tests/road_remove_rc1.py`: 145,920 compiled source geometry cases.
- `tests/road_remove_long.lua`: endpoint normalization, skip order,
  foundation outcomes and affordable prefix.
- `tests/campaign_authority_endpoint.lua`: stale vehicle occupancy,
  confirmed cost and prefix, road/rail split and untouched rail reservation.
- `LUANTTD_NATIVE_BENCH_REMOVE=1 bash tests/road_placement_latency_native.sh`:
  eight 45-tile native worker removals, with persisted results, typically
  reaching a receipt in 45 ms and refreshed host projection in 83 ms
  in the test workspace. This is not a client FPS measurement.
- `LUANTTD_NATIVE_ROAD_GESTURES=1 bash tests/campaign_worker_focus_native.sh`:
  an actual client selects tools and drags. An off-axis aim lays a
  straight road, then the removal tool clears it and the world reopens
  with the same running paid bus and no returned pavement.

- `tests/road_town_permission_rc1.py`: 288,000 compiled comparisons of
  town street permission and rating changes. Native graphical municipal
  sweep with Extra Dynamite off verified three tiles on one town street, a preserved town rating, and a paid route across restart.
  The authority ledger also follows the original passive,
  loading/unloading, and rating-bound rules for station clocks already
  supplied by the ordinary campaign; it does not claim complete council
  actions or that all station classes share one stock index.

- `tests/road_stop_foundations_rc1.py`: 9,728 compiled source checks
  for both stop layouts, slope/facing, height and foundations.
- `LUANTTD_NATIVE_EXPLICIT_FACILITIES=1 LUANTTD_NATIVE_EXPLICIT_FACILITY_UI=1`
  on the graphical focus test: the worker builds a real service with
  explicit through stops and a selected depot direction, then a real
  right-click layout selection and world click builds another depot
  facing East. Both persist on reopen; the operating service paid for
  31 passengers.

- `tests/station_join_picker.lua` checks source picker ordering,
  type and ownership, and joining distance. The graphical focus run
  with `LUANTTD_NATIVE_STOP_JOIN=1` picks a nonadjacent existing station
  and verifies the joined ID after reopening.
- `tests/road_mixed_station.lua` runs a paid bus and mail van through
  different physical parts of the same station IDs and tests removing
  the last compatible platform. The graphical focus run with
  `LUANTTD_NATIVE_STOP_MIX=1` uses the regular truck layout selector,
  verifies the platform meshes and reopens the mixed station.

Remaining: layered tram facilities and bridge/tunnel removal through
this tool, cross-mode road stop joining, and road-type conversion. The current
tool protects game facilities where those rules are not yet mounted.

### Base construction prices

Regular and one-way roads use the OpenTTD 16.0-RC1 base prices from `src/table/pricebase.h`: $95 per newly laid half and $250 when the stock slope rule requires a new foundation. In Temperate, clearing new sites adds $20 for grass, $40 for rough land, $200 for rock, $500 for fields, or $20 per tree. Bare dirt has no clearing fee. This is not the inflation model or unrestricted removal of buildings. Road extensions do not repay clearance, and paving over compatible tram track does not pay for its existing foundation.

Clearing trees with a road or road terminal also applies OpenTTD’s local authority penalty once per wooded tile, not per tree. It is posted only after successful construction and goes to the closest town within 20 tiles (Manhattan distance, exclusive). The per-company penalty is 35 points, floored at −1,000. The ordinary road receipt points out the deduction.

With **Inspect** selected, right-click a town-owned street to view your company’s local authority rating and road-removal requirements. The labels use the stock OpenTTD boundaries. The panel also offers **Fund new buildings** when the company can afford the stock $207,031 base cost. Funding advances town growth for three in-game months. The **Fund road reconstruction** action costs $136,718 at base prices. For six months, eligible flat street tiles near that town can enter stock temporary roadworks. Vehicles can find an open route around the work or wait until it clears. Other council actions are not offered yet.

The reconstruction rules are ported from 16.0-RC1 `TownActionRoadRebuild`, `TileLoop_Road`, `StartRoadWorks`, and `CleanUpRoadBits`. Construction lasts 15 stock landscape visits once started and can finish after a program expires. The visible native work zone uses editable original Blender barriers, cones and gravel. Other climates, rebuilding into custom NewGRF road types, and exact ambient construction sound are outside this slice.

### Tram level crossings

Lay tramway across straight, perpendicular ordinary rail, or lay ordinary rail across existing straight tramway. The tram sees the same physical gate and rail reservation. A crossing can also carry separately priced standard road pavement. Use Remove Road, Remove Tram Track, or choose the surface layer in Bulldozer; removing the final surface layer preserves the railway and any outstanding reservation. Bulldozer can also remove the ordinary railway and leave both surface layers in place; if there is an outstanding rail reservation, release it first. The single dedicated streetcar pilot does not operate on crossings that also carry regular road traffic.

To remove a tram depot or platform, click it with **Bulldozer** and select the facility layer. Removing a drive-through platform keeps its tram track and any ordinary pavement; removing a depot leaves the approach tracks outside its door in place. Stop any tram service using the site first.
