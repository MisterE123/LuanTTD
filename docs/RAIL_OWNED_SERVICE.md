# Owned steam passenger shuttle

The owned-service mount is separate from the existing free MJS movement pilot. It is deliberately restricted to one purchased Kirby Paul Tank or Chaney ‘Jubilee’, and one purchased stock Passenger Carriage, with two alternating platforms on a supported ordinary stock route. The 1950 Temperate public fleet can also buy coal wagons; they cannot depart through the passenger service. No starter stock is created for free. One active route is supported at a time. It is not the complete rail vehicle depot or a general-purpose timetable.

## Mount

In the native setup, load `RailRoster`, pass it as the last optional argument to the existing `rail_dispatch_run.lua` factory (after Crossings), and bind:

```lua
local Depot = dofile(mod.."/rail_depot_fleet.lua")(Sim, Lab, RailRoster)
local Owned = dofile(mod.."/rail_owned_service.lua")(Depot, RailRoster, Pilot)
```

Keep using `Sim.mount_paid_rail(S, Pilot)`. The separate owned flag is `S.rail_owned_service`; in a new world pass the configured seed, world startup design draw, climate and calendar to `Owned.initialize(S, config)`. Don't reinitialize persisted data. A launch needs `S.rail_paid_service`, shared stock house clock and corner terrain. Existing dispatch exclusivity and route safety still apply.

- Quote and buy with `Owned.quote(S, owner, depot, {0,27})`, (or `{8,27}` for the Jubilee) then `Owned.commit(S, owner, quote)`; save after successful commit. The controller never buys or charges a second time to launch.
- `Owned.start(S, owner, fleet_id, first_station_id, second_station_id)` pairs a staged receipt in its owned depot with a real shuttle route and saves the role of each part. Don't persist transient objects. Save accepted starts and stop/resume actions.
- `Owned.toggle(S, owner, fleet_id)` applies the usual stock stopped/braking behavior and resumes the same orders; it retains PBS paths and occupied track. The old pilot's destructive Clear command refuses an owned train. Safe depot return, reopening a completed consist, sale and consist modification are future work.
- `Owned.list/get/catalog/running/occupies_depot` are read-only. Protect depots containing staged stock before demolition. After dispatch, use the existing active railway protection, including occupied spans and crossings.

The live route uses the purchased engine's source values: Kirby 64 stock speed, 300 hp and 47 tons; Jubilee 112 stock speed, 1,000 hp and 131 tons. Both use the 25-ton, 40-seat coach, with exact passenger weight and running cost from the chosen model. The Jubilee requires its own native OBJ and PNG to be installed; no alternate locomotive is rendered. A restored Jubilee is paused if the package has lost those files. Paired and coal orders remain Kirby-only. Coach station arrival uses the real wagon tile, source loading timing and fare, and reservations survive physics and reload. The renderer mounts the native original steam model at its actual railhead datum; paid render samples keep span occupancy identity and hide parts inside the tunnel. When the span and crossing adapters are installed, this route uses their existing bridge/tunnel traversal, slope and road–rail admission rules. The non-owned MJS pilot stays available as a separate test mode with its original values and asset.

Every eligible stock train handler tick is counted once (not per movement pass), including loading and waiting at signals, and braking until stopped. A fully stopped train accrues no new ticks. On the next economy day the actual elapsed ticks are charged as `floor(annual_rate_fp * active_ticks / (365 * 74))` using the company’s shared 8-bit cash fraction. The persistent settlement record never recharges the same ticks after save/reload, and deliberately does not invent retroactive bills from old preview saves that lack daily history. Disabling paid rail freezes ticks and defers any pending settlement until it is enabled again. This uses the same host economy-day boundary as owned coal rail: the source’s intra-day stagger by global lead VehicleID is not reproduced, because the current host has no verified global pool index. The tests verify the actual cash, total expense, daily ticks, fixed-point rounding, and company fraction. Model reliability is seeded at purchase; in-service reliability decay, breakdowns and servicing are not enabled. The separate one-way owned coal service is documented in [RAIL_COAL_PORT.md](RAIL_COAL_PORT.md).

## Regressions

```sh
lua5.1 tests/rail_owned_service.lua
lua5.1 tests/rail_owned_service.lua spans
lua5.1 tests/rail_owned_service.lua finance
lua5.1 tests/rail_owned_service.lua jubilee
lua5.1 tests/rail_owned_service.lua jubilee_spans
lua5.1 tests/rail_paid_runtime.lua air
BAYLINE_NATIVE_TOOLS=/path/to/tools tests/rail_owned_live_native.sh
BAYLINE_NATIVE_JUBILEE=true BAYLINE_NATIVE_TOOLS=/path/to/tools tests/rail_owned_live_native.sh
```

The owned test covers wrong consist/owner, exact quote debit, stopped depot reload, source kinematics, serialized load/paid states, continuing shuttle reversals, real per-coach mass and fares, and (span mode) source-backed timber bridge, masonry tunnel and level crossing. The finance case verifies same-day idempotence, exact partial braking ticks, parked and disabled days, January 1 rollover, and the no-back-bill migration of old owned saves. The existing multiservice fixture still covers road, rail, ferry and air on the common clock.

The native fixture boots two Luanti server processes against the same SQLite world. It verifies purchased entity mesh registration and actual wheel datum before and after a saved boarding stop, then checks that the saved commercial vehicle accrues new running expense, earns fare and reverses again. It leaves client mouse/camera usability to the separate visual QA.
