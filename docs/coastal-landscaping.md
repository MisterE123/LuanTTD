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

On default seed 1751 test two cuts from the **Landscaping** hotbar:

1. **Level area**: pick corner (11,33), then (13,28).
2. **Lower area**: pick corner (8,17), then (10,19).

Use Jump Map and the tile outline to locate the corners.

The first copies a zero-height corner and costs $3,750 for 15 corners;
the second excavates nine corners for $2,250. Both cuts start dry.
Unpause and let a few game days pass. Jump Map coordinates (12,28)
visit the end of the bay; (9,18) visits the inland trench. The reference native
run wetted the bay on day 6. The isolated trench remained dry through
day 24. **Lower corner** at (9,18) cannot go any lower.

## Source and boundaries

The OpenTTD contributors' GPL-2.0 logic follows pinned 14.1
[`water_cmd.cpp`](https://github.com/OpenTTD/OpenTTD/blob/14.1/src/water_cmd.cpp)
(`GetFloodingBehaviour`, directional flood mask, `TileLoop_Water`,
ordinary `DoFloodTile` and `DoDryUp` transitions);
[`terraform_cmd.cpp`](https://github.com/OpenTTD/OpenTTD/blob/14.1/src/terraform_cmd.cpp)
supplies the corner limit, quota and leveling rules that are already
in the shared terrain planner. Raising and lowering water uses the
[16.0-RC1 `TerraformTile_Water` guard](https://github.com/OpenTTD/OpenTTD/blob/16.0-RC1/src/water_cmd.cpp):
natural rivers and canals must be demolished separately. Bulldozing a
river within a town's local-authority radius costs 200 rating points,
down to the stock minimum, as well as the normal water-clear price.

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
python3 tests/stock_water_clear_upstream.py /path/to/OpenTTD-14.1 lua5.1
python3 tests/river_terraform_rc1.py /path/to/OpenTTD-16.0-RC1 lua5.1
TMPDIR=/path/to/qa_temp python3 tests/water_flood_upstream.py /path/to/OpenTTD lua5.1
tests/water_flood_native.sh /path/to/luantiserver /path/to/new-private-evidence
BAYLINE_NATIVE_RIVER_LANDSCAPING=1 tests/stock_generated_native.sh /path/to/new-private-evidence
```

The compiled references check 24,000 stock flood visits and 67,584
historical water-clear/terraform cases, plus the literal RC1 water
terraform guard. Real Luanti checks verify the terrain quote on a
worker-owned world, successful nearby grading, rejection at flat and
inclined river corners, and explicit Bulldozer clearing. After SQLite
reload the deliberately cleared tile is land and the preserved river
keeps its slope, native mesh and random texture byte. The rule covers
recursive corner changes, not only the four tiles immediately sharing
the selected corner.

### Rocky shallows

Open-water rock tiles render as continuous tapering ridges rooted in the
coastal bottom. Small separate rubble stays on that bottom, not suspended
under the exposed crest. The four rock arrangements vary by tile and
direction. The ordinary water surface still rolls over the same geometry
when waves are turned on. This is presentation only; the rock tile's
shipping, flooding and clearance rules are unchanged.

## Live tile-loop dispatch cost

The simulation reads the live tile kind before entering the separate
flood, rail ground, and tree/grass handlers. For example, plain dry
ground with no grass regrowth does not need to enter those handlers
only to return immediately. An actual water visit rereads the source
tile before the next handler, so a dried coast or affected rail
parcel is still handled in the same order. Every stock tile slot is
visited and current neighbors are read directly, without a cached
shoreline mask.

In two alternating native comparisons using the same stock 1024×1024
world, mean CPU per day across 32 warm observations per version went
from **776 to 747 ms**. The median went from **767 to 719 ms**; there
was overlap across runs. The saved day-25 states matched for all
1,048,576 tiles and their graph aliases, excluding the wall-clock
display fraction. Flooded road and tram stops, shore woods and
recovery, fresh grass, rocks, and ordered initial landscape checks
also pass. These measurements are for this world, not an FPS claim.

### Reuse proven open-sea flags on the worker

Generated worker-owned worlds now retain the same packed quiet-water
flags between simulation days. Only a plain sea tile enclosed by
eight plain sea neighbors qualifies. Flood or dry-out changes reset
the affected neighbor flags; the worker drops all flags before
a construction command or when a new industry is placed. Town,
field, and tree growth do not convert plain open sea into a target.
A short cooldown after edits avoids rebuilding flags while a player
is actively building. Views and quotes do not clear the flags.
Company creation, loans, playback changes, and road vehicle purchases,
orders, and dispatch also keep already-proven flags. All other company
commands are conservatively treated as possible edits. The validation
endpoint covers both direct drag placements and quoted commits, so an
actual construction command still clears the cache before changing the
map. No cache state is included in a checkpoint.

In repeated native runs on the same 1024×1024 coastal world, mean CPU
per game day across days 21–31 fell from **804 to 716 ms** (22 warm
observations per version). The complete day-31 state matched,
including all 1,048,576 tiles and 1,559,372 records/aliases, excluding
wall-clock display fraction. The native worker also used the cache
before a paid Bulldozer removed a sea tile; normal tides flooded the
cleared ground again. The autonomous oil-rig opening test verifies
that only a successful placement notifies the worker.

A separate native replay paused, borrowed and repaid, and resumed on six
consecutive days of the same campaign. Across four alternating runs,
the complete day-31 state was identical apart from the wall-clock
display fraction. Cold-cache resets dropped from 24 to zero during
those transactions, avoiding about 26,000 coastal flood checks per
simulated day in this fixture. Whole-day CPU measurements overlapped
between runs, so this is a count of work avoided, not a frame-rate
guarantee.

```sh
tests/live_ocean_edit_native.sh luantiserver /path/to/fixture-world /path/to/fixture.conf ../sea-edit-test
```
