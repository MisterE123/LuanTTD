# Pinned temperate Forest → Sawmill → Town Goods

Independent OpenTTD 14.1 simulation slice; no world, controls, vehicle or
renderer is wired here. `openttd/timber_industry.lua` uses the existing
packet, fixed-point rating/competition, income and catchment ports;
`openttd/town_goods.lua` contains all 110 original HouseID goods values.
NewGRFs, placing/funding industries and dynamically scheduling original
economy random-industry choices are outside this adapter.

## Exact source behavior

- Forest type 3, two layouts (18/23 tiles). Nominal wood production is
  13 t every 256 stock ticks. A completed physical landscape visit
  offers at most 255 t and only if the lot exceeds 30. Recession shrinks
  the offered amount after the full lot has left industry stock. Forest
  gfx16 changes to gfx17 only when cargo was moved; its next visit resets
  the chopping graphic. Real completed tiles may distribute while other
  tiles are still under construction.
- Sawmill type 2, two actual 8-tile layouts. Only gfx13 adds 8 units of
  Wood acceptance. A station can have a nearby sawmill by covering any
  occupied tile, but that does not make it accept Wood. Source order
  among nearby accepting industries uses minimum Chebyshev distance
  from station sign, then IndustryID. Source-industry self-delivery,
  refused or exclusive-supplier mismatch do not accept input.
- The sawmill has zero autonomous goods output. Station delivery first
  accumulates its unsigned-16-bit input buffer; after the **whole one
  station's loading scan**, it consumes all input exactly once and
  converts at the source 256/256 multiplier. The output buffer saturates
  at 65,535; discarded overflow is not output and should not reappear.
  Goods cannot be offered in that just-ended tick's landscape phase.
  A future completed sawmill tile visit offers only when waiting >5,
  with the same 255-unit cap.
- Town goods acceptance counts stock HouseID contributions in eighths,
  independent of construction stage, summing each in-catchment actual
  house tile only once. At least 8 activates the acceptance flag.
  House acceptance supplies the always-accepted bit for Goods; a bus-only
  facility does not activate its goods order. A paid town delivery credits
  the receiving station's associated town, not an arbitrary accepting
  house or the visually closest house. Goods cargo #5 uses payment
  base 6144 and thresholds 5/28; Wood #7 uses 5005 and 15/255.
- Purchase data is exposed, no vehicles are spawned: stock Balogh Goods
  Truck #138 has 14 crates, Witcombe Wood Truck #144 has 20 t, both
  have 5-unit gradual pulses and one cargo aging period per 185 ticks.
  These are their default unrefitted capacities.
- Organic forest production changes use source original/smooth paths
  and economic month history. The processing sawmill can announce
  abandonment after 5 economy years without output distribution, under
  the selected stock RNG chance and closure controls. A marked closure
  is physically removed the next month. Creation seeds and industry RNG
  are supplied by the host instead of inventing a second clock.

## Live adapter contract

1. Instantiate `Timber(Packets,Catchment,Rating,Income,CoalCommons,TownGoods)`
   and `TimberRuntime(Timber,Catchment)`. Existing coal helper provides
   exact chance/scale, not parallel commodity production. Save each
   industry record plus `TimberRuntime.new()` ledger. Bind with
   `B=TimberRuntime.bind(s,ledger,ctx)`; keep closures outside the save.
2. Fill `ctx.industries` with Timber's actual native seeded industry
   records, unique global IDs. Fill `ctx.stations` with canonical views
   (ordered numeric ID, owner, town, native sign tile, zero-based sign
   x/z and physical mode-tagged footprint), and alias the *same* saved
   `st.goods` and `st.stock` records already read by vehicle loads. If
   legacy stocks share these cargo labels, pass separate packet queues
   and ratings so prototype quantities cannot count. `ctx.xy` maps
   native tile IDs to coordinates for actual carriage/truck income;
   `ctx.house_at(x,z)` reads the real source HouseID for a covered tile.
3. In the **existing** world's landscape visitor, call
   `B.tile_visit(x,z,tick)` on marked timber footprint cells only.
   It returns physical lot and actual transported units. Do not drive
   `H.advance` for timber separately. The station list is deduplicated
   by canonical ID and follows source company-best allocation with
   distinct per-cargo fractions. New packets defer their first actual
   pickup tile, as in stock. Use standard Packets.pickup/drop/split
   from the existing loading controller, not category buys/sales.
4. `B.report(id,cargo)` supplies actual acceptance and nearby IDs.
   Native use can pass `ctx.acceptance(st,cargo,tick)` to read the
   saved station's acceptance flags refreshed at construction and
   the stock 250-tick station phase (the pure default report is
   immediately computed). Use `Timber.goods/queue` to update normal
   two cargo ratings after station/vehicle ticks, once in the same
   station small clock; no duplicate per-mode or per-cargo counter.
5. Route staged actual final-unload packets to
   `B.stage(station_id,tick,token,packet,actual_carrier_tile)` and
   return its eligible profit into the **existing** cargo payment
   transaction, never directly debit/credit twice. Token must be the
   stable vehicle/order-visit/loading-round/packet-ordinal from the
   actual loading scan. An exact replay returns nil and a reason, not
   a second payable result. Other station scans cannot overtake saved
   pending input. Transfer orders use the common loader's actual
   transfer path and are not sent as new wood to the mill.
6. Call `B.finish(station_id,tick)` **once after all actual deliveries**
   at that station, before the next station's scan. Returns distinct
   conversion and settlement receipts once, including accepted units
   and town ID. Apply town Goods receipts and company statistics from
   those actual units via the authoritative station/vehicle code.
   A stage never inserts goods into a station or another vehicle.
7. After vehicle and station ticks, call `B.produce(industry_id,tick)`
   in the globally sorted world industry phase, preserving shared RNG
   ordering with coal. `B.month(industry_id,month_ordinal,year,opts)`
   runs at the existing economy month transition. Use source actual
   random-industry callback for the original economy's nonmonthly
   `Timber.change`; smooth and frozen settings are supported here.

The adapter prevents duplicate per-tile landscape batches, stale/open
station scan replay, duplicate unload tokens, and duplicate monthly or
industry ticks. Resume a saved pending station scan before advancing
the world clock. Outer loader mutation and save must remain within the
same authoritative engine transaction; this is not a second freight
transport/running-expense implementation.

## Verified

- `lua tests/timber_industry.lua`: a shared source landscape clock
  produces 39 t wood from 3 cadence pulses. Two actual carried packet
  slices consume exactly 20 t once across a saved/reloaded open station
  scan; 20 crates are offered only on a later landscape visit, and
  14 crates pay $102 at the actual marked town delivery. Resize/cap,
  receipt replay, selective/owner-best competition, threshold and
  closure paths are covered.
- `python3 tests/timber_industry_upstream.py SOURCE --lua lua5.1`:
  checks exact source data, all four footprints, all 110 HouseID supply
  acceptance rows, both original truck bodies, and compares 6,000
  compiled 14.1 output, conversion and shipping rounds.
