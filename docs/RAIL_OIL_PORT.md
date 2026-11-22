# Source-timed stock Oil Tanker rail-to-road adapter

One ordinary standard-gauge tanker wagon, OpenTTD 14.1 #30, on an
existing single coupled locomotive. This is a pure host integration and
fixture; neither native gameplay nor the renderer is enabled here.

* Source image index 36, length 8 (one engine plus tanker fits a
  16-unit tile), 24 t tare, 30 stock Oil units / 30,000 L capacity.
  Oil is freight. Each stock Oil unit adds 16/16 t before the configured
  freight_trains multiplier. A full wagon weighs 54 t with multiplier
  one, 114 t with multiplier three, and no weight is added for merely
  waiting at an empty platform.
* Five units per gradual round, 40 source ticks per active round and
  20 ticks for an empty/full-load probe. Use the existing stock train
  length/overhang timing, not the road tanker timer. Oil packets age
  every 185 ticks on the one stock clock. Fares are based on actual first
  wagon tile and actual unloading wagon tile, not the locomotive, the
  station sign or graphic location. No cargo transfer order, multiple
  tankers, alternate cargo, route purchase or release issue is claimed.

## Mount contract

Instantiate rail_oil_service.lua with Sim, the pinned Oil rules,
Catchment, rail roster, existing rail_coal_service (physical platform
and loading timing only), Packets, Rating, Station adapter, stock
loader and base timing. Existing Oil/Farm defaults are not mutated.
If the main rail roster already publishes #30, the adapter validates
and uses its matching exact data. Persist Service.new() together with
the existing OilRuntime ledger and train physical state.

1. B = Service.bind(s,state,ctx) accepts a local station role map
   (load or unload), actual road-station views, and a pipeline callback.
   The callback receives the one combined authentic road/rail station
   list and shared coverage. Return the existing OilRuntime binding
   against those actual aliases. B.pipeline is that same binding for
   host landscape and industry ticks; this module never starts a
   second source producer or rating timer.
2. Allocate once per real well offer. Any road/rail competitor uses the
   same source CargoID 3 owner-best distribution, station rating and
   residue. The road Goods outlet is the existing physical truck
   station and canonical Goods handler, not a mirrored refinery stock.
   B.report(local_id) includes accepts, role, available/reserved/waiting.
   B.refresh(local_id) updates the saved station acceptance at the
   host's normal station big tick; the adapter does not age ratings
   independently. A combined *single* StationID mixing truck and rail
   facilities has not been mounted; the fixture uses distinct IDs in
   the same refinery catchment.
3. Register the actual tanker actor with B.vehicle({wagon=30,...}).
   Call B.loading_tick(tick,stopped) in the common station pass;
   B.arrive(local_station,visit,tick,actual_head_tile,actual_wagon_tile)
   at the verified physical platform stop. B.leave(visit,tick) accepts
   only the current ready train. B.after_motion(tick) ages once after the
   common movement phase, including reservations. Changed/missing
   platform faults preserve cargo and reservations.
4. The stock loader's actual oil unload stages in the shared oil
   ledger; the whole rail station scan ends before refinery treatment.
   The optional post_scan callback observes genuine receipts (no extra
   pay). All final rail fare is paid only by stock CargoPayment
   settlement; Goods pickup and final delivery use the existing road
   handler, and don't pay the earlier tanker a second time.

## Tests

tests/rail_oil_service_upstream.py authenticates original engine/cargo
table rows and returns 5,000 compiled mass/overhang comparisons.
tests/rail_oil_service.lua uses real adjacent train/wagon platform tiles,
one stock well/refinery clock, one genuine road Goods loading body,
and single mixed rail/truck Oil offer (4+4 instead of 8 twice).
After restarts during loading and unloading, exactly six 5-unit
physical oil scan rounds reach the refinery, 40 ticks apart. The train
earns $270 once for 30,000 L; the road Goods vehicle earns $165 once for
14 of the 30 crates, leaving sixteen true Goods units. A destroyed
platform test preserves the physical five-unit cargo and refuses further
loading. Route travel phases are isolated test inputs, not a native
movement/campaign proof, and the fixture does not place the new art.

## Live shared clock

`rail_oil_runtime.lua` mounts the #30 oil order on the existing paid
rail dispatcher when `s.rail_oil_service`, purchased rail, stock road
loading, stock houses and the road Oil chain are active; the flag is not
a default. An owned idle physical platform may be marked `oil_role`
`load` or `unload` only if stock catchment permits it. Active passenger
routes, pilot use and same-platform Coal designations are rejected.
This role retains the physical platform; it does not build or alter it.

The Oil road binding opens its original `stock_oil_transactions`
once for both distinct road and designated rail StationIDs. They compete
for the same physical well offers; train unload goes through the exact
same refinery scan/receipt observer as road. This preserves one versioned
production cursor and one Goods queue, rather than a railroad-specific
processor. Rail port activity/rating is processed from the same 74-tick
day as the trucks, before producer ticks. A disabled preview pauses
the rail cargo/reservations and reconciles its local cursor on resume,
while existing road Goods continues. A lost platform or closed source or
refinery holds the train and its saved cargo without paying or deleting
cargo. Closing an industry is not a fake push of its last cargo into a
station. Train running costs are computed on preceding actual usage and
settled against the company’s fractional stock ledger.

Host API: `Sim.rail_oil_active/validate/designate/stop_status/status` and
`Sim.rail_oil_loading_events` alongside the common paid rail motion and
pose methods. Oil orders retain the dispatcher's existing `mine/power`
endpoint keys for loading/unloading. `tests/rail_oil_runtime.lua` exercises
actual Sim days, a real moving road Goods truck and correct platform
cargo tiles with deterministic substituted rail motion callbacks: 30,000L
for $210 in six stock pulses, followed by 14 Goods for $103, with partial
cargo pause/reload and refinery-close fault. This is distinct from the
full real rail movement and native SQLite tests.
