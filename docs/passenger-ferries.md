# Purchased passenger ferries

Build two docks on a navigable waterway near houses, and a ship depot.
Inspect the depot, open **Passenger ferries**, buy an offered model,
choose its orders, pick both docks and select **Dispatch**. The depot
also shows fares and operating costs and can stop or resume the ferry.
A Yate coal ship has a separate depot page; use a separate depot and
separate dock berths for a concurrent Yate service.

| Model | Seats | Raw maximum speed | Default purchase |
| --- | ---: | ---: | ---: |
| MPS Passenger Ferry (206) | 100 | 64 | $24,375 |
| FFP Passenger Ferry (207) | 130 | 128 | $28,437 |

The roster uses OpenTTD 16.0-RC1
[`src/table/engines.h`](https://github.com/OpenTTD/OpenTTD/blob/16.0-RC1/src/table/engines.h),
MS entries 206–207 and SVI rows 2–3. Dates, raw speed,
acceleration, capacities and cost factors are stock. Purchase price
uses the stock BuildShip price base. Running expense is settled from
active ticks and the company's fractional balance; stopped ticks don't
incur a charge. The source's array sprite index is shared between the
two stock ferries, not between the distinct LuanTTD vessels.

The 130-seat FFP has its own original low, enclosed aluminum saloon,
ten-frame V hull, swept wheelhouse, separate propeller shafts and
waterline. No stock sprites or colors were sampled. Edit
[`ffp_passenger_ferry.blend`](../art/ffp_passenger_ferry.blend) or
regenerate with `blender -b -t 2 --python tools/build_ffp_ferry_art.py`.
Both original boats use the existing native ferry palette.

Try a **1950** world for the MPS and **1980** for the FFP. The fixture
verifies source capacity, paid cargo, running cost, SQLite reload and
actual Yate/road coexistence. The current interface supports one
purchased passenger ferry per world. It does not yet offer ship sales,
ship-to-ship collision, cruise line fleets, or model-specific faults.
