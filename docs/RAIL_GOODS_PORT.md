# Stock standard-rail Goods Van #32

Pinned OpenTTD 14.1 `table/engines.h` and `table/cargo_const.h`:

| Item | Stock value |
|---|---:|
| Engine ID / image index | 32 / 38 |
| Standard rail, body length | type 0, length 8 |
| Tare / full mass | 21 / 33 t |
| Goods capacity | 25 crates |
| Gradual pulse | 5 crates per body |
| Medium/no-inflation base price | 1,484 |
| Separate wagon running cost / power | None |
| Cargo ID / unit weight | 5 / 8 sixteenths of a tonne; freight-scaled |
| Cargo payment / first, second periods | 6144 / 5, 28 |
| Cargo age counter / regular rail active wait | 185 / 40 ticks |

Goods weight is multiplied by the stock freight setting before flooring
each wagon independently. An unmodified Kirby + van weighs 68 t empty,
80 t at capacity, and costs $12,421; at 3× freight, the van alone weighs
58 t full. The sealed van's stock image has no full-adder; the original
3D `bl_rail_goods_van.obj` and `bl_rail_goods_van.png` represent both
loads without an invented open cargo or visual substitution.

The ordinary full-load source and no-load accepting destination share
the existing Timber station economy. The Goods union joins actual
separately owned truck and rail catchments to the **same**
`timber_transactions` binding. Timber production still runs once per
stock tile and tick. An individual sawmill offer is allocated once among
eligible station ratings. A train's carrying tile and packet ages drive
the fare. The receiving scan uses the existing house acceptance and
canonical town receipt, so no duplicate payment or extra conversion
is possible. The live lane is opt-in and permits one purchased Kirby
and one Goods Van on one manually ordered two-platform route. It has
no effect on a prior Harbor build without the matching host opt-in.
Purchase and dispatch are conditional on the real Goods Van mesh and
atlas and the active stock Timber/road clock. Coal/Goods/Oil designation
is mutually exclusive per platform; paused or disabled support does not
manufacture or discard previously saved cargo.

The isolated rail freight test board admits, without alternate scenery or the timber
route crossing the rails:
- NW-facing depot (17,20). PBS at (17,19) facing SE provides the
  safe position on return to the sawmill platform.
- Goods loading platform (17,16) through (17,18), within the real
  sawmill's catchment.
- North leg X=17 up to Z=13, RIGHT rail at (17,12), and the horizontal
  leg on Z=12 through X=13..16. PBS at (17,15) faces NW and
  at (16,12) faces SW.
- Accepting platform (13,12) through (15,12), nine actual house eighths.
  This layout builds with the existing Forest → Sawmill wood truck path;
  it does not require the optional parallel town Goods road spur.

`tests/rail_goods_service.lua` uses an actual production clock, six
physical #144 haulage/scan receipts, the existing sawmill conversion
and genuine rail and road loading. It keeps competing allocation
accounted for throughout the reload, delivers 25 crates by rail for $184
and 14 by road for $143, issuing precisely 39 town credits.
`tests/rail_goods_harbor_layout.lua` proves construction and catchment on
the fresh 1751 board. `bash tests/rail_goods_live_native.sh` runs a real
owned depot purchase and safe signal route over two actual Luanti
processes with SQLite: 40 t of forest input moved by road, 25 crates
delivered in town for $142, full mass 80t, and $246 in actual train
running expenses. No scenery was injected or replaced. Set
`BAYLINE_NATIVE_GOODS_COMPETITION=true` for the shared road/rail
variant: 80 t of wood input and one Goods allocation, paying $131
for 25 crates by rail and $176 for 28 by road. This uses the same
native Timber chain and exact town/cash receipts. For its parallel
truck, build the Mill spur (12,14)–(12,15), the existing town
Goods stop (14,8) and close the truck turnaround at Z=11, north of
the railway: (15,8)–(15,11)–(12,11).
The pinned C++ consist differential now includes #32's original cost,
capacity, freight weights and loading time (7,500 cases; 226,080 rows).
The original cargo payment differential covers Goods across its complete
broad fare matrix (57,600 total cargo cases). The Oil rail station
adapter is still the same logical profile with unchanged save keys.


## Host mount

On a configured Timber campaign, set `S.rail_goods_service=true`,
retain `Sim.mount_paid_rail(S,Pilot)`, and after the dispatch view has
checked its real OBJ/atlas call
`Sim.mount_rail_goods(S, view.goods_wagon_ready)`. Pass
`Sim.rail_goods_validate, Sim.rail_goods_active` as the two final owned
rail factory arguments (after Oil). The renderer uses the actual #32
carrying body from the common rail pose. The owned interface quotes and
commits `{0,32}` and `start_goods(S,owner,id,sawmillPlatform,townPlatform)`.
The separate stage interface is
`Sim.rail_goods_stop_status(S,id)` /
`Sim.rail_goods_designate(S,owner,id,"load"|"unload")`. The raw platform
key is `goods_role`. Use `Sim.rail_goods_status` and
`Sim.rail_goods_loading_events` to present actual cargo and settlement.
