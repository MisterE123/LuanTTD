# Changelog

## November 23, 2026 development preview

- Use **Survey** to walk, drive from inside a car, fly from a Country or City
  Airport, sit in a train driver's cab, or ride in a bus or coach. The seated
  view is private: other players see the normal vehicle. Exit to recover
  your builder view and tools.
- Road and railway tunnels now have native open bores and real running surfaces
  underneath intact surface terrain. Restored visible repair smoke; working
  trains and real industrial chimneys have local exhaust. Fixed overlapping
  farm building roofs, trim and silo surfaces.
- **Transport Gazette** ports stock RC1 newspaper ordering, category
  preferences and history. The worker reports real vehicle introductions,
  first arrivals, rail collisions and installed-industry changes. Not every
  upstream event producer is connected yet.
- Depots scroll without cutting off complete model names. Restore an
  independent Copy Orders action for stopped road vehicles. The Jump Map
  has finer detail, named towns and simple area targets.
- Add six native freight wagons for Iron Ore, Steel, Valuables, Livestock,
  Grain and Wood, four Darwin and four Bakewell Luckett aircraft, a
  dozen completed town/retail appearances and the source construction stages
  for all 27 single-tile Temperate town building types.

## Current preview

- The install folder and game ID are now `luanttd`. The bundled mod is
  `luanttd_core`; game nodes, items and entities use `luanttd_core:`.
  Start a fresh world; older `bayline` saves are not migrated.
- Added a living [State of the Port](PORTING.md) with scoped
  parity claims, intentional Luanti differences, and unfinished systems.

## Overnight development preview

- Road traffic occupies its own lane and protects verified shared
  junctions and two-bay turnaround aprons. A third bus queues outside
  instead of clipping parked buses. Source-timed contemporary buses can
  share or copy orders, break down and repair in place, and make a
  YAPF depot service detour without abandoning passengers or orders.
- Complete native farm/factory and oil/refinery freight routes are
  available in separate optional fresh worlds. Actual cargo pays at
  the processor; a separate Goods route earns its own town fare.
- New modeled stock rail: Ginzu 'A4' steam and Floss '47' diesel.
  Purchased Kirby and Ginzu trains can also share a directionally
  reserved paid route. Ordinary block signals and path signals are
  separate tested workbenches.
- Original stock terrain can be explored up to 4,096 tiles on each
  axis in a separate read-only world. Stock source road, rail, air
  and water systems in the regular company world are smaller.
- Actual private Linux playtests verify the unpacked artifacts across
  SQLite restarts. This is not 1.0 and does not offer general OpenTTD
  save interchange. Only narrow stock construction/edit proofs
  have passed in that separate interoperability lab.


## 0.3.0

- Fresh worlds prevent overlapping models at supported ordinary road
  junctions by waiting for the first vehicle to clear. Exact stock viewport
  behavior remains available separately. Added optional genuine MPS Regal
  procurement, with 31 seats and its OpenTTD running/depreciation economics.

- Added opt-in hangar purchase and paid service for the original Sampson U52
  and Coleman Count. Both use the stock runway controller; the Coleman
  has its own native airframe and two gear states. Covers 25/65 passenger
  seats, exact purchase and running cost, and restored flight and fares.


- The game now starts in 3D with a fly camera, native hotbar, Inventory control desk, and live HUD. Build directly on terrain; the map is only for teleporting.
- Ten original Blender prototype vehicles and exported mesh files replace flat vehicle markers in the world. Adjacent traffic movement interpolates between simulation days.
- Small opt-out effects suggest waiting passengers near busy stops. Passenger counts and payments remain authoritative in the sim.
- Fixed default terrain mapgen, added 3D scenery, and rendered one centered road/track per logical tile. Fresh worlds are recommended for clean scenery.
- Still a 48×36 region with main-thread simulation; large sparse worker-backed worlds and reference-refined vehicle art remain planned.

## 0.2.0

- Signaled corridors now permit multiple trains to follow the same directed
  path with a two-tile gap. With no signal, the route remains exclusive.
- Opposing trains retain exclusive use of shared track. A waiting reverse
  service prevents additional trains joining the current-direction convoy.
- Rail dispatch can choose an unclaimed alternative. Parked trains occupy a
  terminal siding abstractly; intermediate terminal tiles are protected.
- Existing worlds require no save migration; traffic occupancy is rebuilt
  from active routes. New native tests cover a convoy before and after a
  restart. This is not OpenTTD's full path and block signaling.
