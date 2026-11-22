# SH '8P', stock #10

Original 3D asset for [OpenTTD 14.1](https://github.com/OpenTTD/OpenTTD/blob/14.1/src/table/engines.h)
temperate steam engine #10. The stock record is
`RVI(0, G, 22, 144, 1600, 170, 130, RC_S, 0, R, S)`, a single standard
head. [The train sprite table](https://github.com/OpenTTD/OpenTTD/blob/14.1/src/table/train_sprites.h)
uses eight views starting at 2905 for image 0; the Jubilee also uses
this index. OpenGFX maps 2905 to the row starting at (111,35) in
`temperate_engines_28px.png`. The familiar offset boiler and tender
read in that shared view were considered, but the 3D SH '8P' gets its
own recognizable silhouette rather than recoloring the Jubilee.

- Original shaped circular boiler, double open exhaust, tall detached
  smoke-deflector plates, bright red beam, openly displayed large
  driving spokes and Caprotti-style cam housing. The visible coachwork
  includes an open cab, a separate drawbar and a six-wheel coal tender.
  Mechanically this is the one stock unit including tender.
- Editable source `art/rail_sh_8p.blend` keeps nine independent editable
  axle pivots with the body and running equipment in named geometry.
  No runtime axle animation is implicit in the OBJ.
- `mods/luanttd_core/models/bl_rail_sh_8p.obj` and
  `mods/luanttd_core/textures/bl_rail_sh_8p.png` mount at unit scale,
  -Z native nose, tire tread local Y=0, .424 rail centers,
  world +.614 at flat base-zero track. Coupling tips reach ±.499,
  centered on Y=.157 at the stock unit spacing.
- Rebuild with `blender -b -t 3 --python-exit-code 1 --python tools/build_sh_8p_art.py`.
  `SH_8P_REVIEW=/path/to/preview.png` also writes a two-angle studio PNG.

## Reference and tests

Photographs of British Rail's *Duke of Gloucester* were consulted for
its very distinctive large smoke plates, boiler, and coupled tender.
No photographs, trademark masks, proprietary mesh, or upstream bitmap
are included or projected into the model. The fleet's green/cream/red
scheme and small SH '8P' plates are original.

- beareye2010, [*71000 at Oakleigh Park, 13 June 2026, No. 01*](https://commons.wikimedia.org/wiki/File:71000_Duke_of_Gloucester_at_Oakleigh_Park,_13_June_2026_-_01.jpg),
  [CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/).
- Hugh Llewelyn, [*BR Riddles Standard Class “8P” 4-6-2 No.71000*](https://commons.wikimedia.org/wiki/File:BR_Riddles_Standard_Class_%228P%22_4-6-2_No.71000_-_9292827257.jpg),
  [CC BY-SA 2.0](https://creativecommons.org/licenses/by-sa/2.0/).
  The side reference shows the BR1E tender profile in particular.

Run `python3 tests/sh_8p_art.py` for real rail overlaps,
turnout/portal fit and two non-filled chimney mouths. Opening the
original tables via `--upstream-engines`, `--upstream-train-sprites`
and `--opengfx-trains` also verifies pinned #10/image0. The six
views in `tests/sh_8p_art_native.sh` come from Linux Luanti running
the actual shipped mesh on the real track geometry with stock cars.
