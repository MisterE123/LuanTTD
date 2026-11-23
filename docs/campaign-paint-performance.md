# Local terrain painting

LuanTTD's engine thread paints the simulation worker's bounded scene into
native Luanti mapblocks. The painter now uses the maximum occupied node
height for each projected tile, including a margin above ground, bridge
decks, portals, and other elevated anchors. It still clears old or
incorrectly rotated nodes above that height. Unchanged blocks do not go
through a redundant engine write. Initial map generation retains its
usual lighting and write path.

In a native Luanti 5.10 server benchmark, the two painters rendered the
same 64×64-node scene in a 128² logical map. The comparison checks both
the exact content ID and param2 of every node. These are elapsed server
painting times, including VoxelManip reads and writes, not client FPS:

| Case | Before | After |
|---|---:|---:|
| Lowland sector, distant level-54 ridge, unchanged scene | 84.9 ms | 34.3 ms |
| Same sector, with two stale nodes to clear | 69.4 ms | 44.7 ms |
| Flat map, unchanged scene | 23.9 ms | 9.1 ms |
| Flat map, with changes to commit | 20.8 ms | 20.7 ms |

Each number is the median of seven runs. The ridge case checks 241,664
voxels; the flat case checks 32,768. Actual gains depend on terrain and
whether the region is already current. No gameplay or terrain state
changes.

Reproduce with `bash tests/campaign_paint_bench_native.sh e0a13ec` in a
checkout with Luanti's server and Python available. Set
`BAYLINE_PAINT_PEAK=2` for the flat case. The test uses a disposable world
and runs both passes with the original renderer helpers and assets.
