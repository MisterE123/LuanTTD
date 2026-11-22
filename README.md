# LuanTTD

Formerly Bayline Transport. Use the existing `bayline` game folder when upgrading;
the name change does not change the game ID, save schema, or mod namespace.

LuanTTD is a standalone Luanti transport-management game inspired by OpenTTD.
It has original world art and Luanti code alongside a growing port of
OpenTTD rules (see [PORTING.md](PORTING.md)). It does not contain or need
the OpenTTD executable, game assets, or Minetest Game. It is not a drop-in port
and does not open OpenTTD scenarios or saves.

## Install and play

1. Install Luanti 5.10 or newer. This release was tested on Linux with 5.10.0.
2. In GitHub choose **Code → Download ZIP** and extract it, or clone the
   repository. Rename the extracted folder to **bayline**, then move it
   into your Luanti user **games** directory. The folder you move must
   contain `game.conf` and `mods/` directly.
   Common locations: Linux `~/.minetest/games/`, Windows
   `%APPDATA%\Luanti\games` (some installs use `%APPDATA%\Minetest\games` or
   a `games` folder beside the unpacked engine). Use Luanti's **Open User Data
   Directory** button to find the correct installation.
3. Open Luanti, select **LuanTTD**, and create a fresh world. In the generator
   setup choose **Save and return**, then **Play** that same world again.
   No additional mods are needed. The default temperate map is made by the ported
   OpenTTD 14.1 TerraGenesis generator. You start in 3D above a generated
   town. Existing saves keep their original terrain.
4. Open **Roadworks (2)** from the main hotbar. Choose Road to join streets,
   or open **Bus Stops** to put a stop on a suitable town street. Place a
   depot beside a road, inspect it to buy a bus, then order the bus to two
   stops and start service. Stops start empty until first visited.
   See the [generated map guide](docs/generated-campaign.md) for a tested
   first coal route and larger maps.
5. The old Harbor Valley starter map is no longer a new-world option.
   Existing worlds still open as saved. Explicit Farm, Oil, South Coast,
   Coastal Landscaping, and development scenarios retain their own maps.

New to rail? See the [first train recipe and transport playtest notes](docs/native-qa-2026-11-22.md#first-train-recipe).

### Controls

| Input | Action |
|---|---|
| WASD, mouse | Fly horizontally and look |
| Space / Shift | Raise or lower the camera |
| Main hotbar 1–7 | Survey, Roadworks, Fleet, Company, Navigation, Controls, Landscaping |
| Main hotbar 8 / 0 | Rail Construction / Sea & Air, when mounted |
| Roadworks 1–5 | Inspect, AutoRoad, Bus Stops, Depot, Road Freight |
| Construction 9 | Bulldoze from any construction menu |
| Road and rail menus 0 / 6 | Bridge / Tunnel |
| 8 in any section | Back to the previous hotbar |
| Left click | Use the selected hotbar tool in the world |
| Right click | Cancel an active build, finish picking orders, or open context |
| I | Open the secondary control desk |
| Escape | Close the open window |

Fresh road-first campaigns expose the compatible native workbenches.
**Rail Construction (8)** opens the railway directly. Use **Sea & Air
(0)** for Harbors (2) and Airfields (3); use **Roadworks (2) → Road
Freight (5)** for loading stops. **Navigation (5) → Jump Map (5)** is only
for moving around. The label above the hotbar shows the current menu, the
selected key and tool, and how to use it. Existing worlds and explicit
Luanti settings can differ. Use **Controls (6) → Workbenches &
Scenarios (2)**, or `/workbenches`, to see which tools are active and which
profiles need a separate world. See [hotbar layout](docs/hotbar-layout.md)
and [Workbench index](docs/workbench-index.md). Do not turn on the legacy
developer sandbox for these native workbenches.

### Towns that actually grow

Set `bayline_stock_town_growth = true` before creating a road-first
world. Towns use stock station-service timing and build supported
one-tile buildings on clear, flat open lots along existing roads.
Look for foundations, framing and roofing on the actual map. Inspect
the building to see progress. Population increases on completion;
passenger and mail supply starts on later stock house visits. Disabling
new growth leaves any construction already underway to finish.
This preview does not build new municipal roads or multi-tile houses.

### One-way roads

Enable `bayline_road_oneway_preview = true` on a stock-road world. Open
**Roadworks → Road Options (7)**, choose **Paint a one-way route (2)**,
then click along one straight axis in the intended direction of travel.
The quote identifies edited tiles; completed roads display painted
arrows and physical roadside signs, including on supported roads with a
grade. Repeating the same drag cancels that restriction. Dragging in the
opposite direction adds a second restriction and closes the road to both
directions, as in OpenTTD. A bus facing a new sign detours if its exact
current pose can lead into a valid alternative. Otherwise it waits
without entering and can continue once the invalid approach is reopened.
Existing signs remain enforced even if further construction is disabled.

Fresh worlds use physical clearance at ordinary three- and four-way
road junctions. Approaching vehicles wait outside a connected junction
until the other vehicle's projected rear clears. Stock viewport rules
allow overlap in some merging poses before the headings match. Use
`bayline_road_3d_junction_clearance = false` if you want to reproduce
those exact poses, or set it to `true` to enable clearance in an older
world. This does not change YAPF or ordinary lane rules, and it is not
a universal collision system.

To buy the stock MPS Regal bus instead of the early Town Flyer, set
`bayline_stock_regal_preview = true`. Build a road depot, inspect it
and buy the 31-seat Regal for $6,562. It uses the original stock loading,
road motion, running charges and eight-day depreciation. Old buses
retain their existing capacities and costs.

For the three original stock buses with a real depot market, create a
fresh world with `bayline_stock_bus_catalog = true`. The default year
is 1950; add `bayline_stock_bus_start_year = 1995` before creating the
world to try the original **Foster Bus** immediately. At a road depot,
buy whichever of the 31-seat MPS Regal, 35-seat Hereford Leopard and
37-seat Foster is available. Stock introduction and retirement dates
are calculated from the campaign seeds and its Gregorian calendar.
The Foster has its own Blender-made model and costs $8,203. This
mounts the public market, not prototypes, mail variants, vehicle
breakdowns, or automatic replacement. Settings do not change an
existing world's start date. See [stock engine calendar](STOCK_ENGINE_CALENDAR.md).

With stock road loading enabled, stop a bus at an accepting stop to
finish unloading. Once empty and stopped, open its Fleet card and
choose **Park in depot**. It drives to its nearest reachable owned depot,
travels through the door, and is hidden inside. Its original stop list
stays intact. Reopen it from the depot and **Start service** resumes the
next saved order. This action is not an in-motion reroute.


### Optional Trackworks sandbox

The default game remains the playable bus scenario. To examine the new
3D track pieces, add `bayline_trackworks_preview = true` to your Luanti
configuration and open a disposable world. Run `/trackworks X Z x` to place
east–west track; the other pieces are `y`, `upper`, `lower`, `left`, and
`right`. Add a second piece on the same tile to form a switch or crossing.
Append `remove` to remove one piece; omit the piece to inspect that tile.
The sandbox supports flat track and common straight grades. It uses the
ported track follower to check connectivity and YAPF to survey routes,
but it does not schedule train service, allocate signals, or charge costs. The legacy
train prototype is not the new rail port. Run `/trackroute X1 Z1 X2 Z2`
to survey a path from a built piece to a flat straight segment treated as
a temporary one-tile test platform. It does not create or run a station.
Use `/trackrun X1 Z1 X2 Z2` to watch one temporary locomotive follow the
same route. To build real facilities instead, use
`/trackfacility X Z platform X2 Z2` on one to seven owned straight tiles
or `/trackfacility X Z depot east` at a clear end (also north, south, west).
Use `/trackrun clear`, then `/railtrial DEPOT_X DEPOT_Z PLATFORM_X PLATFORM_Z`.
The single-locomotive pilot waits in the depot, follows real stock orders
to the new platform, stops at the stock position, and survives a restart.
It does not carry cargo or use signals. Multiple trains are available
only in the separate dispatch pilot below.
Use `/railtrial clear` and `/trackfacility X Z remove` to clear the pilot
or remove a facility, respectively.

### Build and order trains with the 3D Railworks hotbar

Open **Rail Construction (8)** from Home. **AutoRail (2)** is the direct track tool. Click for one piece, or hold, aim and release for a run.
**Rail Tools & Operations (7) → Rail Engineering (1) → Manual track pieces (7)** contains both
straights, the four individual curves, and a removal toggle. Two ground clicks outline a station platform
with **Platform (3)**. The depot's door faces the compass direction shown on
the HUD. **Rail signals (5)** offers ordinary/one-way path signals and
removal, and conventional signals on workbenches that mount them. In
**Rail Operations (7)**, select an owned depot
and a destination platform, or a pair of distinct platforms for a shuttle.
You do not need chat coordinates. Quotes and charges come from stock
ordinary construction, including the existing plain-track refund under
a station. NewGRF tracks and general complex joins are outside this
preview. Ordinary flat road/rail crossings use the separate crossing
workbench.

### Buy and run a real steam consist

Set `bayline_rail_owned_preview = true` in a new temperate world. Build
owned track, a depot and two passenger platforms in populated catchments.
Use **Inspect (1)** or right-click the depot, then buy the **Kirby Paul Tank +
passenger carriage** for $12,866. Choose its platform orders, then
pick the two platforms in order. Select and click **Dispatch** to run
the train; right-click cancels before dispatch.
The first track route to the platform must connect from the depot; the train
then reverses and shuttles between the two platforms. Inspect the depot
again to pause or resume that particular purchased train.

The same depot also offers the original **Chaney 'Jubilee' + carriage**
for $22,241. It has its own model, the stock 112 km/h speed limit and
running costs, and works with the same two-platform passenger order
tool. The larger engine is not substituted for the Kirby in paired
passenger or rail coal service.

The streamlined **Ginzu 'A4' + carriage** costs $31,616 while the
stock engine is on sale. Its independent Blender-authored locomotive
and tender use the source 128 km/h limit, 1,200 hp and original
running cost. The same two-platform order tool runs it; a native
seed-1751 playtest bought it, boarded passengers, restored the loaded
consist and paid fares. The paired passenger workbench can place it beside a
separate Kirby consist. Coal work still uses its own Kirby consist.

In a later temperate start, the **Floss '47' + carriage** gives an
ordinary 160 km/h, 2,580 hp diesel option at the stock $30,054 price.
For example, enable `bayline_stock_bus_catalog = true` and set
`bayline_stock_bus_start_year = 1966` before creating the world.
The historical date applies to the whole campaign, including the
rail market; this isn't a separate unlock for just one engine. The
Floss has a separate original Blender model and a single logical
locomotive, not two engines hiding in the same entry.

On fresh seed 1751, clear trees on (2,5), (3,5), and (4,5) with
Roadworks → Bulldozer. First place the east-facing depot at (2,5).
Connect east–west rail from (3,5) through (23,5), then build platforms
(5,5)–(6,5) and (21,5)–(23,5), and a west-facing path signal
at (4,5). Choose the east platform first.

Stock capacity,
speed, cargo weight, purchase and passenger settlement are active.
This is one paid passenger consist; other consists and financial
maintenance, including actual running-expense debits, remain preview
limitations. Coal wagons are not exposed in this UI.

### Timber railway bridges and tunnels

With the Railworks preview enabled, also set `bayline_rail_span_preview = true`.
In **Railworks**, **Bridge (0)** takes two opposite
abutments on one straight axis, then opens the type list. **Tunnel (6)** takes an uphill portal
and finds the aligned far opening. Supply matching ordinary track at each
outside edge. The bridge deck uses the stock one-level ramp and wooden
speed limit; the tunnel does not draw trains through the surface. For this
exclusive one-way pilot choose **Rail Operations (7) → Run train through
rail spans (4)** and click an owned depot and its final platform.
Do not use the two-platform paid shuttle for the spans. To edit a built
span, clear the pilot first. This preview protects the immediate bridge
and tunnel layers from other construction tools. See
[rail span details](RAIL_SPAN_PREVIEW.md) for supported geometry.

### Controlled road–rail crossings

Enable **Build and order trains** and `bayline_rail_crossing_preview = true`.
Lay ordinary road across compatible rail, or AutoRail across a compatible road.
Both types must be perpendicular and the tile flat. The explicit tool remains
under **Rail Tools & Operations (7) → Rail Engineering (1) → Level crossing (4)**. A train can use the crossing on a
normal depot-to-platform order. A road vehicle that already entered can
finish; approaching road vehicles wait outside. The striped barriers stay
down until the last wagon clears. This safety policy is more conservative
than OpenTTD's stock collision branch. The preview does not put crossings
on slopes, junctions, signals, depots, bridges or one-way road, and has
no crossing demolition tool yet. Disabling new construction never
removes protection from an existing crossing.

### Coupled railway dispatch pilot

In a fresh world set `bayline_rail_dispatch_preview = true` to enable
Trackworks plus a separate two-consist pilot. Lay owned ordinary flat
track, install two different depots and two destination platforms, and
place path signals on plain straight pieces using
`/pathsignal X Z east|west|north|south [oneway]`. Signals face the
direction of travel you supply. Use
`/raildispatch DEPOT_X DEPOT_Z PLATFORM_X PLATFORM_Z` for each train.
Each has an MJS 250 and one empty passenger carriage. The rear carriage
keeps its track reservation until it actually leaves the crossing; a
competing train waits at its signal. Both survive a restart.

Each train follows a unique one-way route and stops at its own platform.
The two-train pilot does not provide passenger service, return orders,
conventional signals or dynamic branching. Set `bayline_rail_grade_preview = true`
alongside the dispatch flag to drive on authored shared-corner straight
grades, using stock height and uphill/downhill speed. Use
`/raildispatch clear` before
editing track; signal placement and ownership persist. The single
locomotive trial and survey cannot run at the same time as this pilot.
For a separate single coupled shuttle use
`/railshuttle DEPOT_X DEPOT_Z FIRST_X FIRST_Z SECOND_X SECOND_Z`.
The first and second platforms must both be reachable in the supported
forward/reverse directions, with safe waiting at both ends. The train
alternates the stations after a short pilot dwell, including after a
restart during turnaround. By default this is an empty trial.
Set `bayline_preview_paid_rail = true` and keep stock house production
enabled for timed loading, unload-before-pickup and passenger fares in
the shuttle. Existing empty pilots must be cleared and relaunched.
Build platforms close to occupied neighborhoods that accept passengers.
Rail can share the same town supply with buses and a paying ferry; the
same house does not emit passengers twice. See `/raildispatch status`
for current coach load and fares. This remains one paid shuttle and does
not unlock a full commercial rolling-stock fleet or automatic transfers.


### Landscaping, road bridges and tunnels

Open **Landscaping (7)** for Raise corner, Lower corner and Level area.
The highlighted tile's north corner is the selected point; the first
corner of a Level drag sets the grade. For typed coordinates or diagonal
selections, use `/landscape raise X Z`, `/landscape lower X Z` or
`/landscape level X Z END_X END_Z [diagonal]`. Area operations can be
partial as in stock OpenTTD; work costs money and protected roads, buildings,
trees, and water aren't cleared by this adapter.
With road bridges enabled, open **Roadworks (2)**. **Bridge (0)**
previews two endpoints, then opens the type and price list. **Tunnel (6)**
previews its exit from the incline and builds from a single entry click.
The previous **Navigation (5) → Road Bridges & Tunnels (7)** shortcut also remains.
Typed alternatives are `/woodbridge X Z END_X END_Z` for timber,
`/concretebridge X Z END_X END_Z` for a short concrete bridge (two interior
tiles at most), or `/girderbridge X Z END_X END_Z` for the steel girder. Prices,
length limits, ramp heights and speed limits follow the stock catalogue. Connect each outside approach using the ordinary
Road tool. Buses follow the deck with stock speed limits; roads underneath
stay on the ground. Remove the entire structure with `/woodbridge X Z remove`
at either end when active routes have cleared it. The same setting enables
`/roadtunnel X Z` on an uphill portal tile. The exit is found by the stock
same-level scan. This preview requires an already complementary exit
slope and does not excavate land or permit layered bores.

The Coastal Leopard becomes available in road depots in 1964. Its bus
capacity and max speed come from the stock vehicle table, with original
Blender art.
With `bayline_mail_preview = true`, build a road and use `/truckstop X Z`
to place each mail loading stop, then buy the Harbor Post Van at a road
depot. Both stops should display **Accepts mail** if you want deliveries
in both directions. In the default 1751 world, the sites (11,12) and
(17,12) accept mail when connected by a road. The existing bus stops are
not mail stops. Route, production, acceptance, aging, and payment use
the stock mail rules; handling and loading are still grouped by day.

### Electric Tramways pilot

Open **Roadworks → Road Options (7) → Tramways (4)**. Place a depot
with its door facing the connected track. Lay two-ended sections, use
half-pieces to connect to the depot and to make turnaround stubs, and add
two straight through stops. **Rotate (6)** changes the direction or axis.
Choose **Order test streetcar (0)**, then click the depot and both stops
in order. The streetcar alternates stops, reports its visits in the
Tramways hotbar and resumes after restart. **Clear test streetcar (7)**
keeps your track and stations. The test vehicle uses original stock
electric tram routing and motion; it does not earn fares.

This pilot needs flat, **tram-only running**. The tram layer preserves existing
road bits and can be built over a flat road, but the pilot will not share a
route with buses yet. It does not carry passengers, run more than one tram,
apply timetables, or support track construction under spans or on grades.

### Stock road loading preview

Set `bayline_preview_stock_road_loading = true` in a fresh world to run
stock loading, reservation, payment and cargo aging on the same tick
clock as road movement. A bus or postal van unloads before loading, and
pickup happens in successive stock batches. Boarded people disappear
only when actually picked up; an occupied bay stays blocked until the
vehicle departs. This preview supports one modeled bay and manual cargo
orders; it does not have articulated road vehicles, multi-bay scheduling,
automatic refit or a cargo link graph.

### Working coal mine, power station, and road freight

Set `bayline_preview_coal_industry = true` and open a fresh seed 1751
world. The mine and power station appear naturally, with original Blender
assets, moving winding gear, and a running power-station stack after deliveries.
Open **Roadworks (2) → Road Freight (5)**. Build a road between (31,14) and
(41,14), a road depot at (32,15), and a freight stop at each end of the road.
You can fly there or use `/survey 35 14` to orient yourself. Use **Inspect**
on the depot to buy a 20-ton coal tipper, add the mine-side stop first and the
power-station stop second, and choose **Start service**. A first mine visit
opens its catchment for regular deliveries; an initially empty stop is normal.
Inspect the mine, power station or stops for production, receipt and ratings.
This is the ordinary stock coal chain, not a fully general industry or cargo port.

### Rail coal loading and receiving

Enable both `bayline_rail_owned_preview = true` and
`bayline_rail_coal_preview = true` in a fresh default seed 1751 world.
The original mine and power station supply and consume the coal. Build
rail platforms, then select **Railworks → Rail Operations (7) →
Rail Freight (5)**. Use **Loading (2)** on an owned platform serving
the mine and **Unloading (3)** on one that can deliver to the plant.
Click the tile that should hold the equipment; slot 6 switches sides.
The stage is separate from untouched passenger platforms.

For the default seed, make the west-facing depot at (44,15) first.
Connect east–west rail between (30,15) and (43,15), platforms
(30,15)–(32,15) and (39,15)–(41,15), and a regular east-facing
path signal at (42,15). Put the north-side loader at (30,15) and
the receiver at (41,15). Inspect the depot to buy a $12,312 Kirby
Paul Tank with a 30-ton coal wagon. Choose its mine and power-station
orders in that sequence. The train waits for full coal, unloads without
loading at the power station, then repeats. Income settles only against
actual power-station receipt. Click its depot to stop or resume the
train, or to park it after the next completed power-station delivery.
Parking retains its position and affected track claims. This preview
operates one freight train at a time. If road freight is enabled too,
both modes compete for one simulated mine output. Older coal orders
from the one-trip preview still park after their delivery.

### Two-bay bus terminals

From the normal hotbar select **Roadworks (2) → Bus Stops (3) →
Two-bay bus terminus (3)**,
then click the flat end of a road. A terminus is a dead end with one
shared entrance. A roadside stop (slot 2) still goes on a straight road.
Inspect the terminus to see which bays and whether the entrance are in use.

For a repeatable starter on seed 1751, draw a road from (11,12) to
(17,12), build a terminus at each end and a depot at (12,13).
Buy buses from the depot, then use **Go to…** to click the two stops.
Before starting each bus, select the first order and use **Selected
order: toggle full load**. The first two buses can park in distinct
bays, and a third waits on the approach until the entrance and a bay
clear. Fare service and the physical queue save. Disabling the
construction option (`bayline_road_bay_preview = false`) does not
erase existing buildings or their queues.
The two-bay runtime currently supports Town Flyer and Coastal Leopard,
not the legacy Coach, articulated road vehicles, or multi-tile stops.

### Two purchased steam trains on a shared railway

Enable `bayline_rail_owned_preview = true` and
`bayline_rail_pair_preview = true`. Keep paid rail enabled. Buy one
Kirby and coach in each of two different depots. Use **Railworks →
Rail Operations (7) → Order two owned passenger trains (6)**. For each
train, click its depot, boarding platform and final platform. The
boarding platform may be shared. The final platforms must be distinct,
on separate ends away from the other train's route. Give both trains
same-direction shared track with working path signals.

The second train waits for the first train's last wagon to clear the
merge. Both have independent paid cargo and running-cost ledgers. They
unload and park at their destinations; this pair does not repeat or turn
around. Building a completely free-form rail timetable or mixing
paired passenger service with rail coal is outside this preview.

### Forest, sawmill and town Goods

Set `bayline_road_timber_preview = true` before creating a fresh
default seed 1751 world. An actual forest at (12,1) and sawmill at
(12,16) are placed on stock footprints. Use **Road Freight** for
road, truck stops and depot. Build the two road strings in
[TIMBER_WORLD.md](TIMBER_WORLD.md), plus the short Goods spur (12,14)
to (12,15). Use truck stops at **(16,2), (15,17), (12,15), (14,8)**
and the depot **(11,12)**.

Buy the **Witcombe Wood Truck** and order the forest (16,2) then the
wood inlet (15,17). Put the **Balogh Goods Truck** on the distinct
Goods pickup (12,15) then the town stop (14,8). Give each a full-load
first order if you want complete loads. Use separate mill stops: a
goods truck waiting for a full load in the wood receiver's only bay
would block the incoming material. The sawmill converts actual wood
receipts, then offers real Goods on a later terrain tick. Its output
is not spawned directly in the second truck. The first truck shows
actual bundled logs at 10 tons, and the covered Goods truck does not
change its appearance at loading. Industries remain open in this
scenario; dynamic industry founding/closure is not mounted.

### Harbor construction and passenger ferry pilot

Set `bayline_ship_preview = true`. Open **Sea & Air (0) → Harbors (2)**.
A dock needs a dry, one-level shoreline ramp pointing
toward two consecutive level water tiles. Choose one end of a depot and
rotate its full two-tile footprint before building. Open **Ferry Operations (7)**,
choose **Order ferry (2)**, and click your depot then two different docks.
For an example on the default seed, the same operations are available as commands:
```
/shipyard dock 5 32
/shipyard dock 8 32
/shipyard depot 11 35 x
/ferrypilot 11 35 5 32 8 32
/survey 7 33
```
The original ferry leaves the depot, navigates with stock ship YAPF, moors
on navigable water beside each pier, and resumes after restarting. This runs empty by default.
To carry and earn fares for actual passengers, also set
`bayline_preview_paid_ferry = true` with stock house production enabled.
Place docks within populated neighborhoods that accept passengers; the
bare coastal route above is primarily a navigation example. Use
`/ferrypilot status` to see berth queues, onboard passengers, delivered
units and fares. Clear and relaunch an existing empty pilot to switch.
The paid pilot remains one ship, with no fleet procurement or subsidies.
Use `/ferrypilot clear` before removing a facility. Harbor construction
and removal both preview and change the whole two-tile structure at once.
Open **Waterworks (4)** within Harbor construction. **Dig canal (2)** takes
two flat area corners; **Lock (3)** takes the one-level incline between flat
tiles; **Aqueduct (4)** takes two opposed natural slopes of equal height.
The same tools are available as `/shipyard canal X Z END_X END_Z`,
`/shipyard lock X Z`, and `/shipyard aqueduct X Z END_X END_Z`.
Aqueducts need water approaches at their deck elevation. For ordinary
changes of level use a lock: its chamber and ferry rise together and
the two gate meshes remain closed while the level changes. A saved ferry
can continue from mid-lift. Fresh lock ends become canals, which remain
water after the whole lock is removed.


### Buy and refit a real coal ship

For the supported South Coast route, set both
`bayline_ship_coal_preview = true` and
`bayline_scenario = south_coast` before creating a fresh
seed 1751 world. This chooses the alternate real coal sites on the
same untouched terrain instead of the inland rail-coal sites. Use a
separate new world for the inland route.

Build coal mine and power station docks at **(8,32)** and **(5,32)**,
and the east–west ship depot at **(12,34)**. Inspect the depot, buy
the **Yate Cargo Ship** for $32,500, then choose **Refit hold for
coal** for $507. In **Vessel Operations (7)**, select **Order Yate
coal ship (3)** and click the mine dock followed by the power dock.
The Yate loads 160 tons and repeats its route on the shared industry
clock. The covered hatches look the same loaded and empty, as in
stock. Inspect the depot to stop or resume it; stopping does not remove
the ship or release the route's protected facilities.

One cargo ship is supported, alongside a ferry on distinct docks and a
different depot. This preview does not yet sell or automatically return
the Yate to its depot. A short test route can cost more than it earns.

### Country airfield and trimotor pilot

Set `bayline_airport_preview = true`. Open **Sea & Air (0) → Airfields (3)**. Place the
northwest corner of the actual 4×3 airfield; all twelve tiles must be
clear and level. It costs $7,200. On a fresh default 1751 world, fields
at (7,16) and (30,16) fit. Select **Order trimotor (3)** in the Airfields
hotbar and click your departure and destination airfields. Slot **7**
clears the flight. Command equivalents are `/flightpilot 7 16 30 16`
and `/airfield X Z`. The original Trimotor
leaves its hangar, reserves the stock runway, takes off, approaches,
lands, taxis to a stand and returns. Saved airborne controller state is
restored after restart. The base preview runs one empty plane. To carry
passengers and earn fares, also enable `bayline_preview_paid_air = true`.
Use a separate fresh seed 1751 world and place the two fields at (7,12)
and (20,12) for actual town catchments; the empty-route sites above do
not receive passengers. Inspect either airfield for waiting passengers,
capacity and fares.

For the purchased-aircraft workbench, set `bayline_air_owned_preview = true`
instead. On the same (7,12)/(20,12) sites in a fresh 1751 world, Inspect
the first airfield's hangar and buy **Sampson U52** ($38,281, 25 seats) or
**Coleman Count** ($41,015, 65 seats). Use **Order aircraft (3)**, click
the purchase airfield and then the other field. The original country
controller handles the runway and stand; the Coleman raises its gear
in flight. Inspect either field to see fares and running costs. The
purchased slice is one passenger aircraft with no mail, sale, automatic
service, crashes, helicopters, or multi-plane construction workbench.
Small test routes may cost more than they earn.

To try two purchased aircraft sharing a runway, use a **different**
fresh world with `bayline_air_fleet_preview = true`. On seed 1751 place
country fields at (7,12), (20,12) and (30,11). Buy one **Sampson U52**
at each outer hangar and order each to the middle airport. Both repeat
their own orders and share one passenger queue. The runway, approach
and stands are reserved by the source airport controller rather than
a capacity-1 shortcut. Inspect the middle field to see both aircraft's
independent loads, fares and costs. Two planes and three airfields cost
$98,162; allow for ongoing expenses or use the in-game company loan.
The shared-runway preset uses only Sampsons and one purchase per
hangar. Use the single-plane preset above for the Coleman Count.

### Farm, factory and town Goods

Set `bayline_scenario = farm` in a **fresh seed-1751
world**. Use a separate world from the timber preset so there is
one Goods handler. Road Freight lets you build the roads,
three freight stops and a depot. At the farm, the physical fields
change crop stages along the stock landscape clock. Crop furrows,
fencing and bales are not independent industry producers.

Buy the **Hereford Grain Truck** ($6,234; 20t) and
**Talbott Livestock Van** ($5,742; 14 animals), and order each to
load at the farm and deliver to the factory. Then order a **Balogh
Goods Truck** ($5,851; 14 crates) from that same factory stop to a
town Goods stop. Inspect the factory and its stop to distinguish paid
inbound cargo from stored and dispatched Goods. It processes each
accepted input independently, rather than requiring a fixed recipe.
All three operate on the same campaign clock and keep their actual
cargo through saves.

See [Farm workbench layout](FARM_FACTORY_WORLD.md) for the exact
site coordinates and working direction-preserving road turnarounds.
The preset adds one farm and one factory, not a complete industry
world or a new Steel supply chain.

### Conventional railway blocks

Set `bayline_rail_block_preview = true` in a separate fresh world.
Railworks → Rail Signals (5) → **Conventional block signal (4)**
places a forward head. Rotate the fitting before placing signals on
the perpendicular line. In the same menu choose **Order block
pilot (7)**, then click a depot and its destination platform. You may
order two empty trains on separate straight lines through an unsigned
diamond, with forward blocks on both sides. Pause before you order
both to watch them contest the same block. The waiting train sees the
original red head until the other train's whole consist clears the
protected track. No PBS mixing, paid cargo, or shuttle orders here.

On untouched seed 1751, use [this working layout](RAIL_BLOCK_DISPATCH.md).
The normal paid paths and PBS are separate options.

### Explore stock Original terrain

A separate optional 64×64 native map uses the OpenTTD Original
temperate geography, with true slopes, coast and level water. It is
read-only flight and inspection (not the company campaign). It needs a
locally extracted OpenGFX mask bank and a new SQLite world. Follow
[Original Terrain Exploration](docs/original-terrain-exploration.md).

### Run a standalone server

A normal world pauses with nobody connected. To run a dedicated campaign
without viewers, set `bayline_offline_economy = true`. The same paid
transport and town clock advances, saves regularly and resumes on
SQLite restart. Visible scenery catches up when players return, without
replaying old fare popups and sounds. Pausing time still stops the
economy. The empty, view-driven demonstration pilots are not run
headlessly.


Set `LUANTI_GAME_PATH` to the directory containing the `bayline` directory
(or use the normal user game directory). For example:

```sh
LUANTI_GAME_PATH="$PWD" luantiserver --gameid bayline --world "$PWD/bayline-world"
```

Use Luanti's usual network and server config. This project does not publish
or configure a server automatically. Each player name owns its own company;
the first company or server administrator can set speed. Simulation pauses
when no players are connected. A new world can set `bayline_seed` (default
1751) in its Luanti config; `bayline_seconds_per_day` defaults to 1.25.
Back up the whole world directory to preserve the simulation and login state.

## Road-first scope

In Roadworks select **AutoRoad (2)**. Click to place one half of a tile,
or hold the left mouse button, aim along either axis, and release to build
the quoted straight run. Right-click during a drag to cancel. Make bends
with a second run. Existing compatible approaches, including railroad
crossings, can connect even when they sit just outside your selection.
Stops retain the underlying road connection and must be within five tiles
of a town or industry. A depot needs a compatible roadside entrance.

The current default covers passenger bus service, terrain-aware road and
foundation construction, depots, stops, cyclic orders, company finance,
and saving and resuming the fleet. Each player owns their own company.
The game does not yet offer full OpenTTD traffic behavior, world scale,
mod support, or playable save interchange. Don't rely on prototype
non-road tools or legacy-world compatibility.

## Verify or develop

- Simulation: `lua5.1 tests/sim.lua` from the game directory.
- Luanti process + SQLite restart: `tests/engine.sh /path/to/luantiserver`.
  The harness copies the game to a temp directory, opens a loopback server,
  drives a first delivery, checks a generated stop node, and restarts to
  validate the saved orders, in-transit position, and revenue.
- Fresh-world graphical playtest: `BAYLINE_NATIVE_FRESH=1 tests/native.sh`.
  In this profile the fixture refuses camera cheat commands; the test targets
  the starter sites using actual relative mouse motion. Set
  `BAYLINE_NATIVE_GRADE=1` separately to exercise the deterministic ramp fixture.
- Art: `python3 tools/make_art.py` and `python3 tools/build_dispatch_icons.py`
  (Pillow needed only when regenerating art).
- `mods/bayline/sim.lua` is the authoritative sim, independent of Luanti.
  `ui.lua` translates player actions, `render.lua` projects the state
  into scenery and 3D traffic, `world.lua` handles flying, targeting and
  the hotbar, and `init.lua` binds save/load and clock.
- The ten editable prototype Blender files are in `art/`. Re-export meshes
  with `blender -b --python tools/build_vehicle_art.py`. Asset reference and
  license status is in `art/README.md`. Waiting passengers use short-lived, bus-scaled platform silhouettes driven by the actual stop queue, with a visual cap for very large queues.

References: [OpenTTD manual](https://wiki.openttd.org/en/Manual/) for feature
comparison, [Luanti formspec reference](https://api.luanti.org/formspec/)
for the native dispatcher.

## License and attribution

LuanTTD's integrated game code is GPL-2.0-only. See [LICENSE](LICENSE)
and [NOTICE.md](NOTICE.md). It includes Lua ports from OpenTTD 14.1,
not the original executable or commercial graphics. The game folder is
`bayline` for Luanti game-ID compatibility.
