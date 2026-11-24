# Stock railway ground fences

Original cool galvanized posts, rolled top cap and chain link for the ten
plain-rail fence states in OpenTTD 16.0-RC1. The stock sprite bounds and
OpenGFX silhouettes were only references. All vertices and atlas pixels
are authored in LuanTTD.

The edge and full-diagonal forms follow the pinned DrawTrackDetails and
FenceOffset table in src/rail_cmd.cpp. In Luanti coordinates x/z
within [-.5, 1.5], NW/SE run along X, NE/SW along Z. The vertical
screen diagonals run N–S (native x=z); the horizontal screen diagonals
run W–E (x+z=1). Pairs 8/9 and 10/11 differ only in upstream corner
height reference, so each pair shares identical art on flat ground.

Mount each asset as one nonwalkable mesh node at odd X/even Z:

    world = (stock_x*2+1, Trackworks level+1, stock_z*2)
    mesh  = bl_rail_ground_fence_<RailGroundType>_<profile>.obj

The mesh compensates the extra X node and OBJ import reflection. The
model anchors to the native grass top (relative y=-.5), or uses the
matching extended grade. Profile 0 includes all ten fence states. Stock
X rail uses profile 3 or 12 (edge states 2/3/4); Y rail uses profile 6
or 9 (5/6/7). Other grades are currently unsupported by Trackworks.
HalfTileWater is not one of these ten regular forms.

Use the RGBA bl_rail_ground_fence_atlas.png with texture alpha clip.
Physical posts and rolled rails form the silhouette, and opposing
cutout cards make the light chain link double-sided. Each card is one
indexed convex quad. Total OBJ payload is below 100 KB even with the
shared flat aliases. The Blender master provides each native form and
editable wire proxies, not copies of the original reference sprites.

Validation:

    python3 tools/build_stock_rail_ground_fence_art.py --check
    python3 tests/stock_rail_ground_fence_art.py --upstream-rail-cmd /path/to/OpenTTD/src/rail_cmd.cpp
    lua5.1 tests/stock_rail_ground_fence_art_surface.lua

Create or refresh the source and Blender art proof:

    blender -b -t 2 --python-exit-code 1 --python tools/build_stock_rail_ground_fence_art.py -- --blend --preview /tmp/luanttd-rail-ground-fence.png
