# Stock road vehicle reliability and breakdowns

This OpenTTD 14.1 port covers conventional road reliability aging,
scheduling a breakdown, timing the actual stop and recovery, and
resetting the correct fields when serviced.

## In the game

Use a fresh world with `bayline_stock_bus_catalog = true`. Set
`bayline_stock_bus_breakdowns = 1` (reduced) or `2` (normal); the
default for the development preview is `0` (off). Only those original
catalogue buses are affected. The vehicle inspector shows reliability
and reports an actual stoppage as **Broken down**. The vehicle waits in
its real lane, keeps the same route/orders and recovers by stock ticks.
A saved failure continues to repair even when you turn off new failures.

An actual depot arrival and its later safe release service the bus.
Use Fleet → Park in depot after stopping and unloading. There is no
automatic engine replacement, articulated road model, or separate
wallclock economy/calendar. Short, local smoke puffs identify a true
active repair, not a traffic wait; they are cosmetic and stay paused
with the sim. The game uses the campaign's
seeded shared RNG and 74-tick clock, not a claim of complete global
OpenTTD RNG replay.

## Mounting contract

Load `mods/bayline/openttd/road_breakdowns.lua` with `dofile`. Allocate one
plain serializable state per vehicle:

```lua
local state = B.new(current_engine_reliability, engine_reliability_decay,
  max_age_in_days, economy_date, calendar_date)
```

Use 16-bit source reliability/decay and the stock engine's vehicle life in
days (not sale-model life), e.g. from the corresponding engine calendar and
roster. A current engine snapshot is not the same as the vehicle's decayed
reliability. Persist (and restore without reseeding) the entire state,
including `tick_counter` parity, age/decay, chance, breakdown countdown,
delay, service tally, and both service dates.

- **Calendar day:** `B.calendar_day(state,{front=true})`. Front only; age
  increases independently of the economy calendar. Doubles the 16-bit decay
  at max age and at the next four stock Gregorian year offsets. It does not
  itself change the vehicle's reliability.
- **Economy day:** `B.economy_day(state,ctx,random32)` returns
  `scheduled,details_dirty`. The road controller calls this after the
  day/economy-age accounting and before automatic service/order/expense
  processing. `ctx.cur_speed` is the source integer speed, not a UI unit;
  `blocked_ctr` is the stock traffic state, not every reason to stand still.
  A nonzero blocked counter or non-front vehicle skips the entire breakdown
  check, including decay. Difficulty 0 / 1 / 2 is off / reduced / normal
  (stock default 1). `no_servicing_if_no_breakdowns` defaults true; with it
  false, difficulty 0 still decays reliability. Manual stop, low speed
  (<5), title/menu, or a pending/active fault suppress the random draw but
  do not by themselves suppress daily decay. Pass the authoritative global
  stock `Random()` draw as a callback, not per-vehicle private entropy;
  it is called once exactly when the source would call it. For global
  replay, vehicle-day order and every other system's draws also have to
  match; this module cannot establish that on its own.
- **Motion tick:** `B.tick(state,ctx)` owns the source byte counter
  increment (do not increment it a second time). Supply actual
  `cur_speed`, `loading`, `front`, `hidden`, and `crashed` from the host
  when applicable (crash includes the current collision check, which stock
  runs first). Only the front's breakdown is handled. Apply returned
  `cur_speed` and skip ordinary motion/loading processing when
  `hold_motion=true`. This flag only means held *by a breakdown*, not
  permission to move a non-front, crashed, or otherwise stopped vehicle.
  Loading freezes a countdown only if the current counter is >2.
  At 2 the vehicle actually stops; optional `started` is the sound/visual
  event then, not when the economy-day roll was made. `smoke_animation_state`
  is the raw source effect animation setting, absent when hidden or
  `no_breakdown_smoke`. During repair the delay decrements on an even
  post-increment tick. The final repair tick emits `recovered` **and still
  holds**; normal motion processing resumes on the next eligible tick.
  Do not set the player's stop switch, discard existing routes, or reset
  movement progress/subspeed. Stock running ticks count before the
  breakdown gate for a vehicle not manually stopped; the host should not
  treat this fault as switching running expenses off.
- **Actual servicing:** `B.service(state,current_engine_reliability,
  economy_date,calendar_date,difficulty)` sets both service dates, restores
  the engine's *current age-specific* reliability, clears the breakdowns
  since service count, and quarters chance (sets it to zero on reduced).
  It does not clear pending/active timers or undo aging's faster decay.
  Call it at actual stock service points: depot entry, when the automatic
  service pass services an already-depot chain, and when the head is
  successfully released at a safe depot exit. Retain both entry and exit
  calls, not one combined call; each real service has the stock chance
  mutation. Use actual depot entry/exit conditions from road movement.
  This module does not implement automatic service intervals, depot
  detours, replacement, game notifications, articulated vehicle chains,
  or NewGRF effects.

## Verification

```sh
lua5.1 tests/road_breakdowns.lua
PYTHONDONTWRITEBYTECODE=1 python tests/road_breakdowns_upstream.py /path/to/OpenTTD-14.1 lua5.1
```

The fixture starts from a real stock Regal road-engine snapshot and verifies
countdown, loading hold, stop, save/restore and repair release exactly. The
C++ differential compares 96,330 transitions and exact RNG draw counts across
all 64 reliability thresholds, trouble-roll boundaries, disabled/reduced/
normal modes, manual or traffic guards, calendar aging and service. It
compiles the pinned original `CheckVehicleBreakdown`, `HandleBreakdown`,
`VehicleServiceInDepot`, calendar/date arithmetic and `Chance16I`; the
original road tick and relevant road-controller/day and age prefixes run
with inert non-reliability interfaces. The reference draws from injected
32-bit words so eligibility and RNG consumption can be measured without
assuming full original timer/vehicle order in the Luanti host.

The graphical Linux test buys and orders a Foster Bus by mouse. It
then accelerates only that vehicle's wear/chance in the test observer;
the real stock daily draw, motion gate and repair steps do the rest.
A native SQLite reopen preserves the route, exact stopped position
and remaining repair time. The same bus earns fares afterward. The
test uses `BAYLINE_NATIVE_ROAD_FAULTS=1 BAYLINE_NATIVE_STOCK_FOSTER=1
BAYLINE_NATIVE_FRESH=1 tests/native.sh`.
