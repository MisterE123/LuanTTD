# Stock Temperate canal dikes

LuanTTD translates [OpenTTD 16.0-RC1 `IsWateredTile` and `DrawWaterEdges`](https://github.com/OpenTTD/OpenTTD/blob/16.0-RC1/src/water_cmd.cpp#L683-L826).
The four cardinal neighbors decide the wall sides. A pair of dry sides gets a
solid outside corner. A pair of wet sides gets an inside corner only if the
diagonal tile is dry. Water is directional at a lock, aqueduct, single-corner
coast or half-water railway. Plain rivers, open water, and rocky open water
can hide an adjoining dike without becoming canals themselves.

A canal, canal buoy, ship depot or other stock canal-ground facility gets
the same 12-bit mask it would draw in stock. The worker computes it from
its full board, not the viewer's window, so removing a diagonal just
outside the subscribed sector still redraws the right corner. The mask is
not written to the simulation or the save. It does not affect navigability,
construction cost, terrain, ship clearance, waves, or water level.

The 46 nonempty arrangements have compact, original 3D limestone meshes
and an [editable Blender collection](../art/stock_canal_dikes.blend).
A single overlay anchors to a free subnode inside the 2×2 tile, separate
from the default depot/buoy/bridge deck, lowered buoy and bridge foot.
Ordinary water, locks' own banks, and rivers' separate ground art remain
unchanged. NewGRF sprite overrides are not implemented here.

**Checks:** `tests/canal_dikes_upstream.py` compiles the two pinned functions
and compares 221,440 results with Lua. `tests/canal_dike_scene.lua` proves
the host mapping and outside-window invalidation. In
`LUANTTD_QA_CANAL_DIKES=1 bash tests/campaign_worker_stock_residential_native.sh`,
a graphical client observes paid canal, Bulldozer and recut commands,
then the low bridge/shifted buoy and depot/dike combinations, including
an actual save and process reopen.
