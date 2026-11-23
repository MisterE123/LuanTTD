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

QA: both cargo boats used real worker-authorized purchase, Coal refit,
route and fare with the same stock mine and power plant after a partial
load restore. The Bakewell cargo and hovercraft also ran as native Linux
client projections and earned real fares. The exact source table check is
tests/ship_complete_temperate_roster_rc1.py. See also the
[stock content inventory](stock-content-inventory.md).
