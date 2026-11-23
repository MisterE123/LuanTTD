# OpenTTD 14.1 temperate land oil chain

The ordinary generated temperate campaign now includes land Oil Wells,
Oil Refineries, Witcombe Oil Tankers and Rail Oil alongside farm, timber
and coal freight. Oil converts at the refinery into the same Goods cargo
used by the other industries. The dedicated Oil scenario is still a
fixed-layout test world, not a prerequisite. Offshore rigs, oil-ship
refits and player funding/prospecting are not part of this port.

## Exact source records and graphics handoff

* Oil Wells are IndustryType 11. Layout 0 is the actual five-cell
  L: (0,0),(1,0),(2,0),(0,1),(0,2), all completed idle gfx 29; layout
  1 has (0,0),(1,0),(1,1),(2,2),(2,3). Gfx 30–32 are the same site
  and same pump during a three-sprite cycle. No tile there accepts
  cargo. Base 12 units Oil per 256 stock ticks, original
  worldgeneration history 96, pay Oil as actual stock cargo ID 3.
* Refinery is IndustryType 4. Layout 0 actually occupies 15 cells:

  | Z offset | X=0 | X=1 | X=2 | X=3 |
  |---|---:|---:|---:|---:|
  | 0 | 20 | 20 | 23 | empty |
  | 1 | 21 | 19 | 18 | 23 |
  | 2 | 22 | 22 | 18 | 18 |
  | 3 | 21 | 20 | 18 | 18 |

  Only gfx 20 can accept crude (8 eighths, three actual sites).
  Gfx 23 accepts one eighth of Passenger only; all other refinery
  graphics accept nothing. Use direct visible loading frontage west
  of (0,0) or south of (1,3). There are zero periodic Goods; an
  actual station scan stages received input, 256/256 one-for-one
  conversion at the end of that scan into uint16-capped Goods,
  and later visits to any completed physical refinery tile can offer
  output. Conversion does not pay. Final Goods acceptance is based
  on true HouseIDs with existing town and cargo accounting.

Mesh site offsets are per occupied local (X,Z), not generic gfx ID.
Suggested mount asset names bl_industry_oil_well_X_Z.obj and
bl_industry_oil_refinery_X_Z.obj, anchored at north-west node with
grade+1, leaving all source holes untouched. Artwork can render
completed idle pumps or source frame-driven original animation.
O.animate(tile,tick,random) runs only each eighth absolute tick;
all active frames draw even when not yet at the stopping boundary.
On the complete twelve-animation-frame cycle the source stops
with probability 1/7. Idle physical landscape visits start with
probability 1/6; the optional animated callback tells the host to
register the new active pump in its actual animation list. Do not
fabricate oil from an animation transition.

The first stock road tanker is global EngineID 132, table index 16,
Witcombe Oil Tanker, image 3, 21 stock units of 1,000 L, base buy
factor 110, running factor 90, source max speed 96 (48 km/h),
5-unit stock gradual pulse and 185-tick cargo age. Oil has base
payment 4437 and 25/255 cargo travel-age parameters. Goods may
reuse the true Balogh #138 (14 crates); no legacy prototype cargo.

## Siting and longer lifecycle

Normal wells and refinery are land industries. Occupied gfx 18–23
and 29–32 have SLOPE_STEEP in the source refused mask, which
rejects every nonflat tile. Separate optional TerraGenesis industry
leveling is not included in these pure rules.

O.refinery_edge(x,z,width,height,opts) checks zero-based origin +
(1,1) strictly inside the default edge limit 32; above size 256
each axis scales by its own floor(size/256). North/west void
edges use the actual freeform option. This is an edge distance
check, **not** a water adjacency or dock requirement. Industry
editor bypasses the edge condition. O.conflicts reports the
source's directional conflicts at Chebyshev distance <=14: a
new Well names Refineries, a new Refinery names Rigs. Authored
pair planning should leave at least 15 tiles between origin
anchors rather than relying on source placement order.

The well's temperate map-generation relative appearance weight is
4, while normal random play weight is 0, plus the >1950 filter
in the random play path. Map generation and separate user
construction/prospecting are not that random play path. No new
periodic oil source is invented when wells are exhausted. Original
economy each selected well declines unconditionally 12→6→3 then
closes (zero lottery draws). Each smooth month permits only a
downward change toward minimum, and last-of-kind protection does
not apply to temperate wells. A refinery with five idle economy
years uses the stock random closure branch and ordinary
last-instance protection. Production history rolls over before
monthly processing/removal, as in source.

## Station and proof boundaries

oil_industry.lua instantiates a **private** copy of the existing
fixed-slot industry/cargo helper then defines only oil tables and
special rules. It never modifies installed Farm/Sawmill rules.
oil_industry_runtime.lua wraps the same replay-safe station protocol:
one shared physical tile_visit, true global IndustryID production,
actual stage/finish in the existing whole-station load scan.
The very same physical through truck station can accept Oil and
send Goods, using independent CargoID queues and one canonical
Goods handler; do not add a second mirrored Goods station or credit
an incoming tanker indirectly when processed cargo is sold.

tests/oil_industry_upstream.py checks all 4 source footprints, real
table cargo/depot rows, acceptance/refusal roles, and 18,000 compiled
source comparisons across production/conversion, original/smooth
change, edge offsets and pump states/draw counts. The isolated
tests/oil_industry_ledger.lua service releases authentic well
production, uses actual pickup/delivery map tiles and source age,
and settles 21 oil units for $189 and 14 of their 21 Goods crates
for $146. The two-process SQLite harness replays only the unpaid
rest of an actual staged packet, leaves seven legitimate crates
waiting and tests no duplicate processing/settlement. It is a
ledger proof, not a live drive, authentic graphics QA, or new
campaign availability.


## Ordinary generated campaign verification

The placement catalog and location checks were rechecked against
[OpenTTD 16.0-RC1's stock industry table](https://github.com/OpenTTD/OpenTTD/blob/16.0-RC1/src/table/build_industry.h)
and [industry commands](https://github.com/OpenTTD/OpenTTD/blob/16.0-RC1/src/industry_cmd.cpp).
The refinery uses the perimeter-scaled generation weight; the wells use
the area-scaled weight. Their stock directional conflicts and the
refinery's strictly scaled map-edge limit apply. The native host mounts
the stock layout 0 art for each and keeps the upstream-recorded town,
footprint holes, tile random bits, construction stage and production
history. It still declines unsupported art layouts or sites that would
need the unported TerraGenesis industry-platform leveling pass.

In the default generated seed 1751, the refinery appears at (26,30)
and the oil wells at (48,35). Build on the stock landscape; try a truck
stop near the wells at (47,35), a refinery stop at (25,31), and a
town stop at (16,17). Check **Accepts Oil** at the refinery and
**Accepts Goods** at the town before dispatch. A company depot needs
actual through connections and room for the trucks to turn.

`bash tests/generated_oil_freight_native.sh` is a two-launch SQLite
proof on the standard generated world (no oil scenario or enable setting).
A purchased tanker delivered 42,000 L for $588 and a Goods truck
delivered 13 crates for $221 after restart.
