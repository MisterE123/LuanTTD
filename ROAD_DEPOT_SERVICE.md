# Stock road service thresholds and automatic depot orders

This port models the OpenTTD 14.1 daily service decision for a single
ordinary road vehicle, and applies it to the original catalogue buses
in a supported native campaign.

## Use it in LuanTTD

Set `bayline_stock_bus_catalog = true` in a fresh world, enable reduced
or normal `bayline_stock_bus_breakdowns`, and set
`bayline_stock_bus_service_interval = 150` (days). The preview disables
automatic service by default (`0`). Set
`bayline_stock_bus_service_percent = true` to use an interval from 5
to 90 as the relative reliability percentage, not the displayed
absolute percent.

On ordinary moving road frames, a bus that is due can take a short
source-YAPF detour to a reachable owned depot. It doesn't move sideways
or jump to the depot, and it doesn't rewrite your schedule. Existing
passengers stay on board, the precise temporary route survives a
save, and after depot service the bus resumes the exact interrupted
stop. The preview waits for a representable ordinary frame rather
than retargeting inside a bridge, tunnel, crossing, station, or
temporary passing lane. There is no automatic engine replacement
or wallclock-mode service scheduling in the live adapter.

## When the stock vehicle is due

- `interval_due(health,ctx)` compares the saved vehicle reliability with
  `engine_reliability * (100 - interval) / 100` in integer percentage mode.
  The vehicle's reliability must be **strictly below** it. The comparison uses
  the current design age/reliability, not a fixed 100% baseline.
- Day mode requires the economy date be **past** the last-service date plus
  the configured interval, not merely equal. Wallclock mode converts each
  configured minute to **30 economy days**. Calendar age still serves the
  replacement eligibility check separately.
- `needs_servicing(health,ctx[,replacement_lookup])` applies those thresholds
  after stopping/crash guards. With breakdowns off and the stock setting
  that disables servicing when breakdowns are off, an ordinary detour is
  suppressed. The exception is an actual pending, company-available,
  age/refit-compatible replacement with money for the configured reserve
  plus twice the new engine purchase price. The optional pure lookup returns
  `{engine_available,replace_when_old,renew_months,has_refit_union,cargo_valid,
  accepts_current_cargo,reserve_money,available_money,replacement_price}`,
  or nil for no replacement. Supply authoritative company/group rule and
  design state. The module neither chooses a replacement nor performs it,
  and it does not support articulated mixed-cargo masks.
- `needs_automatic_servicing` additionally refuses an active loading order,
  a manual current depot order, a depot current order that belongs to the
  scheduled list, and any regular order list containing any depot order.
  An existing generated service-only/non-manual depot order is eligible
  to be reconsidered. Map current/list types to `{kind="goto_depot",depot_type,
  non_stop}` and `{kind="loading"}` where relevant.

## Applying a daily decision

Run `plan(health,ctx,hooks)` only at the original front's **economy day**
service stage, after `road_breakdowns.economy_day`. This particular stage is
not skipped by a nonzero traffic-blocked counter. Pass vehicle FLAGS for
stopped/crashed, current integer speed, true depot state and tile info,
current active order, persistent list (or authoritative `has_depot_order`),
per-vehicle `interval` and mode booleans `percent` / `wallclock`, and the
separate `company_service_interval` setting (zero disables automatic
service even if the vehicle's custom interval says it is due). Pass stock
`difficulty` and `no_servicing_if_no_breakdowns`. `health` is the flat
saved state from `road_breakdowns.lua`, which provides reliability, age, and
last economy service date.

`hooks.nearest(mode,max_penalty)` binds the **actual current vehicle and
trackdir** in the host and uses the chosen NPF/YAPF route implementation.
Return `{tile,depot,cost,...}` (distinct map tile and depot ID, penalty rather
than tile count), or nil for unreachable. Defaults are YAPF and 2000 cost
units for either pathfinder. Pass the cap into stock search if supported
and keep the outer test: infinity (`UINT_MAX`), no route, and costs strictly
over the cap are rejected. Equal cost is accepted. Already on a real depot
tile is the original cost-zero shortcut, but counts as actual in-depot
service only with zero speed and the stock in-depot state.

The returned table is an action to apply atomically, not a mutation:

- `none`: no special work.
- `service_here`: service an actually parked depot vehicle with the
  current engine reliability and current economy/calendar dates, via
  `Breakdowns.service`. Its old orders and breakdown timer are not replaced.
- `cancel`: the previous generated service target is gone or now too
  expensive; apply stock `Order::MakeDummy` (type = dummy, flags = 0).
  Preserve inactive order destination/refit fields, vehicle destination,
  path cache, and regular order-list cursor. Let the normal order loop
  resume the regular schedule; don't delete the list to cancel the detour.
- `keep`: a usable candidate exists but the current non-stop service
  detour normally stays in place. In this branch the source consumes
  exactly one global RNG draw from `hooks.random32`; only stock
  `Chance16(1,20)` allows changing it. A valid candidate and the
  existing `non_stop` intermediate bit are both required to draw.
- `route`: make the returned temporary service-only/non-stop depot order,
  suppress implicit order mutation, and set `dest_tile`. Invalidate the
  route cache only when `clear_cached_path` is true (the tile changed).
  Attach actual path/motion data and retain the saved regular schedule.
  On eventual physical arrival use the real depot service hook; planning
  a detour never repairs or refills reliability.

The service result only applies where the runtime can honor stock road
orders and provide actual YAPF/NPF reachability from the live pose. It does
not grant arbitrary nearest-depot lookup on an unsupported preview route,
and no RNG sequence beyond this callback is assumed to be identical.

## Verification

```sh
lua5.1 tests/road_depot_service.lua
PYTHONDONTWRITEBYTECODE=1 python tests/road_depot_service_upstream.py /path/to/OpenTTD-14.1 lua5.1
```

The deterministic map test uses the existing source-ported road YAPF
search, ignoring a nearer disconnected depot, selecting a real route of
cost 500, accepting the exact cap and canceling when it becomes 499.
The compiled differential matches 22,000 cases across all five actions.
It compiles pinned source for `NeedsServicing`, `NeedsAutorenewing`,
`NeedsAutomaticServicing`, persistent order detection, the depot-chain
predicate, the road service decision and order/depot destination mutation.
The map lookup, replacement rules and UI/finance are injected; these
fixtures verify the decision, not general road route execution.

The native graphical check buys an actual Foster and constructs two real
depots. It accelerates only the saved due date when the bus really
carries riders, lets the real controller choose from its actual frame,
reopens the temporary route, and proves the retained load is paid at
the unchanged original station. Use `BAYLINE_NATIVE_ROAD_SERVICE=1
BAYLINE_NATIVE_STOCK_FOSTER=1 BAYLINE_NATIVE_FRESH=1 tests/native.sh`.
