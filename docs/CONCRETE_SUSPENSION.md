# Concrete suspension bridge

Stock bridge **#3** is OpenTTD 16.0-RC1's reinforced concrete suspension
bridge. It is available from the earliest campaign year, has a stock
speed value of 80 and admits **2–10 interior tiles**, plus the two ramps.
It is part of an ordinary 1950 road or conventional rail campaign, not a
separate scenario. It can replace an existing bridge with the same two
portals, including one already carrying a bus or a train.

The six ordered pieces and their pillar masks come from
`CalcBridgePiece`, `GetBridgeTilePillarFlags`, and
`SUSPENSION_PILLARS` in the pinned OpenTTD source. The Luanti renderer
uses those piece choices to select original catenary-cable models.
The high and low cable seams line up for every stock length, and concrete
towers meet at the section boundaries specified by the source. Clear
underway variants keep supports out of the lower way without removing
the towers above the deck.

The [editable Blender source](../art/concrete_suspension.blend) contains
both the road deck and the conventional rail deck. The original concrete
towers, saddle sleeves, cable hangers, fascia and casting details do not
include OpenTTD or TTD graphics. Only the catalogue, structural piece
roles and allowed span lengths use the stock reference.

## Verification

- `python3 tests/concrete_suspension_art.py`: 180 consecutive cable
  joins, both axes and both decks, all valid catalogue lengths; plus
  deck seam and pier-foot checks.
- `BAYLINE_TEST_BRIDGE_STYLE=3 bash tests/fast_girder_graphical.sh`:
  genuine native Luanti renderer and client with the stock plus, low
  center and minus pieces mounted along two parallel bridges.
- `BAYLINE_TEST_BRIDGE_STYLE=3 bash tests/road_bridge_upgrade_native.sh`
  and `tests/rail_fast_girder_worker.sh` with the same environment variable:
  ordinary worker purchases, live replacement, independent lower
  layers, retained route and railway reservations, restart and paid trips.
- `blender -b --python-exit-code 1 --python tools/build_concrete_suspension_art.py`
  regenerates the source library and matching meshes.
