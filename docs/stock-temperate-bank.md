# Temperate Banks and Valuables

The Temperate Bank is OpenTTD 16.0-RC1 industry **12**, not the Gold or
Diamonds Bank used in other climates. The original Bank publishes
Valuables and accepts Valuables from *other* Banks. It does not convert
received bags into extra output. Stock output, acceptance, payment and
anti-self-delivery all share the ordinary worker's station and cargo
clocks.

## Building and operating

1. Open **Company → Fund Bank**. Choose the west tile of two neighboring
   house tiles shown in the build preview. The nearest town needs at
   least 1,200 people; an existing Bank cannot be in the same town or
   within 14 tiles. The town clears affected house footprints without
   lowering your company rating. The quoted cost is charged once.
2. Do the same in a second qualifying town. Add a Truck Stop near each
   Bank. Right-click it to confirm its Valuables catchment, queues and
   rating.
3. Buy whatever Armoured Truck is available on the stock calendar.
   Connect the depot and both stops to a two-way road; add the stops from
   the vehicle card and start service. Each Bank can supply its own
   bags and receive the other Bank's bags.

| Vehicle | Stock engine | Capacity |
| --- | ---: | ---: |
| Balogh Armoured Truck | 153 | 12 bags |
| Uhl Armoured Truck | 154 | 15 bags |
| Foster Armoured Truck | 155 | 16 bags |

All three have original editable [Blender assets](../art/stock_armoured_trucks.md).
The [Bank art](../art/stock_temperate_bank.md) is split into its two genuine
stock footprint tiles. Default new-game industry generation assigns this
Bank a zero initial generation weight; this port does not silently add
free Banks to normal starts. Random later Bank openings and other climates
are separate work. The current native bank mesh needs a common foundation
base; existing stock house tiles already meet that placement constraint.

Source: stock [industry rows](https://github.com/OpenTTD/OpenTTD/blob/16.0-RC1/src/table/build_industry.h),
[building checks and funding](https://github.com/OpenTTD/OpenTTD/blob/16.0-RC1/src/industry_cmd.cpp),
[shipment settlement](https://github.com/OpenTTD/OpenTTD/blob/16.0-RC1/src/economy.cpp),
and [engine rows](https://github.com/OpenTTD/OpenTTD/blob/16.0-RC1/src/table/engines.h).
