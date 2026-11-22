# Temperate farm, factory and original cargo chain

Source pin: OpenTTD 14.1. This slice contains the real industry rules and
a replay-safe host adapter, **not** an enabled campaign option. No
production, vehicle, UI or renderer behavior changes on existing worlds.

* Farm IndustryType 9: three original layouts (9, 12, 12 physical
  tiles, gfx 33–38). Output order is Grain then Livestock. Each has an
  independent production rate 10 per 256 world ticks before cargo scale,
  16-bit waiting, 16-bit current/last history, pickup rating/fraction
  and selective collection through the original transport loop.
* Factory IndustryType 6: two original 12-tile footprints, gfx 39–42.
  Input order is Livestock, Grain, Steel. Each has a multiplier of
  256/256 into one Goods stockpile, not a complementary recipe.
  Periodic Goods rate is zero. Every original factory tile supplies
  eight acceptance eighths for each input. Steel is a valid input
  but this slice does not produce steel at the farm.
* After the entire station unload scan, the processor consumes each
  accepted input, clamps shared output to 65535 and clears input
  stock. Manufacturing doesn't pay. A later completed landscape tile
  offers Goods. Each output independently requires >5 and releases at
  most 255 units. Recession halves the drained lot with rounding up.
  Final Goods acceptance and receipts reuse the original HouseIDs and
  the station town; factories do not accept their own Goods.
* Cargo IDs/base freight rates and aging curves: Livestock 4 (4322;
  4/18 periods), Goods 5 (6144; 5/28), Grain 6 (4778; 4/40), Steel 9
  (5688; 7/255). Stock bodies #135 Talbott Livestock Van 14 animals,
  #141 Hereford Grain Truck 20t, #138 Balogh Goods Truck 14 crates,
  and later optional #150 Balogh Steel Truck 15t. Stock five units per
  gradual pulse, 185 aging ticks for all four. Keep the actual pickup
  and unloading tile for fare distance, not the station label.
* Original random changes use first output Grain's monthly transport
  ratio and change both Farm rates together with source rounding and
  levels 4–128. Smooth economy draws separately for each valid crop.
  Factory abandonment respects five years, original/smooth RNG
  probabilities, frozen economy, override flags and last-of-type
  protection, with removal on the next stock monthly pass.
* Farm field planting attempts 50 times on build and has a 1-in-8
  chance every 256-tick production pulse. It uses shared RNG, source
  suitability/clipping, 4–7 tile bounds, nine variants and original
  fence rules. Farmhouse gfx 33 and 34 contribute one Passenger
  acceptance eighth each; a lone farm accepts no whole passenger
  unit. Clear-ground field aging/fallow and 3D field visuals
  are separate from this source planting slice.

## Host integration

Instantiate openttd/farm_factory_industry.lua with existing Packets,
Catchment, Rating, Income, Coal commons and Timber (the same exact
town Goods acceptance/delivery). Pass rules, openttd/farm_factory_fields.lua,
the existing timber_industry_runtime.lua staged protocol and Catchment to
farm_factory_runtime.lua. Persist Runtime.new(), source industry records
and actual shared queues; never serialize the binding. Produced/accepted
arrays each have 16 ordered source slots, matching source identity and
initial smooth RNG draws.

B.tile_visit(x,z,tick) consumes physical landscape visits.
B.produce(id,tick) is one call per stock global IndustryID, after vehicle
ticks. B.month(id,ordinal,year,opts) keeps unique monthly transitions.
For an original daily selected industry pass Rules.change() its
actual factory/farm and stock selection. A binding with shared RNG
requires real field_board callbacks or the equivalent field_attempt.
B.plant_on_built() follows committing the literal farm footprint;
field count does not increase production rates.

Use B.report(station,cargo) for geographic acceptance. Reuse the same
canonical Goods queue for factory and sawmill production and settle
Goods once through the same cargo payment path. Stage receipt with
B.stage(station,tick,actual_vehicle_visit_pulse_packet_key,packet,
actual_cargo_tile). B.finish(station,tick) is after every real vehicle's
unload pulse for that station, with no intermediate manufacturing or
duplicate accounting. On reload a duplicate returns no payable amount.

## Proof

* tests/farm_factory_upstream.py: five true layouts and 10 tile classes;
  authentic source rates/cargo/stock truck rows; 8,000 compiled
  production, dispatch/recession and conversion cases; 6,000 compiled
  original/smooth change cases with all RNG draws checked.
* tests/farm_factory_fields_upstream.py: 500 compiled planting scenarios
  compare the exact tiles, all fence sides, and RNG draws including
  normal and freeform boundaries.
* tests/farm_factory_ledger.lua and tests/farm_factory_ledger_native.sh:
  real landscape cursor, actual packet tiles and a mixed station scan.
  Two native Luanti processes persist a partial scan in SQLite and
  settle 5 grain for $43, 5 livestock for $38, and exactly one converted
  shipment of 10 crates to the town for $104, with no duplicate output
  or payments. This is a native ledger fixture, not an end-to-end
  player truck drive or graphical port. Assets and active campaign
  placement remain separate work.
