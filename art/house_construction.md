# Ordinary house construction stages

Three original native meshes for the early-to-mid-century 1×1 temperate
house progression in OpenTTD 14.1. The reusable cottage scale and warm
stone, linen siding and terracotta match LuanTTD's installed period
houses. Every surface, material, line, rafter and window is original.
No OpenTTD or OpenGFX sprites were imported.

| Stock stage | What is physically present |
| ---: | --- |
| 0 | Low mortared limestone footing, survey strings and pegs, rough service bed, brick/timber piles and a working joiner's trestle |
| 1 | Same footing plus oak plates, open joists, partly laid floorboards, framed door and sash openings, wall plates and temporary braces |
| 2 | Same footing/floor with partly installed walls, one glazed sash, exposed timber rafters, partial terracotta roof and leaning ladder |
| 3 | The existing finished-house mesh selected by the actual stock house ID. This asset kit does not replace it. |

The order follows the four source draw slots
([`town_cmd.cpp`](https://github.com/OpenTTD/OpenTTD/blob/14.1/src/town_cmd.cpp)
and [`town_land.h`](https://github.com/OpenTTD/OpenTTD/blob/14.1/src/table/town_land.h)).
The first three geometries are reusable render presentations, not
per-building sprite reproductions or replacements for stock growth,
probability, acceptance, phasing or occupancy rules. Only apply them
to supported ordinary one-tile houses.

## Runtime mount

- `bl_house_build_stage_{0,1,2}.obj` with `bl_house_build_atlas.png`.
- One full 2×2 native tile. Place the overlay at even
  `(2*x,base+1,2*z)`, with the normal terrain surface at `base+.5`.
  Keep the terrain underneath. The same limestone ring stays at exactly
  the same position and height in all three incomplete stages.
- Heights above terrain: .223, .653 and 1.048 nodes at the highest points.
  All work, stock timber and stepping stones stay within the local tile,
  including the ladder/brace feet. Changes to the terrain slopes and
  final house model selection belong to the game.

## Edit and verify

```sh
HOUSE_STAGES_RENDER=/tmp/house-build.png blender -b -t 4 --python-exit-code 1 --python tools/build_house_construction_art.py
python tests/house_construction_art.py
BAYLINE_NATIVE_TOOLS=/tmp/bayline-run BAYLINE_NATIVE_TCP=1 bash tests/house_construction_art_native.sh
```

`house_construction.blend` contains all three named editable collections
and a side-by-side studio scene. The Python test reads actual exported
triangles, checks identical foundations, monotonic height and genuine
roof/door/floor apertures. The separate native Linux test shows each
stage at street level and the complete sequence alongside an existing
finished house. It does not advance house ages or modify a live world.
