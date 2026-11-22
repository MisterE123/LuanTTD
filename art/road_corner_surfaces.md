# Native road bends

The four ordinary two-arm road corners (road masks 3, 6, 9, 12) use
one original raster design rotated to the four orientations. They used
to be perfect rectangular elbows. The original OpenTTD motion curves
interpolate through certain pixels outside that box, so a wheel could
appear to roll on grass, even when its vehicle fit the straight lane.

The new raster adds a compact inside fillet and a gentle local flare
around the outside of each bend. Its centerline has one diagonal dash
between the unchanged straight dashes. The town variant follows the
bent shoulder with a short continuation of the curb and sidewalk.

Each corner changes **80 net paved texels out of 1,024** and never
extends the visual road profile in the outer two pixel rows at any tile
edge. Straight road lanes remain .3125 nodes each; the two road
shoulders, terminal texture samples, and dash phase still match exactly.
Straight, dead-end, T-junction and four-way input rasters are unchanged.
Road, grass, town and slope variants use the same asphalt pixels.
Crossing/bridge/tunnel approaches continue to use the unchanged
straight masks. There are no changes to the terrain, road topology,
movement, vehicle width or capacity.

## Test and rebuild

```bash
python3 tools/road_surface_raster.py
python3 tools/build_sloped_road_art.py
python3 tools/build_town_streets.py
LUA=/path/to/lua python3 tests/road_corner_art.py
python3 tests/level_crossing_art.py
BAYLINE_NATIVE_TOOLS=/path/to/native/tools tests/foster_bus_art_native.sh
BAYLINE_NATIVE_TOOLS=/path/to/native/tools BAYLINE_FOSTER_TOWN_STREET=1 tests/foster_bus_art_native.sh
```

`tools/make_art.py` uses the same authoritative road raster for the
regular full asset rebuild. The focused rebuild writes just the four
corner families. The Python test checks all 512 compatible tile-edge
pairs and all tread points in **12,784** right-hand road poses with
16 subdivisions between stock frames. All nine verified body styles
now maintain full sampled tread contact with asphalt or center-stripe
paint, including the smaller inside and larger outside elbow in all
rotations. This test measures the physical tires rather than demanding
that a tall bumper or mirror never overhang the verge. It does not
change the stock road projection or assert passing clearance during
acute turns.
