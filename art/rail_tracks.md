# Original 3D railway track art

`rail_tracks.blend` is the editable library and sample scene. Each numbered
collection corresponds to a six-bit OpenTTD track mask. The library also
contains the four ordinary straight grades. The authoring file uses real
meshes for the rail crown, web and foot, sleepers, cast chairs, ballast bank,
and individual loose stones. Diamond crossings have cut flangeways; common
turnouts have a low throw linkage. Hardware is presentation, not a simulation
of a movable switch or safety equipment.

The terrain, colors, rail profiles, timberwork and 3D assemblies are original
LuanTTD art. No OpenTTD sprite, model, texture, or other art was copied. The
six values and their connections are the track topology from OpenTTD 14.1
(see `src/track_type.h` and `src/rail.cpp` there):

| Bit | Piece | Enter/exit sides |
| ---: | --- | --- |
| 1 | X | -X / +X |
| 2 | Y | -Z / +Z |
| 4 | Upper | -X / -Z |
| 8 | Lower | +X / +Z |
| 16 | Left | +X / -Z |
| 32 | Right | -X / +Z |

## Runtime mesh contract

- Flat asset: `bl_rail_track_{mask}.obj` for 1–63 inclusive; air for a
  zero mask. Place at even native `(2*x, flat_base+1, 2*z)`. The OBJ is
  aligned to the existing two-node terrain tile; the world tile center is
  `(2*x+.5, 2*z+.5)`.
- Straight grade assets: `bl_rail_grade_1.obj` rises toward +X (terrain slope
  3), 2 toward -X (12), 3 toward +Z (6), and 4 toward -Z (9). Place above
  the slope's mesh at even position `(2*x, slope_base+2, 2*z)`. The lower
  local origin lets ordinary stock terrain stay at `slope_base+1`, while
  the rail mesh follows its world height exactly. Foundation and mixed
  slope construction decisions belong to the simulation.
- All meshes use one `bl_rail_atlas.png` texture. The rolling reference
  height is ground/deck + 0.114 node; the two centers of the rolling
  surfaces are 0.424 node apart. Half-tile arcs are quarter circles of
  radius 1, tangent to other pieces at the tile edges. Incoming and
  outgoing rail crowns share the same profile; mesh end walls are
  omitted at tile-to-tile joints.
- The atlas and OBJ files are sufficient for Luanti. Blender or GEOS
  are not runtime dependencies.

## Authoring and validation

```sh
# GEOS >= 3.10 and Blender 4.x; generation is from authored geometry.
blender -b -t 4 --python-exit-code 1 --python tools/build_rail_art.py
python tests/rail_art.py
# Optional EEVEE Blender overview:
RAIL_ART_RENDER=/tmp/rail-library.png blender -b -t 4 --python tools/build_rail_art.py
# Optional native Linux fixture (preexisting Luanti, Xauth, Xvfb, ImageMagick):
BAYLINE_NATIVE_TOOLS=/tmp/bayline-run BAYLINE_NATIVE_TCP=1 bash tests/rail_art_native.sh
```

The structural test checks all 63 nonempty masks, all four grade assets,
and 12,544 paired edge joins. The graphical fixture loads the game-format
OBJ and texture files in an isolated Luanti world and captures a turnout,
curves, diamonds, a locomotive against the running surfaces, and a straight
grade. It does not test player construction or train simulation.
