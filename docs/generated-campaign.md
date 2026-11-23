# Play a stock-generated world

Create a **fresh ordinary LuanTTD world**, with no special settings.
It starts with a 64×64 temperate landscape made by the OpenTTD 14.1
TerraGenesis port. In new-world setup, choose **Map width** and **Map depth**
independently. Each axis can be a stock power of two from 64 to 4096, up to
262,144 tiles total: for example 512×512, 1024×256, or 4096×64.
For a dedicated server, set `bayline_generated_map_width` and
`bayline_generated_map_depth` before generating.
Ordinary maps can generate farms, factories, oil wells and refineries
alongside coal and timber. You do not need a separate scenario for those
industries. Reopening a save keeps its recorded geography; create a
fresh world to generate the expanded roster.

At 16,384 tiles and above, successful saves atomically replace
`luanttd-wide-campaign.chk` inside the world folder. Above 16,384 tiles,
the packed file is authoritative and the campaign is not duplicated into
SQLite. Back up or move the **entire world folder** with the game closed.
Larger worlds paint the starting area first and stream scenery as you
explore; towns, industries, and ground elsewhere are still simulated.
A damaged checkpoint stops the load rather than silently selecting an old
snapshot.

The profile is not the Original read-only terrain viewer. It uses the
pinned OpenTTD 14.1 TerraGenesis height and coast pipeline, with no GRF
needed. It generates rough and rocky ground before running the stock
town-placement, English-name, initial road/house growth, temperate
industry placement, landmark placement and forest code. A
single stock random stream starts with the economy startup draw and
continues through those phases. Name parts, municipal roads, completed or
under-construction house records, and the game state persist in SQLite.

The generated world runs the current stock coastal flood and dry-up
port, on the actual landscape clock. Lowering or exposing a connected
sea-level bank can admit water; an inland dry cut does not flood merely
for reaching zero. Ramps and banks render as 3D meshes on shared
corners, not as cubes painted on a flat plane. The native port only
changes supported ground and coastal tiles and preserves protected
structures; it does not yet implement every stock shore or tree case.

- `bayline_seed` selects the stock 32-bit seed, default 1751.
- `bayline_generated_relief` selects flat through mountainous relief.
- `bayline_generated_sea` is the stock 0–3 sea/lake quantity setting.
- `bayline_generated_rivers` selects none (0, default for these example
  routes), few (1), normal (2), or many (3). Set
  `bayline_generated_min_river_length` for the source minimum (default 16).
  Water generation runs before towns and industries, so enabling it can
  move every site. The stock generator can also find no river on a small
  map; it won't draw an artificial fallback.
- `bayline_generated_towns` selects the stock density from very low (0)
  to high (3). The default is normal (2); it is a target, not a guarantee.
- `bayline_generated_town_layout` selects
  `original`, `better`, `grid2`, `grid3`, or `random`.
- `bayline_generated_tree_placer` selects none (0), original (1), or
  improved (2, the default). The forest stores the original species,
  growth, ground, and one-to-four stem counts, using four original 3D
  tree models for presentation. It does not yet run the stock tree lifecycle.
- `bayline_generated_industries` selects the stock density (0–6; default
  normal, 4). The custom target at 6 reads `bayline_generated_industry_count`
  (1–64 in this small native map).
  Normal industry density considers all eight mounted temperate layouts:
  coal mine, power station, forest, sawmill, farm, factory, oil wells and
  refinery. The default seed 1751 generates all eight together. Other
  seeds may not find a suitable site; for instance, the refinery needs an
  acceptable coastal location. There is no industry feature switch.

For freight, right-click a truck stop to see which cargoes it collects or
accepts, then buy the matching truck at a road depot. A town Goods stop
can accept output from a sawmill, factory or refinery on the same map.
In **Rail Operations → Rail Freight**, the Goods tools remain visible
alongside **Oil trains**. Not all OpenTTD industries and transport
combinations are ported yet.

### First coal route (seed 1751)

Use the shared industrial road and coal branch in the wood route below.
From **Roadworks → Road Freight**, build stops at `(46,41)` and `(29,28)`, and buy
a Balogh Coal Tipper from the depot at `(32,43)`. Order it to **full load**
at the mine, then unload at the power station. The first 20 tons earn
$424 in the source-clock test. The return loops give through-stop trucks
room to turn around.


### First wood route (seed 1751)

1. In a fresh ordinary generated world, the managed forest is at
   `(48,44)` and the sawmill is at `(23,42)`.
2. Build the main road from `(25,44)` to `(47,44)`. Add the sawmill
   return via `(25,44) → (25,45) → (30,45) → (30,44)` and the forest
   return via `(47,44) → (47,46) → (46,46) → (46,44)`.
3. Put freight stops at `(45,44)` for Wood pickup and `(26,44)` for
   delivery, and a depot at `(32,43)`. Buy the wood truck, set full load
   at the forest stop first, then order it to the sawmill stop.

The first 20 tons earn $228 in the standard test. Coal can share the
same main road and depot. Branch off
`(46,44) → (46,40)` and add its turnback via
`(46,40) → (45,40) → (45,43) → (46,43)`. To reach the plant, build
`(29,44) → (29,26)` and its loop
`(29,26) → (28,26) → (28,30) → (29,30)`. Coal pickup goes on
`(46,41)`, delivery at `(29,28)`. The first 20 tons of coal earn $424
in the mixed route test.

### Extend mixed freight with the rail Goods Van

Keep supplying Wood. For the tested seed-1751 mixed map **without
rivers**, build a depot on clear ground at `(15,42)` facing SW (+X).
Use X from `(16,42)` to `(21,42)`, an UPPER piece at `(22,42)`,
Y from `(22,41)` to `(22,12)`, a RIGHT piece at `(22,11)`, and
X from `(21,11)` to `(16,11)`. Clear trees normally if needed.

Build platforms `(17,42)–(19,42)` at the mill and `(16,11)–(18,11)`
at Great Chinfingley Market. Place path signals at `(16,42)` facing
NE, `(20,42)` facing SW, and `(19,11)` facing SW. In Rail Freight,
mark the mill platform for Goods loading and the town platform for Goods
delivery. Buy a Kirby + Goods Van and order it between them. The source
route test pays $605 for the first 25 crates. This is distinct from the
native graphical test of the Wood delivery.

### Try a generated river and lock

Make another fresh seed-1751 world with
`bayline_generated_rivers = 3` and
`bayline_generated_min_river_length = 2`. This runs stock TerraGenesis
river widening and makes two rivers on the small map. Enter (25,20) in Jump Map to visit a river incline that connects two levels. To make it navigable,
select **Sea & Air → Harbors → Waterworks → Ship lock**
and click the incline at `(25,20)`. The three-tile lock costs $17,500
at the start. Flat river tiles can be traversed directly; sloped river
tiles need suitable locks. This alternative map doesn't preserve the
freight layouts above.

To test both directions through that lock, build an X-axis ship depot at
`(15,18)` and docks on the land at `(26,18)` and `(28,20)`. Lower the
north corner of `(23,21)` once, put a canal at `(23,20)`, and build the
lock at `(25,20)`. Order the ferry to the upper dock first, then the
lower dock. The stock route test docks before reversing at the dead-end
upper berth and completes all eight steps of the lock in both directions.
This is a navigation exercise, not a paid passenger route; neither dock
is near a town.

Play directly in 3D. Inspect an existing town street near houses, place
a roadside stop from Roadworks, or build your own connections. The
protected sea/void edges are not construction ground. Rendered horizon water
over the void boundary is scenery, not part of the transport network. Railworks,
Bridges & Tunnels, and other compatible construction tools still use
the standard hotbars. Inventory opens the Transport & World Guide;
Jump Map goes directly to a map tile.

This is a **scoped stock pipeline**, not a claim that a mixed vanilla
save or full OpenTTD seed will recreate every tile. It skips most stock
industry types and custom landscape objects. It mounts only modeled
temperate house types and flat municipal growth (no town-built bridges,
tunnels, or destructive grading), so the stock candidate rules run on
a smaller native build set. The ordinary simulation still uses a dense
tile-state array. A 4096×4096 campaign would require a different storage
and simulation architecture and is not offered. The independent terrain
kernel can generate larger survey dimensions. See
[TerraGenesis](terragenesis-port.md),
[river generation](stock-river-worldgen.md),
[town generation](stock-town-worldgen.md),
[industry generation](stock-industry-worldgen.md),
[scenery object generation](scenery-object-worldgen-port.md), and
[forest generation](tree-worldgen-port.md) for the pinned differential tests.

The scenery object stage places lighthouses from stock coastal searches
and radio transmitters on suitable flat high ground. They are protected
unowned landmarks. The default seed has two lighthouses and no antenna;
a low or unsuitable landscape can legitimately have no transmitter.

### Try the larger map

Use a fresh seed-1751 world with `bayline_generated_map_size = 128`,
`bayline_generated_relief = 3`, `bayline_generated_rivers = 1`, and
the mixed-freight test fixture. It creates eight
towns, 13 industries, and two rivers. Enter (106,70) in Jump Map to reach the test corridor. Roadworks can lay road `(102,70)–(111,70)` and put bus
stops at `(103,70)` and `(110,70)`. These cost $2,226 at the start.
The stock road path test verifies the directed route between the
stops. This example doesn't dispatch a bus.

Verification:
- `tests/default_stock_terrain_native.sh` starts a clean Luanti world
  with no game settings, checks the stock terrain and workbenches, then
  uses a real paid corner edit and observes void-fed coastal flooding.
  It also verifies scenario precedence and restarts of both map types.
- `lua5.1 tests/stock_generated_campaign.lua` checks deterministic native
  records, including house IDs after mounting the live economy.
- `tests/stock_generated_native.sh` boots and restarts distinct real
  Luanti servers against a disposable SQLite world and compares the generated
  terrain, forests, landmarks, industry footprints, stock RNG state,
  and settlements.
- `lua5.1 tests/generated_coal_route.lua` builds the recommended freight
  route on the explicit coal-only profile and tests two paid deliveries
  both with and without one-way signs.
- `lua5.1 tests/generated_mixed_rail_goods.lua` verifies normal road Wood,
  sawmill production, and rail Goods deliveries from a purchased train.
- `BAYLINE_NATIVE_GENERATED_RIVER=1 tests/stock_generated_native.sh`
  verifies positive widening, typed river nodes, a paid lock, and SQLite
  restore. The graphical test uses this flag with
  `BAYLINE_NATIVE_GENERATED_WORLD=1`.
- `lua5.1 tests/generated_ferry_lock.lua terminal` tests the actual
  two-direction route and a saved midpoint with the vessel in the lock.
- `BAYLINE_NATIVE_GENERATED_SCALE=1 tests/stock_generated_native.sh`
  verifies the 128×128 landscape clock, far-side stock routing and a
  reload with the map-size setting changed back to 64.
- `tests/stock_wide_atomic.sh TEST_OUTPUT_DIR` kills two disposable
  Luanti servers before their first SQLite commit. It verifies that
  both construction and removal survive with exact balances and that
  the loaded mapblocks reflect the checkpoint.
- The graphical test `BAYLINE_NATIVE_GENERATED_WORLD=1` builds a paid
  roadside stop on an actual generated municipal street and reopens it.
