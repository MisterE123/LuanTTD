# Stock coastal landscaping

OpenTTD 14.1 terrain corners are never negative.
`TerraformTileHeight` refuses heights below 0 with **Already at sea
level**. Sea level is 0, not a buried water surface above negative
corner coordinates. Lowering a shelf can leave a genuine dry level-0
trench. Connect that trench to the sea and it can become a bay.
Player-built canals are a different water class and can sit at
higher flat levels; rivers/lakes are generated or authored separately.

## Remove or reclaim water

In a fresh standard game, open **Landscaping** and select
**Bulldoze** to clear an ordinary water tile. The corners stay at
their existing height. Raise a connected coast or it may flood back
when the stock landscape clock visits it.

| Water type | Bulldoze base price |
|---|---:|
| Ordinary sea or river | $10,000 |
| Shore with one raised corner | $10,000 |
| Other coast shapes | $40 |
| Canal | $5,000 |

A **Raise corner** command directly clears ordinary water on all
affected playable cells. For example, at the default TerraGenesis
seed, choose the corner **(3,3)**. With all four cells still wet, it
costs $40,250 ($250 for the corner, plus four ordinary water
clearances). An earlier Bulldoze of one of the cells deducts that
clearance from the later raise. Canals must be bulldozed separately
before the shared corners can be changed, and another company's canal
cannot be removed normally. Water held by a vessel or its reserved
host route, boat facilities, and protected structures stay guarded.
Void border tiles cannot be bulldozed, but an edit to an adjacent
shared corner does not charge for a void tile. Older shared-corner
worlds can clear ordinary water without opting into passive flooding.

## Landscaping beside a river

OpenTTD does not preserve a river if a changed corner belongs to that
tile. Each corner is shared by up to four tiles. An edit can also move
a neighboring corner to keep the height difference between adjacent
corners at most one level. Every river tile in that resulting footprint,
flat or sloped, clears at the ordinary water price. A nearby river tile
outside the footprint keeps its slope and river class.

Rivers are not flooding sources in OpenTTD 14.1. Undoing the change in
height does not regenerate the erased river. Near sea level, tide can
wet a cleared tile from a qualifying neighbor, but it becomes sea or
shore, not river. If you want to preserve a river, choose a corner
farther from the bank and watch for a propagation clearance charge.

## Try it in a fresh coastal world

Choose **Coastal Landscaping** from the new-world setup screen.
Do not enable a preplaced industry profile in the same world. This
prepares a raised shelf behind the starter coast before starting the
campaign. Old saves are not reshaped or migrated. On the otherwise
unchanged starter seed 1751, 946 of 949 unprotected dry flat-level-0
tiles flood by day 40 when connected sea flooding is activated. That
is why this is a separate new-world profile, not a default for old maps.

On default seed 1751 test two cuts:

```text
/landscape level 11 33 13 28
/landscape lower 8 17 10 19
```

The first copies a zero-height corner and costs $3,750 for 15 corners;
the second excavates nine corners for $2,250. Both cuts start dry.
Unpause and let a few game days pass. `/survey 12 28` visits the end of
the bay; `/survey 9 18` visits the inland trench. The reference native
run wetted the bay on day 6. The isolated trench remained dry through
day 24. `/landscape lower 9 18` cannot go lower.

## Source and boundaries

The OpenTTD contributors' GPL-2.0 logic follows pinned 14.1
[`water_cmd.cpp`](https://github.com/OpenTTD/OpenTTD/blob/14.1/src/water_cmd.cpp)
(`GetFloodingBehaviour`, directional flood mask, `TileLoop_Water`,
ordinary `DoFloodTile` and `DoDryUp` transitions);
[`terraform_cmd.cpp`](https://github.com/OpenTTD/OpenTTD/blob/14.1/src/terraform_cmd.cpp)
supplies the corner limit, quota and leveling rules that are already
in the shared terrain planner. Normal-water clearing follows
`TerraformTile_Water` and the ordinary `ClearTile_Water` rules.

- On the same stock landscape cursor as house/industry visits, an
  active sea or one-raised-corner shore can wet only level-0 targets
  allowed by the **destination** slope's source direction mask. The
  one-raised shore can seed another step; a slope with more raised
  corners does not seed floods and dries without eligible active water.
  No instant flood fill or unconditional conversion of level-0 land.
- Natural shore uses the actual terrain slope with horizontally clipped
  water and shingle. A one-corner shore has its specific stock ship track,
  not every open-water route. Non-navigable multi-corner shores do not
  become shortcuts for ships.
- Ordinary water cleared by a level drag is staged through its
  substeps to prevent double charging. Canals and rivers do not seed
  the ordinary flood loop. Protected layers, buildings and existing
  vehicles are not automatically destroyed. The port does not simulate
  vehicle disasters or the stock flooding of railway half-tiles and
  tree ground.

## QA

```sh
lua5.1 tests/water_flood.lua
lua5.1 tests/stock_water_clear.lua
lua5.1 tests/river_landscaping.lua
python3 tests/stock_water_clear_upstream.py /path/to/OpenTTD lua5.1
TMPDIR=/path/to/qa_temp python3 tests/water_flood_upstream.py /path/to/OpenTTD lua5.1
tests/water_flood_native.sh /path/to/luantiserver /path/to/new-private-evidence
BAYLINE_NATIVE_RIVER_LANDSCAPING=1 tests/stock_generated_native.sh /path/to/new-private-evidence
```

The compiled references check 24,000 stock flood visits and 67,584
water clear/terraform cases, including flat and sloped river clearance. The native desktop proof uses the
actual Bulldozer and Raise controls, then resumes the water clock and
reopens the Luanti save. The Lua
fixture exercises shared-corner landscaping, marine track geometry,
protection and the actual shared landscape cursor. The dedicated
native campaign fixture invokes the real commands in the fresh
scenario, checks the sea, 17 shoreline mesh cells and dry trench,
then verifies the same coastline and cursor after a SQLite restart.

The generated-river native regression checks a real flat and inclined
river in Luanti. A nearby edit leaves the flat river node and class
intact; touching it clears it. The raised coastal incline eventually
becomes sea-class water, a flat inland cut stays dry, and an untouched
neighbor still has its original river class and random byte after SQLite
reload.
