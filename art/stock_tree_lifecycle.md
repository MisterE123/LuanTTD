# Temperate tree life cycle

The seven OpenTTD 16.0-RC1 ages are fresh, growing and older sapling;
mature; early decline, late decline, and standing dead. In the pinned
tree command, only the final indexed stem on a tree tile changes
appearance. Every earlier stem is always mature.

Original LuanTTD models retain the existing Oak, Pine, Spruce and Birch
styles. Healthy stems become visibly wider and taller across the first
three phases. Deciduous trees expose forks as foliage thins: later oak
leaves are dry and sparse, birch yellows, and the dead trees are bare.
Conifers lose green and hold brown needle skirts rather than all turning
into bare deciduous snags or stumps. The OpenGFX foliage series was a
private reference for silhouette and phase; no sprite data was copied.

The mature phase uses the unchanged stock mature meshes. The other six
phases use original indexed native geometry and the existing scenery
palette; there is no copied texture. All native heights use the same
five quarter-stem lift anchors:

    Mount: (individual quarter X, terrain base+2, individual quarter Z)
    Local trunk base: -1.5 + lift/2, for lift 0..4
    Mature alias: bl_stock_forest_<style>_<lift>.obj
    Other phases: bl_stock_forest_<style>_<lift>_g<phase>.obj
    Atlas: bl_scenery_palette.png

The master Blender file contains each original stage's adjustable
trunks, boughs and foliage plus the unchanged mature reference in the
fourth column. Runtime section lift files are generated from the same
24 original compact shapes without enlarging their geometry.

Regenerate and verify:

    python3 tools/build_stock_tree_lifecycle_art.py
    python3 tests/stock_tree_lifecycle_art.py --atlas --upstream /path/to/OpenTTD/src
    blender -b -t 2 --python-exit-code 1 --python tools/build_stock_tree_lifecycle_art.py -- --blend --preview /tmp/luanttd-stock-tree-lifecycle.png
