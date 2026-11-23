# Stock oil tankers

Build a ship depot and docks within catchment of a working oil source and an
oil refinery. In the ordinary depot buy a tanker and select the oil source
and refinery docks. The initial orders are Full Load and Unload without
reloading. The orders can be edited on the selected active ship. The
oil and refinery choices are computed from their real tile catchments, not
picked by name. Routes have to navigate both ways.

The stock MPS Oil Tanker (#204) holds 220 kL; the later CS-Inc. Oil Tanker
(#205) holds 350 kL. Dates, price factors, running costs, top speeds and the
fixed 10-unit loading pulse are from OpenTTD 16.0-RC1. Both use the stock
ship controller/YAPF, and share one refinery/cargo authority with road and
rail, including real production and source rating. Stock tanker cargo is
not refittable. The distinct original Blender hulls have no load variant,
matching stock drawing behavior.

Ordinary Linux Luanti worker QA built both kinds of docks, bought each
vessel, observed its original native model in motion, and verified paid
220 and 350 kL refinery deliveries. The worker contract also remounts
saved state during a partial load and verifies cargo and clocks across
reload. The same refinery accepted a combined ship and road route, with no
duplicate cargo or fare. See tests/oil_ship_ordinary_worker.lua and
tests/stock_oil_ship_native.sh. For the latter set
LUANTTD_QA_OIL_SHIP=205 and LUANTTD_QA_OIL_SHIP_YEAR=1980 for the later vessel.

This slice covers one oil tanker per world with separate berths from other
services. [Offshore rigs](OFFSHORE_PORT.md) can supply the tanker when a
rig opens in a generated Temperate world from 1960 onward. Full
multiple-tanker dispatch and ship refit facilities are tracked separately.
