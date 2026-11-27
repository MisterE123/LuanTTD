# Stock Temperate ship fleet

All seven OpenTTD 16.0-RC1 Temperate ships have their own native model and a
working ordinary paid service:

- MPS and CS-Inc. oil tankers: use a dock near an oil source and another
  near a refinery. See [oil tankers](stock-oil-ships.md).
- MPS and FFP passenger ferries, plus the Bakewell 300 Hovercraft: buy the
  appropriate dated hull, then select two owned passenger docks. The
  hovercraft's stock 224 speed and capacity of 100 are not a ferry reskin.
- Yate and Bakewell cargo ships carry **Goods** as purchased, 160 and 190
  crates respectively. In a ship depot, buy the hull, open the vehicle,
  and pick a loading dock near a Factory, Sawmill or Oil Refinery and a
  delivery dock near enough town buildings that accept Goods. You can
  choose from the same compatible docks in the list or pick them in 3D.
  Choose **Start service** after reviewing both. For Coal, refit in the
  same depot before dispatch, then pick a mine dock and an accepting
  power plant. Both hulls retain their stock capacity when refitted.

The actual stock ship controller, regional pathfinding, depot and approach
tests, same-town queue production, preserved loading state and 8-bit
cash-fraction ledger all run on the campaign worker. The host renders one
original Blender-derived mesh at the authoritative pose. All seven are
dated in the ordinary market; there is no scenario feature checkbox.

Open the selected ship from the ordinary depot or company fleet to follow
it, modify orders, or start/stop it. Each of the passenger, oil and dry
freight groups has one owned vessel slot. Different groups use separate
physical berths. Multi-ship scheduling, offshore platforms, more freight
cargoes and other climates remain outside this slice.

## Join dock piers

A dock built next to exactly one dock station owned by your company will
join it, provided the full station still fits the stock 12-tile spread.
Use **Harbors → Join dock or build separately** for manual selection,
or hold the auxiliary key while using **Build dock**. The picker can join
a more distant dock if it fits the spread, or build at the same site as
a separate station. Other companies' docks are never included.

You can build directly on a legal inclined shore with trees. The quote
includes $20 per tree at base prices, and clearing one tile changes your
local rating once, not once per tree. Non-permissive councils refuse a
dock at a company rating of −200 or worse within their authority radius.

Joined piers are physical members of the same station: orders use one
station ID, eligible water tiles around every pier are considered for
routing, and catchment is calculated from all the shore ramps and piers.
The ordinary Bulldozer removes the selected ramp and its matching pier,
not every pier in the station. If a ship is loading at a berth that
ceases to serve the station, it finishes that visit and leaves once.
A ship at another valid berth keeps loading; the station ID and orders
do not change. The last pier and other harbor edits still have active
service protection.

After the last pier is removed, the station is temporarily unavailable
for orders or berthing. A new dock less than eight tiles away (Manhattan
distance) can automatically reuse that company's station ID and name.
The **Join dock or build separately** picker lets you reopen the station
explicitly or choose **Build a separate station**. An active adjacent
station takes priority on a normal build. Retired IDs expire on the
eighth staggered station check, every 250 game ticks. Restarting a
paused world preserves the opportunity to reopen a station.

This is the same-mode construction lifecycle from OpenTTD 16.0-RC1
`CmdBuildDock`, `RemoveDock`, `BuildStationPart`, and
`StationHandleBigTick`, with sign relocation from `Station::AddFacility`.
The inactive ID is visible in the construction picker, not as a world
sign. Joining across vehicle modes and removing a final pier while a
ship is using the harbor are not covered. Native QA removes the final
pier via the ordinary Bulldozer transaction, reopens the world, then
uses the worker operation behind the dock picker to reopen that ID at a
different shoreline tile and verifies fresh berths. The lifetime and
nearest-ID tests also match 7,096 compiled OpenTTD cases.

QA: both cargo boats used real worker-authorized purchase, Coal refit,
route and fare with the same stock mine and power plant after a partial
load restore. Separately, the 1950 Yate loaded real Goods from a refinery
supplied by a tanker. Its own stock hold and order list survived a packed
mid-load reopen and paid for each crate only once. The shared refinery,
farm/factory and timber chains keep their existing production and station
ledgers. An ordinary Linux client used the vehicle form and its in-world
two-dock picker, saw the original hull, and made further paid deliveries
after a separate SQLite restart. The Bakewell cargo ship and hovercraft
also ran as native Linux client projections and earned real fares. The exact source table check is
tests/ship_complete_temperate_roster_rc1.py. It checks the original cargo
class allowlist, all nine equivalent dry cargo holds, and their refit
prices against RC1. Only Goods and Coal are implemented for this hull in
ordinary play; the other seven choices are not exposed. See also the
[stock content inventory](stock-content-inventory.md).
