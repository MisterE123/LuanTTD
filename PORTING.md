# OpenTTD source port and release gate

LuanTTD targets recognizable OpenTTD behavior behind a Luanti-native 3D
interface. Treat simplified legacy simulations as scaffolding, not a port.
Port core behavior and its data together. Keep OpenTTD's own client as the
reference executable and retain named source files, notices, source revision
and regression fixtures. Original models, environments and UI are separate from
the simulation; do not distribute proprietary or unverified art.

## Version and license

The first pin is [OpenTTD 14.1](https://github.com/OpenTTD/OpenTTD/tree/14.1),
the local reference client's version. Integrated game code containing or
linking these ports is GPL-2.0-only. The complete corresponding Lua,
asset-authoring inputs in the project and packaging scripts accompany releases.
See `COPYING.OpenTTD.md` for the upstream license and `art/README.md` for art
provenance. Keep additional notices when importing more code.

| Integration | OpenTTD source | Status |
| --- | --- | --- |
| Slope classification and sampling | `src/tile_map.cpp` / GetTileSlopeGivenHeight, `src/slope_type.h`, `src/landscape.cpp` / GetPartialPixelZ and ApplyFoundationToSlope | Lua port in `mods/bayline/openttd/slope.lua`, not wired to the legacy world. Exact integer differential test and continuous version for 3D tile edges. |
| Terrain editing and road foundations | `src/terraform_cmd.cpp`, `src/road_cmd.cpp`, `src/landscape.cpp` | Shared corner grid and corner propagation port tested against C++; off-by-default 3D preview uses generated terrain meshes and exact picking. The road-edge legality and foundation decision port is verified against C++ and is active in preview worlds for standard roads. Roads charge for placed pieces and foundations at prototype LuanTTD rates; flat stops and depots connect to reciprocal grade-checked road edges. Ramp meshes, ray picking and bus center height use the same surface. Player corner and area terraforming now uses validated stock commands through a protected-ground adapter. Optional timber and steel girder bridge construction uses paired heads, shared clearance, price and a continuous 3D deck. Road routing crosses the paired span with source wormhole motion, actual bridge speed cap, and tagged deck height, including separate underpasses. Paired road tunnels use the stock cost and visibility frames with independently modeled open portals; this preview accepts complementary clear slopes and no layered bores. Other bridge designs, exit excavation and terminal placement on slopes remain open. |
| Road service and economics | Road tile bits and vehicle trackdir; road pathfinder; order, loading and payment code | The road-first campaign uses source-derived selective station supply, station packet identity, onboard age, final distance and default passenger fare. Stock station rating, queue loss, pickup and unload age counters, and selective cargo eligibility now run for road passenger stops. Fresh road worlds now use the source vanilla house production table and tile loop, with explicit house archetypes mapped to the authored scene and stock three-tile catchments. Station ticks precede production and share a saved source RNG stream. The optional live service processes the source loading cadence inside the 74-tick daily simulation and shares its house clock with paid rail, ferry and air. Legacy road service remains day-batched. Omitted stock RNG callers and authored scenery preclude full-world parity. Optional mail van uses the same source house cadence for mail, separate truck stop goods and acceptance, 22-bag capacity, aging and stock fare. Inflation, link graphs, exact dwell and town growth remain open. |
| Stock road pathfinder | `src/pathfinder/follow_track.hpp`, `src/road_cmd.cpp`, `src/track_type.h`, `src/pathfinder/yapf/yapf_road.cpp` | Directional track status, `CFollowTrackRoad`, `CYapfCostRoadT`, and the road destination/estimate methods have Lua translations. The follower, costs, generic YAPF controller, and its heap are differentially tested. A road-first bus now uses that search when departing a depot or bus stop. Through stops preserve the arrival heading and bays have one entrance. The adapter selects a complete leg at departure, including paired road bridges and tunnels. It enforces physical leader, depot-exit and single-bay occupancy checks during the leg. Full per-junction recalculation, shared/station bay layouts and articulated road vehicles remain open. |
| Road vehicle movement | `src/roadveh_cmd.cpp`, `src/table/roadveh_movement.h` | Road-first campaign buses now follow stock directional position samples and take the extra in-place heading steps on curves. Depot departure, ordinary/through roads, bay turnarounds and both driving-side tables are ported. Game runs right-hand traffic with a separate projection onto its modeled street lanes and slope profile. Fresh road campaigns advance the planned leg in 74 source movement ticks per simulated day using the original acceleration model, including fixed-point progress, turn slowdown and grade speed changes. The 74 steps interleave vehicles by ID; stock directional leader checks, depot exit and single-bay occupation are active. Rendering replays the shared physical tick timeline. Actual stock overtaking rows and frame counters run on supported plain straight approaches, with a separately documented host collision guard and save recovery. Paired bridge/tunnel motion is live; broader overtaking, multiple real station bays, and live branching remain open. |
| Rail topology, routing and signals | track types/directions, track-following rules, path reservation, YAPF costs and search | Stock six-piece geometry, foundation decisions, directional and signal state tables, and the rail track follower (including looking ahead for reservations) have compiled-source regressions. The optional Trackworks 3D construction sandbox uses those track pieces, documented grade support and the follower for inspection. Rail YAPF costs and local-cache search have differential matches and drive the sandbox planning command. Stock ordinary locomotive straight/half-tile position steps are differentially tested. An opt-in test locomotive rides the planned mesh pieces at a demo pace, timing relative progress with stock straight/curve movement units. A separate persisted single-locomotive pilot takes a stock order from a real depot to a multi-tile platform, using source acceleration, speed and stopping rules. Native Railworks houses coupled motion, path signals and reservations held through the actual rear car. An exclusive reversing two-platform pilot can earn stock passenger fares. Opt-in ordinary timber bridge and tunnel motion has its own one-way coupled pilot. General depot procurement, multi-train branching, complete signals, train freight, and broader rail hardware are not equivalent yet. Existing legacy tile/convoy code stays separate. |
| Coal freight | `src/industry_cmd.cpp`, `src/table/build_industry.h`, `src/table/engines.h`, `LoadUnloadVehicle` | Optional original stock mine → 20-ton Balogh-class truck → stock power-consumption chain. Built, ordered and paid in the actual native client, with physical loaded geometry and saved cargo. Funding industries, arbitrary cargo mixes and freight rail remain open. |
| Harbor and country airfield | Source ship follower/YAPF, canal/bridge/lock commands, airport FTA/movement tables, aircraft and passenger station controllers | One paid ferry and one paid fixed-wing shuttle can share real town catchments and payment. The optional harbor admits canals, locks and aqueducts. The 4×3 airfield runs an actual fixed-wing taxi, runway, holding and return path. Multi-vehicle terminal contention, broader types and air mail are open. |
| Real save checks | Pinned stock save schema, terrain slope and standard road frames | A real 256² sparse survey displays imported terrain and ordinary roads in native 3D. A separate acceptance program checks the paused running bus, orders, company and aged cargo and the original game's observed reference settlement. It is not a playable importer or exporter. |

## Next public-ready internal milestone

The released scope can be small but must be complete. First candidate:
one two-town road-passenger service, only controls and modes that are ready.
Use the 3D viewport for construction and orders; hotbar for primary tools,
compact side/context windows for secondary controls. Keep billboards optional
and skip them if they detract.

- **Terrain:** OpenTTD corner rules, matched raise/lower and leveling outcomes,
  clear slopes, real 3D foundation and road ramps. Terrain and infrastructure
  share a height truth; previews, ray picking, routes and vehicles agree.
- **Seams:** Native views at street and survey height for straight roads, both
  orientations of a bend, junctions, stops and sloped joins. No misalignment,
  gaps, flipped directions, obvious tiles beneath infrastructure or wheels
  that float/clip on ramps. Real vehicles successfully drive test routes.
- **Art:** Recognizable temperate palette, readable silhouettes and appropriately
  dense little towns, foliage, roads and station scenery. Every visible feature
  in this release needs a finished 3D asset, not a marker, labeled box or
  placeholder prop. This applies to buildings, nature and infrastructure,
  not just moving vehicles. No in-progress features in released scenarios
  or UI. Keep the original Blender sources and verify CC reference provenance
  when derivative; no copied OpenGFX sprites.
- **Playtest:** Human-equivalent mouse and keyboard from a fresh world in the
  graphical Linux client: build roads/stops/depot, purchase, assign two
  world-picked stops, dispatch, observe boarding and payout, then save and
  reload while service continues. Run the equivalent OpenTTD task and record
  what diverges, including a matching slope/foundation case. Inspect snapshots
  at multiple heights and a short video of moving vehicles. Tests supplement
  this, not replace it. No numbered release until the experience passes.

### Electric tram network adapter

`tram_network.lua` maps the shared-corner save lattice to stock ELRL construction and stock road YAPF. It prices and applies straight/curved track drags atomically, isolates tram bits and ownership from the accompanying road, and models actual directional depot/through-stop records. The initial scope is flat at-grade construction; it rejects terrain, bridge/tunnel and building conflicts rather than silently clearing them. `tests/tram_network.lua` covers price, authorization/occupancy, failed drags, reloadable depot-to-curved-stop routing, and separation from the normal road board. The flat preview now connects native hotbar construction, original 3D assets and one persisted reversing tram service. Shared-road physical arbitration and commercial tram loading do not ship.
