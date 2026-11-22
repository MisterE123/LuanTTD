# SH '30' — stock electric #23

Original Class 86-inspired 3D model for [OpenTTD 14.1](https://github.com/OpenTTD/OpenTTD/blob/14.1/src/table/engines.h)
#23: `RVI(20, G, 26, 160, 3600, 84, 180, RC_E, 0, C, E)`, one
full-length electric head, 160 km/h, 3,600 hp, 84 t. Image 20 maps to
2937. [OpenGFX 7.1](https://github.com/OpenTTD/OpenGFX/blob/7.1/sprites/base/base-2905-rail-vehicles-engines.pnml)
shows a blue/grey body and yellow cab ends at (111,180) in its temperate
engine sheet, a shared silhouette for SH '30' and SH '40'. No stock
bitmap, bitmap palette, or upstream mesh is copied or shipped.

The [OpenTTD manual](https://wiki.openttd.org/en/Manual/Base%20Set/Trains/SH%20%2730%27)
identifies the Class 86 as the real-life basis. Original AL6 details
here include two outward cabs, electrical ventilation grilles,
a dark shallow roof with separate ceramic insulators, two two-axle
powered bogies, and **one** raised pantograph. The [AC Locomotive Class 86
history](https://www.aclocogroup.co.uk/index.php/history-introduction/ac-history-2nd-generation-locos/class-history-al6-86)
documents the single collector, retained rather than interpreting both
shapes in the shared sprite as two pantographs. Ian Taylor's [*Electric
locomotive at Preston*](https://commons.wikimedia.org/wiki/File:Electric_locomotive_at_Preston_-_geograph.org.uk_-_6124823.jpg),
2019, [CC BY-SA 2.0](https://creativecommons.org/licenses/by-sa/2.0/),
was observed for side cooling banks, narrow roof rims, two cab
windscreens, and the visible collector shape. No photographic
pixels, surveyed geometry, real brands or number plates are used.

## Files and mount

- `art/rail_sh_30.blend` has four editable wheel pivots, separated bogie
  castings, and a grouped single upper collector with its own support
  geometry. The game OBJ stays static.
- `bl_rail_sh_30.obj` and `bl_rail_sh_30.png`: native unit scale,
  .424 gauge, local rail crown Y=0, local −Z nose, runtime origin
  flat rail world base+.614. Coupler tips near ±.499 at Y=.157.
  The maximum collector height is **.784 above rail**, flat track
  **base+1.398**. Bare shoe is ±.083 across the body; center at
  local Z=.031. This is a suggested compatible contact-wire underside,
  not an electrical simulation change or live catenary integration.
- Build via `blender -b -t 3 --python-exit-code 1 --python tools/build_sh_30_art.py`;
  optional `SH_30_REVIEW=/path/to/preview.png` adds a Blender review image.

`python3 tests/sh_30_art.py` checks the exact pantograph contact,
wheel and coupled curve positions, tunnel portal profile and original
dataset identity (optional upstream files). The small Luanti graphical
fixture `tests/sh_30_art_native.sh` uses only the mounted asset, original
track/rolling stock and straight native catenary at that datum.
