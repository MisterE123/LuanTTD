# Harbor Valley: existing saves

New games use the stock TerraGenesis port. Harbor Valley is no longer
a player-selectable start; these notes describe older saved worlds.

Harbor Valley is a fresh temperate, seed-1751 region. Its sea-level river
starts under the northern hills, narrows between Mason Quay and Eastport,
and opens into the southern harbor. The shoreline, inland wooded ridges
and flat transport terraces are actual shared corner terrain, not
decorative slopes imposed on a flat map. Existing maps are not rewritten.

The starter streets and house parcels around Port Alder and Mason Quay
remain intact. Their short passenger route has municipal access at both
ends and leaves the player to build the connection. Eastbank Coal and
Riverbend Power have ready inland footprints; Alder Timber Forest and
Tidewater Sawmill use a separate west freight corridor. There are no
player-owned stations, depots or track prebuilt by the geography layer.

## Where to build

Tile coordinates below are one-based map coordinates, not native player
positions. All placements require using the ordinary gameplay tools.

| Feature | Build location |
| --- | --- |
| Starter bus | Port Alder stop **(9,12)**, Mason Quay stop **(18,12)**; clear straight corridor between them |
| Timber or steel road bridge | West **(21,13)** to east **(27,13)**; grade 1 heads, deck grade 2 |
| Separate rail bridge | **(21,15)** to **(27,15)**; grade 1 heads, deck grade 2 |
| Rail starter | East-west track from **(28,14)** to **(37,14)**, depot at **(28,14)** opening east, platforms at **(31–32,14)** and **(36–37,14)** |
| Ship facilities | Dock slopes at **(5,32)** and **(8,32)**, two-tile east–west ship depot at **(12,34)** |
| Country Airfield | NW corners at **(7,12)**, **(18,20)** or **(30,16)**; choose before building pieces on that footprint |

The Coast Coal preset still chooses different industry footprints. The
dock sites are geometrically usable in Harbor Valley, but that does not
mean a dock there reaches one of the main map’s inland coal producers.
The separately authored farm, oil and dedicated coastal profiles retain
their own selection and cargo compatibility rules.

Run `lua5.1 tests/harbor_valley_seed.lua` for deterministic geography,
a sea-connection and slope continuity check, actual industry seeding,
bridge quotes and commits, a rail depot-to-station YAPF route, and native
airfield/dock placement quotes. This is a geography check, not a claim
about which workbench combination a given saved world has enabled.

## First coal delivery

Open **Roadworks (2) → Road Freight (5)**. Build road along
**(29,14) to (43,14)**, then add the south-side turnaround loops:

- Mine end: **(29,14) → (29,15) → (32,15) → (32,14)**.
- Power end: **(39,14) → (39,15) → (43,15) → (43,14)**.

Put a freight stop at **(31,14)** near Eastbank Coal Mine and a freight
stop at **(41,14)** in Riverbend Power Station's catchment. Inspect the
latter for **Accepts coal**. The depot at **(34,15)** connects from
the south. Buy a coal tipper and add the mine first and power station
second, using normal orders. The first delivery test paid $140 for
20 tons after the mine had time to supply the newly served stop.

A through stop is not a turnaround. If a vehicle gets to the stop but
shows **No path** when leaving, check that it can loop back in the
opposite direction. This road uses some of the same tiles as the
illustrative east–west rail corridor in the table; build them in
different places or test them in separate fresh worlds.

## Take the sawmill’s Goods by rail

On the normal Timber-enabled map, Railworks → Rail Operations (7) →
Rail Freight (5) includes **Sawmill Goods loading (4)** and **Town Goods
delivery (5)**. Mark owned platforms in the corresponding catchments;
the town end must say **Accepts Goods**. Inspect your rail depot, buy
the **Kirby + Goods Van**, then pick sawmill first and town second.
The van holds 25 crates. It and road Goods trucks draw on the same
sawmill output. Keep a road Wood service feeding that sawmill.

A tested railway has a north-opening depot at (17,20), a south-facing
path signal at (17,19), loading platform (17,16)–(17,18), track north
to (17,13), the RIGHT manual curve at (17,12), and a west–east platform
(13,12)–(15,12). The source-native freight test includes the track and
road connections for this route. See [Rail Goods port](../RAIL_GOODS_PORT.md).
