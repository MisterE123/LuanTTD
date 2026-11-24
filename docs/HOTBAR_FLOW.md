# LuanTTD hotbar design: OpenTTD 16.0-RC1 flow audit

Reference: OpenTTD 16.0-RC1 tree `07b339c0aaeb0a87be9490b2f1c3f17c6b00b837`.
This maps the normal game first, then marks editor-only routes and LuanTTD gaps.
It describes the player-facing interaction hierarchy, not every NewGRF extension.

## 1. OpenTTD: persistent toolbar → window → viewport

The top row is persistent. A button can act directly (Pause, Zoom), open a drop-down
(Finances, maps, vehicle company/type, rail/road type), or open a dedicated construction
window. Several other windows can coexist without replacing the toolbar. Each build
window arms a cursor, which stays armed across legal placements according to the
persistent-tool setting. Esc/right-click exits a placement; closing a toolbar clears
its child pickers. Its narrow-screen switch swaps grouped toolbar sections; it does
not collapse every task into an arbitrary “More”. See
[`toolbar_gui.cpp`](https://github.com/OpenTTD/OpenTTD/blob/16.0-RC1/src/toolbar_gui.cpp).

| Top-level family | Routes and child windows |
| --- | --- |
| Time / game | Pause, fast-forward; Settings → game options, advanced settings, NewGRF, AI/Game Scripts, transparency, town names and similar display controls; Save / Load / Quit / Exit. |
| World | Small map → minimap (display layers), extra viewport, sign list; town directory → town view → local authority/available actions; zoom in/out; Help → land information cursor, about, screenshot commands, console/inspection options as configured. |
| Company / economy | Stations → select company → filter by train, truck, bus, air, ship and cargo; Finances → select company → annual finances and borrow/repay; Company/client list → profile, HQ, livery and other company controls; Story and goals → choose company; graphs → operating profit, income, cargo delivered, performance, value, payment rates; league → ranking/performance details; Industries → directory, chain, fund industry. |
| Trains | Company route or Ctrl shortcut to own rail vehicle list; list → sort/filter/group or available trains; click a train → individual vehicle window; optional shared-order list. |
| Road vehicles | Same company selection/list structure for buses and trucks (trams are a road-vehicle subsystem); own list → sort/filter/group, available vehicles, individual vehicle view. |
| Ships | Company selection → ship list → sort/filter/group, available ships, individual vessel view. |
| Aircraft | Company selection → aircraft list → sort/filter/group, available aircraft, individual aircraft view. |
| Construction | Rail type (conventional/electric/monorail/maglev) → rail tools; road type → road tools; tram type → same class of road tools variant; dock and waterways; airports; landscaping. |
| Sound / news | Music and sound jukebox/settings; messages/news → latest item, history, message settings. |

### Construction tool map

| Branch | Tools → secondary choice → placement |
| --- | --- |
| [Rail](https://github.com/OpenTTD/OpenTTD/blob/16.0-RC1/src/rail_gui.cpp) | Four fixed track directions and AutoRail → aim at rail fragment / drag → build; Remove mode reuses selected rail tool. Depot → four orientations → place and potentially connect; waypoint → graphic type (if applicable) → drag on track → join/new; station → orientation, station class/type, platform length/count or drag, catchment, Ctrl join/separate → place; Signal → variants (semaphore/electric; block, entry, exit, combo, path, one-way path where enabled), density on drag, convert; bridge → pick both ends → type/price/speed list; tunnel → preview distant portal → place; Convert rail → target rail type → drag; demolish → point/area. Crossing built by overlaying compatible road and rail, not a mandatory separate task. |
| [Road and tram](https://github.com/OpenTTD/OpenTTD/blob/16.0-RC1/src/road_gui.cpp) | X or Y direction and AutoRoad drag, half-tile starts and ends; one-way (road only) and remove are modes on selected tools; depot → four orientations; passenger stop / truck loading bay → bay or drive-through orientation, applicable type, drag, catchment, Ctrl join/new; road waypoint → choose type, drag on road, optional join; bridges and tunnels follow rail's endpoint workflow; convert selected road/tram type over area; demolish. |
| [Water](https://github.com/OpenTTD/OpenTTD/blob/16.0-RC1/src/dock_gui.cpp) | Canal drag; lock on suitable slope; depot X/Y orientation; dock slope with catchment and Ctrl join/new; buoy in open water; aqueduct end-to-end; demolish. Place River is editor-only. |
| [Air](https://github.com/OpenTTD/OpenTTD/blob/16.0-RC1/src/airport_gui.cpp) | Airport → airport class and available designs (small, commuter, urban, metropolitan, international, intercontinental, heliports/helidepots/helistations and optional content), layout rotation when supplied, catchment, cost, noise → preview → place or join; demolish. Once built, airport/hangar are distinct interactions. |
| [Landscaping](https://github.com/OpenTTD/OpenTTD/blob/16.0-RC1/src/terraform_gui.cpp) | Lower/raise corners or area; level drag; demolish area; buy land; plant trees (palette or random); sign; object picker class/type → place. Editor adds generation/reset, brush size, rocks/rough/desert, free placement/editing; not normal-company tools. |

### Service flow for every mode

1. Build connected infrastructure or usable water/air space, two compatible destinations,
   and local business facilities; inspect station catchment/acceptance before buying.
2. Click the owned depot/hangar → [depot window](https://github.com/OpenTTD/OpenTTD/blob/16.0-RC1/src/depot_gui.cpp)
   → New Vehicles → [model purchase window](https://github.com/OpenTTD/OpenTTD/blob/16.0-RC1/src/build_vehicle_gui.cpp)
   (year/type/cargo availability, filtering, specs) → buy. For rail, buy an engine and
   attach wagons; also clone with copied or shared orders. Depot window supports vehicle
   lists, detail, sale, mass start/stop and available replacement actions.
3. Click the vehicle → [vehicle window](https://github.com/OpenTTD/OpenTTD/blob/16.0-RC1/src/vehicle_gui.cpp)
   → location (and order destination), start/stop, depot/service, refit, clone, orders,
   details and applicable train reverse/force-through controls.
4. [Orders](https://github.com/OpenTTD/OpenTTD/blob/16.0-RC1/src/order_gui.cpp) → Go To →
   select a compatible station, waypoint or depot in the world; alternatives include
   copying/share from another vehicle, nearest depot, conditional orders. List rows expose
   skip/delete, non-stop/via, load/unload, refit, service/stop/depot actions, and timetable/
   shared lists where applicable. Start/stop belongs to the vehicle, not the build cursor.
5. Click a [station](https://github.com/OpenTTD/OpenTTD/blob/16.0-RC1/src/station_gui.cpp) →
   cargo waiting/ratings/acceptance, center/catchment, scheduled train/road/ship/air lists,
   rename, applicable airport closure. Fleet lists also link to vehicles without finding them
   in the viewport.

## 2. Translate interaction, not window geometry

| OpenTTD has | LuanTTD constraint and choice |
| --- | --- |
| Persistent 30-button launcher, optional toolbar split | One 10-slot spatial hotbar, camera-centered. Give common transport modes direct access and put specialist actions beneath meaningful categories, not arbitrary extras. |
| Pointer can click the toolbar without moving camera | Number/wheel/tap selects a slot; primary action applies it. Desktop and touch must not need a right-click or chat to reach a depot. Use the same explicit **Open depot / hangar** in every build branch; leave shortcuts as acceleration. |
| Construction window and context windows coexist | Restore the exact prior row after scoped order picking. Build, mode effects, and dispatch stay distinct; keep Back, Bulldoze, and survey/inspect utilities predictable. |
| Stock tool variants often share a button, with states in a picker | Preserve variant IDs and existing authoritative command calls. Keep selection variants in child rows. Avoid deep menu visits for first road/station/depot work; avoid adding buttons for unported features. |
| Fixed isometric map and click-oriented viewport | Keep teleport/inspect and jump map on the survey branch. “Buy / order” aims at a depot, not an arbitrary world placement. Label actions where aim matters and use different icons for Open, Build and Dispatch. |

### New task paths

- **Road** → AutoRoad, passenger stops, truck-stop capability, depot, **Open depot**; road variants,
  one-way, routing/removal stay in the road family; through/depot layout choices remain available.
- **Rail** → AutoRail, station, depot, **Open depot**; track shape, signals, crossings, spans,
  track conversion/gauges, plus separate operations and freight branches.
- **Water** → dock, ship depot, **Open depot**, canals/locks/buoys/aqueduct branch, vessel operations
  and removal. **Air** → country/city/rotary facilities, **Open hangar**, manage aircraft.
- **Fleet** → actual unified company vehicles screen, individual vehicle → Orders → pick in world
  → return to exact prior toolbar. **Survey** → inspect, jump/camera tools and World Guide.
- **Company** → finances/time, HQ/bank capability; **Landscaping** → core territory edits; **Controls**
  → help, settings and audio.

Out of presently implemented toolbar scope: editor tooling, generic object/sign placement,
full industry funding and chains across all climates, an OpenTTD-style company selector for
all foreign companies, all station/fleet/group actions, conditional/timetable order parity,
every stock signal variant and every airport layout. Presence in the flow map does not claim
these features are implemented.

### Construction rhythm and first service

Road and rail start with the same spatial order: tools **4** lay infrastructure,
**5** place a stop or station, **6** build a depot, **7** open that depot, and
**8** opens spans. Rail's next tiles are Signals and rail operations, with
visible names and help instead of a generic wrench. Harbor places the dock,
ship depot and **Open depot** together before Waterworks. Utility order is
unchanged: Back, Bulldoze, Teleport (secondary action Inspect).

After buying a vehicle, open it from the depot. Train and ferry setup
offer world picks as well as station lists, then review and explicit Start.
The back button returns to the original depot and selection. Bus depots
start on the first available passenger vehicle, without removing freight
choices. The window retains normal vehicle Follow; passenger sightseeing
is a nearby Walk interaction, not an administrative fleet control.

### Completeness check

The task presentation is derived from mounted tool definitions, not a second
list of feature switches. The automated comparison traverses every visible row
and checks that every previously mounted action remains reachable, with its
own existing or new icon. It checks both bridge-picker paths and minimal and
full mounts. It also checks exact slot count, Back restoring the parent row,
peer transport launchers, and the role separation of Build versus Open depot.

Deliberate differences from the previous live presentation:
- Air and Water each get a home launcher; the combined index remains reachable through Survey → Navigation.
- Tram construction has a peer launcher as well as its original Road Options shortcut.
- Road's primary row carries the ordinary passenger stop; the variants, removers, waypoint and truck freight remain together below it.
- Bridges and tunnels are grouped on the Road and Rail rows; the fallback bridge-type selector remains present.
- Rail modes still keep manual pieces, signals, types, crossings and tested special service actions.
- Vehicle orders keep the prior row while a replacement pick bar is active. Fleet lists can be filtered to Road, Rail, Water, Air or Tram from a tap-friendly tab strip, while the All tab stays the default.

Regression commands: `lua5.1 tests/hotbar_task_flows.lua` and
`bash tests/hotbar_task_native.sh` (graphical client with Xvfb and xdotool).
