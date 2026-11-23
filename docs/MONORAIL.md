# First stock Monorail service

**Port target:** OpenTTD 16.0-RC1. The first playable fleet is the
X2001 (#54), Passenger Carriage (#57), and Mail Van (#58). They use
stock dates, separate depot purchase, power constraints, loading
and arrival procedures, and company charges and receipts. These
vehicles can be assembled individually or bought as one starter train.

## Start a service

Once the X2001 is available to your company, open **Rail Construction →
Rail Tools & Operations → Rail Engineering → Rail Types → Build monorail**.
Go back to Rail Construction and use AutoRail, Platform, and Depot as
usual. Monorail is a different gauge, so it cannot run on either
ordinary or electric railway. Switch back through **Build standard
railway** to build conventional rail. To try the X2001 in a fresh test
world without waiting for the date, set **Starting year** to **2010**
in the world creation screen. The same calendar governs the other
transport types.

Right-click your depot and buy **X2001 · Coach and Mail**, or open
**Assemble wagons** to buy the physical bodies separately. Order
two ordinary passenger platforms near houses. The train can carry
45 passengers and 35 bags in the two independent wagons. A simple
single-train shuttle does not need signals. The normal Depot and
Vehicle Orders controls are available; no text command is required.

Monorail uses the selected gauge for its timber bridge and tunnel
portals. Route through both correctly aligned heads. If a road passes
under a timber bridge, the overhead deck continues without a support
in the road. The same vehicle order can traverse open track, bridge
and a solid-terrain bore.

## Provenance and verification

- `src/table/railtypes.h`, `src/table/engines.h`, `src/engine.cpp`:
  stock types, costs, powered masks, 28 Temperate stock records, and
  calendar. `rail_cmd.cpp`, `station_cmd.cpp`, and
  `tunnelbridge_cmd.cpp`: rail compatibility, construction,
  station overlay quotes, depot and span geometry. `train_cmd.cpp`:
  stock route admission and moving front, reversal, per-tile
  acceleration type and paid loading.
- [Editable Blender and mesh pipeline](MONORAIL_ART.md): authentic
  running surface, independent articulated bogies, drawbars, and
  fitted original station/depot and bridge/tunnel meshes. The same
  guideway shape is visible in the AutoRail preview. Curves, grades
  and 45-degree seams carry the same uninterrupted wear band.
- `tests/monorail_owned_runtime.lua` and the `monorail` and
  `monorail-spans` native runs of
  `tests/stock_mixed_town_rail_live_native.sh`: real owned train,
  passenger/Mail supply, partial load and partial payment across two
  process/SQLite restarts, and stable physical body identities after a
  reversal. `tests/monorail_controls_native.sh` drives a fresh Luanti
  client without chat: lay track, a depot and two stations, inspect
  the yard, buy actual stock and start a real service.

**Scope:** First stock powered unit and two wagon types, on the
supported ordinary tracks, facilities, and tested spans. Maglev meshes
and data are present but not offered. Later stock, full-stock variant
and differing bridge styles, arbitrary mixed-gauge layouts, level
crossings and area conversion for advanced gauges are not claimed.
