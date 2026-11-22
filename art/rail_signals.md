# Original 3D rail signals

`rail_signals.blend` contains the editable four-state art library. The
two-aperture electric head has real shaped hoods, differently colored glass,
a ladder and a control cabinet. The older upper-quadrant semaphore has an
open steel lattice, a red blade with front and reverse bands, a pivot,
counterweighted linkage and a spectacle lamp. Horizontal means stop and
45° above horizontal means clear; the blade remains red in both states.
The color-light apertures and semaphore lamp also change red/green.

The four OBJ meshes are original and contain no OpenTTD sprite, model or
texture. They share `bl_rail_signal_atlas.png`. Their physical origin is at
center of the mast foot, exactly on the ground, not at the two-node tile
center. Use them as fixed mesh entities with visual_size={x=1,y=1,z=1} over the existing track geometry.
The model's aspect face is local -Z when no rotation is applied. Use the
pose returned by `mods/luanttd_core/rail_signal_art.lua` as the object's rotation
directly, rather than applying road or locomotive heading adjustments.

## Track mounting

`anchor(trackdir, right_side)` returns the exact two 16-unit tile
coordinates from `SignalPositions` and `DrawSignals` in
[OpenTTD 14.1's rail_cmd.cpp](https://github.com/OpenTTD/OpenTTD/blob/14.1/src/rail_cmd.cpp).
The argument is the **protected movement trackdir**, not the direction
the lamp faces. For the straight tracks:

| Trackdir | Protected travel | Stock left anchor | Stock right anchor | Luanti rotation Y |
| ---: | --- | --- | --- | ---: |
| 0 | NE / -X | (11,3) | (11,13) | +π/2 |
| 1 | SE / +Z | (3,4) | (13,4) | 0 |
| 8 | SW / +X | (4,13) | (4,3) | -π/2 |
| 9 | NW / -Z | (11,13) | (3,11) | π |

`pose(tile_x, tile_z, surface_y, trackdir, right_side)` returns a world
position and rotation for those four trackdirs. Supply the world Y of
the terrain/deck at the anchor (e.g. `base+0.5` on the flat board), not
the rail crown. Raw curve positions are preserved for future work, but
`pose` returns nil for them. Some stock isometric sprite placements sit
inside the native 3D swept vehicle gauge. A later curve mount needs a
separately tested presentation adjustment, not a change to stock signal
semantics. For straight tracks the narrow plinth and the signal head's
height clear the current locomotives and pantographs.

`mesh("light"|"semaphore", green)` returns the appropriate model name.
These are visual assets only. Path reservation, operational authority,
signal-state transitions and multi-train safety are not part of this art.

## Reproduction and checks

```sh
blender -b -t 4 --python-exit-code 1 --python tools/build_rail_signal_art.py
python tests/rail_signal_art.py --lua lua5.1
# Optional comparison against an unmodified pinned source file.
python tests/rail_signal_art.py --lua lua5.1 --rail-cmd /path/to/14.1/src/rail_cmd.cpp
# Optional Blender EEVEE art sheet:
RAIL_SIGNAL_RENDER=/tmp/rail-signals.png blender -b -t 4 --python tools/build_rail_signal_art.py
```

The regression checks the exported aspect colors, semaphore arm angles,
low equipment dimensions, 24 upstream source anchors and all eight
straight placement/rotation combinations. No external artwork or
runtime Blender dependency is required.
