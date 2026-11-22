# Ordinary stock coal transport by rail (source adapter and native preview)

OpenTTD 14.1 stock coal wagon #29 carries 30 t alone behind a
non-cargo locomotive, is 8/16 of a map tile long, and moves at most
5 t per gradual load/unload pulse. The train waits 40 ticks after an
active gradual round, 20 for an empty retry, and uses the cargo-unit
count for non-gradual active rounds. Stock platform overhang applies to
both active and idle delays. One physical wagon ages its committed and
reserved packets every 185 stock ticks. The locomotive's max speed
cache supplies rail rating without halving; the current calendar year
minus build year supplies the clamped last-age field.
 
The module uses the pinned commodity, stock packet travel, loader,
catchment and Coal Industries modules. Train *front* position identifies
the live continuous platform length. The *carrying wagon* identifies the
first pickup tile, transfer point and final distance/payment tile. Rail
goods acceptance uses the actual 4-tile catchment around each valid
owned platform tile, not the sign, depot or rectangular outline. Truck
stops keep radius 3 by default. Delivery is paid only on plant-accepted
tons and after the existing cargo payment settles, not when the
landscape generates coal or when the train arrives.

## Native wiring contract

- Instantiate `Rail=Factory(Sim,Coal,Catchment,Roster,Packets,Rating,Station,
  Income,LoadingFactory,Timing)`. Keep `Rail.new()` as the serialized
  cargo state; `Rail.bind(s,state,ctx)` produces an ephemeral world
  adapter. Station local IDs are normalized to 0x4000+ID, consistent
  with paid rail passenger stations; current road IDs remain unchanged.
- Extend **the existing road coal binding's** candidate arrays immediately
  after the one road view/coverage loop with
  `bound_rail.extend(station_list,coverage)`. Only the road stops should
  be walked by the existing road timer loop; use a dedicated road subset
  or filter by road station/descriptor, because the mixed list also holds
  real rail station IDs. In that existing binding's `tile_visit`, select
  `Rail.distribute` instead of `Coal.distribute` when rail is mounted.
  Invoke it exactly once per visited producer with the combined candidate
  list. Do not run a second rail coal producer or a second industry tick
  on the train side. The pure rail binding never generates coal on its own.
- This shared distributor writes straight into both saved station queues.
  It preserves the source fixed-point competition/order and explicitly
  defers the first pickup tile for *new* packets. Stop-sign origins in
  historical single-tile road coal saves are retained; arbitrary station
  signs are not stamped on new rail packets.
- Register one real purchased wagon through
  `bound_rail.vehicle({id,owner,stock_id=29,length=16,speed,built})`.
  `length` is combined locomotive+wagon cached length, `speed` is the
  exact stock cached maximum, and `built` is the actual locomotive's
  purchase/build year, not the current year. No free wagon, proxy actor
  or reset per leg is needed. Update stopped/broken/crashed flags from
  the authoritative locomotive controller.
- After **the existing** landscape pass collect `bound_rail.loading_tick(tick)`
  ready IDs beside the existing station loading scan, before committing
  vehicle movement. When the dispatch controller truly halts at a
  scheduled station call `bound_rail.arrive(vid,local_station,visit,tick,
  actual_head_tile,actual_wagon_tile,order)`; accept one real visit and
  treat duplicate replay idempotently. `order` supports ordinary
  `full`, `no_load`, `no_unload`, `force_unload` and transfer flags.
  When the existing train genuinely leaves its station during the same
  ready tick call `bound_rail.leave(vid,visit,tick)`. Hold the dispatch
  dwell until then; do not retain a hard-coded 74-tick pilot dwell.
- Call `bound_rail.after_motion(tick)` after the actual stock movement
  and before the shared industry's production callback. This applies
  wagon aging and rail station counters/ratings. Use `ctx.rating_due`
  if that exact physical station already clocks passenger/mail: call
  after the shared station phase, not a second counter increment. The
  250-tick stock big phase refreshes acceptance. `bound_rail.withdraw`
  returns genuine reservations and settles prior accepted deliveries before
  deleting the selected service. Do not delete the station first.
- Presentation: `bound_rail.report(local_id).sources/.near/.accepts`,
  `bound_rail.waiting(local_id)` (including reservations, then available),
  and `ctx.emit(event)` for actual arrivals, board, transfer, deliver,
  fare and leave. `ctx.received(s,industry,tons)` uses the real existing
  power station accounting. Art orientation or mirroring is not a
  condition of mine/plant service.

The independent adapter does not implement track plans, multi-wagon/refit/cargo routing,
cargo orders UI, train art, or native movement. It is safe to include only
as an unmounted source module until authoritative dispatcher, station and
industry clock hooks plus native playtest are in place.

## Tests

- `lua tests/rail_coal_service.lua` uses actual seed 1751 site footprints,
  road truck catchment at (31,14), source rail platform (30..32,15) and
  sink rail platform (39..41,16). A real landscape+industry clock offers
  each batch once. Competing truck and wagon queues both receive coal.
  The wagon loads 30 t, spends nine aging periods in transit, unloads
  partial acceptance at a nearly saturated plant (27 t paid), and its
  actual pickup/delivery sites yield distance 8 rather than sign
  distance 10. Reload mid-reservation and mid-unloading; no duplicate
  aging, acceptance or payment.
- `python3 tests/rail_coal_service_upstream.py SOURCE --lua lua5.1` checks
  pinned source engine/coal and paired carrier/front rules; compiles
  4,000 source loading delay comparisons including ordinary, overhang,
  no-load self-retry and lost-acceptance retry.

## Mounted preview

Enable `bayline_rail_owned_preview=true` and
`bayline_rail_coal_preview=true` on a fresh seed 1751 scenario. Stock native
corner, road and house clocks are required. The road-truck preview can be
enabled independently; when both workbenches are enabled coal candidates
from both compete in the same industry event and receipt ledger. Saved coal
clocks/packets are retained when this optional rail service is paused in
settings. This does not add coal wagons to the passenger shuttle.

- `Sim.rail_coal_designate(s,owner,id,"load"|"unload")` explicitly marks
  an unused owned platform, verified against the true mine/plant footprint.
  It does not replace the platform or silently recolor a passenger service.
  The saved `stock_rail_stations[id].coal_role` selects its freight art.
- `Sim.rail_coal_stop_status(s,id)` reports .role, .sources, .near, .accepts,
  .waiting and .available. Unmarked platforms report potential
  geographically useful roles, with no active rail coal queue.
- `api.rail_owned.start_coal(s,owner,unit,mine,power)` validates both roles
  and preflights the actual depot, loaded outbound and empty return paths.
  It uses only the purchased Kirby 0 + coal wagon 29. New orders repeat
  stock full-load at the mine and no-load at the accepting power plant.
  Actual stopped locomotives and wagons take the pinned stock station
  reversal as required; they never respawn or jump to a platform. A save
  from the earlier one-delivery pilot has no repeat marker and retains
  its original stopping behavior.
- `api.rail_dispatch_controller.park_coal(s,owner,unit,true|false)`
  schedules or cancels parking after the next settled power order;
  select before finishing the delivery. Parked trains hold real platform
  claims and no longer accrue front-engine running ticks. A disconnected
  line or permanently lost industry destination blocks at the last
  committed position; loaded/reserved coal remains accounted for, and a
  route failure does not invent a fare. A slow but live mine still uses
  true full-load waiting.
- `Sim.rail_coal_status` reports actual onboard tons, delivery, paid route
  profit, exact stop and cargo tiles, and fraction-accounted locomotive
  running expense from real active ticks, plus repeat marker, completed
  order cycle count, pending park and route failure. The display uses the common
  `Sim.rail_paid_pose`, and coal effects are read separately with
  `Sim.rail_coal_loading_events` (not passenger ticker messages).
- Native two-process regression:
  `BAYLINE_NATIVE_TOOLS=/path/to/bin-root bash tests/rail_coal_live_native.sh`
  purchases and orders both stock vehicles on actual unchanged flat seed
  1751 land. Track X (30,15)..(43,15), mine platform X (30,15)..(32,15),
  power X (39,15)..(41,15), two-way PBS facing east at (42,15), depot
  facing west at (44,15). Truck uses (31,14)..(41,14) and depot (33,13).
  It saves during the wagon's real loading and reopens the native world:
  30 t rail/$232, 40 t road/$280, $120 actual rail running expense,
  and 70 t in the one power station receipt ledger. This legacy migration
  variant retains its historical one-delivery order and parked train.
- `BAYLINE_NATIVE_TOOLS=/path/to/bin-root bash tests/rail_coal_repeat_native.sh`
  uses two separate native two-process SQLite saves on the same unaltered
  terrain. The main case restores a half-loaded wagon in the second mine
  stop after paying $232 for the first haul; it independently pays $234
  for the next, for 60 t rail and $466 overall. The competing truck
  delivers 60 t/$420 through the same mine and plant. At both mine
  arrivals the train is physically westbound (td 0, both parts at (30,15));
  at both power arrivals it is eastbound (td 8, both at (41,15)). The
  third reversal and asked-for parking retain actual rail claims, and
  freight charges total $182 before parking. The fault case closes the
  real power plant after restart mid-second mine load and verifies no
  further movement, payment, lost reservations or running charges.
  UI/graphical testing is separate.
