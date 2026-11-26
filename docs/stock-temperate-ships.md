# Stock Temperate ship fleet

All seven OpenTTD 16.0-RC1 Temperate ships have their own native model and a
working ordinary paid service:

- MPS and CS-Inc. oil tankers: use a dock near an oil source and another
  near a refinery. See [oil tankers](stock-oil-ships.md).
- MPS and FFP passenger ferries, plus the Bakewell 300 Hovercraft: buy the
  appropriate dated hull, then select two owned passenger docks. The
  hovercraft's stock 224 speed and capacity of 100 are not a ferry reskin.
- Yate and Bakewell cargo ships: buy a hull, select its **Coal** refit in
  the same depot, then pick a dock near a mine and an accepting power
  plant. The two carry 160 and 190 tonnes respectively. Their ordinary
  Goods cargo and the remaining stock refit choices are not yet serviced.

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
service protection. Full station retirement and joining across vehicle
modes are separate.

QA: both cargo boats used real worker-authorized purchase, Coal refit,
route and fare with the same stock mine and power plant after a partial
load restore. The Bakewell cargo and hovercraft also ran as native Linux
client projections and earned real fares. The exact source table check is
tests/ship_complete_temperate_roster_rc1.py. See also the
[stock content inventory](stock-content-inventory.md).
