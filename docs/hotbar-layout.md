# Native construction hotbars

Open **Roadworks** or **Rail Construction** from Home. Use the number
shown above the selected icon, then left-click to open a section or
use a tool. Each section shows exactly the tools it contains:

- **1: Back** in submenus.
- **2: Bulldoze** wherever that submenu provides it.
- **Teleport above tile** follows the common actions. Aim at a square
  and click to jump directly above it. In a full row, right-click
  Teleport to inspect instead; shorter rows also have Inspect.
- Other keys depend on the section and the features in that world.
  The tenth slot, if present, uses **0**.
- **Route orders** use the same hotbar controls across modes. **Pick stop**
  is initially selected. For road schedules, **Done** or right-click
  returns to the vehicle window; **Start service** is separate.
  For rail, sea, air and the test tram, pick the required stops, then
  select and click **Dispatch** to run the route. **Cancel** or right-click
  leaves without dispatching. The legend shows the actual key for each
  action because Luanti may retain the previous physical slot.

Right-click also cancels a pending build, or opens the tile's context
when there is nothing to cancel.

## Where tools live

- **Roadworks** offers **AutoRoad**, bus stops, road depots, bridges and
  tunnels. **Road Freight** has truck stops and depots. **Road Options**
  has one-way roads and **Tramways** where available.
- **Rail Construction** offers **AutoRail**, platforms, depots,
  signals, bridges and tunnels. **Rail Tools and Operations →
  Rail Engineering** has manual pieces, conversion and spans.
  **Rail Tools & Operations → Rail Waypoints** places or removes
  non-stopping [train route markers](rail-waypoints.md).
- **Sea & Air** opens **Harbors** or **Airfields**.
- **Navigation → Jump Map** is for travel. **Controls →
  Workbenches & Scenarios** or `/workbenches` shows the active features.

**Bridge:** choose the near and far bridgeheads, then select a bridge
type from the price list. **Tunnel:** aim at an uphill entry to preview
the exit, then click the entry. For supported structures, aim Bulldoze
at a bridgehead or portal to remove the whole structure.

## Comparison with OpenTTD 14.1

The actual stock 14.1 road and rail toolbars open separately. Both put
ordinary construction, depot, stops/stations, bulldoze, bridge and tunnel
directly on their own toolbar. Their Bridge actions mark the aligned
endpoints before opening the type list; Tunnel sends its single clicked
entry to `CMD_BUILD_TUNNEL`. The two regular construction commands
produce a crossing on suitable perpendicular existing transport, rather
than requiring a dedicated crossing tool. Stock ports are in
`src/road_gui.cpp`, `src/rail_gui.cpp`, `src/bridge_gui.cpp`,
`src/road_cmd.cpp` and `src/rail_cmd.cpp`. The toolbar demolition action
in road, rail, tram, docks, airports and landscaping is the shared
`PlaceProc_DemolishArea` action, distinct from individual piece removal.

AutoRoad uses OpenTTD’s straight-axis held gesture. To build a turn in
one drag, hold **E** (Aux1) while aiming across both axes and keep it
held as you release left-click. The longer leg comes first; drag from
the other end to choose the opposite corner. If the bend is blocked,
nothing is charged or placed. This is a LuanTTD extension. AutoRail
also uses click-and-drag for stock straight or diagonal track; a single
click lays one piece. Bulldoze uses the stock rectangle
or diagonal ordering and progressive budget. Some transport
prerequisites and per-tile rules remain stricter than stock.

### Bulldoze a selection

In a shared-corner world, click and release to clear one tile as before.
Hold left-click, aim at the other corner, and release to clear a rectangle.
Hold **Aux1** (normally **E**) when releasing for a stock diagonal
selection. Right-click while holding to cancel. The preview lists the
affordable part of the selection. Protected cells are skipped, and work
stops at the first otherwise clearable cell the company cannot afford or
when its clearing allowance is used. Bridge and tunnel dismantling stays
on a single click at a supported structure's portal, not on area drags.
