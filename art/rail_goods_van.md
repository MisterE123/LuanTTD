# Goods Van, standard rail stock #32

The [OpenTTD 14.1 catalog](https://github.com/OpenTTD/OpenTTD/blob/14.1/src/table/engines.h)
gives the temperate standard-rail Goods Van 21 t tare and 25 crates
of Goods: `RVI(38, W, 190, 0, 0, 21, 0, RC_W, 25, R, A)`.
Image 38 in the [train sprite table](https://github.com/OpenTTD/OpenTTD/blob/14.1/src/table/train_sprites.h)
uses base sprite 2753, four views, and a zero full-adder. This is one
closed, covered asset at every load, not an open wagon or a payload
with a fabricated visual swap.

[OpenGFX 7.1's temperate wagon mapping](https://github.com/OpenTTD/OpenGFX/blob/7.1/sprites/base/base-2733-rail-vehicles-wagons.pnml)
places 2753 at (6,79) in `temperate_railwagons_28px.png`. Its dark
covered top and blue framed volume informed the fleet palette and
readable scale. No OpenGFX, photographed or proprietary image is
copied, baked, distributed or embedded. Geof Sheppard's [*BR diagram
1-208 Vanfit 778346 at Buckfastleigh*](https://commons.wikimedia.org/wiki/File:BR_diagram_1-208_Vanfit_778346_at_Buckfastleigh.JPG),
21 February 2016, [CC BY-SA 3.0](https://creativecommons.org/licenses/by-sa/3.0/),
was visually consulted for the shape of the diagonal braces, framed
loading doors, steel end corrugations and handbrake.

- The original covered van has a true bowed board-and-cloth roof,
  individually shaped horizontal boards, separate vertical loading
  doors with hinges and locking drawbar, a recessed end ventilator,
  and pressed steel ends. The small blue/cream Goods 32 marks are
  fictional fleet art.
- Editable source: `art/rail_goods_van.blend`. Independent axle
  pivots and named collections for doors, body, roof, and suspended
  underframe. The runtime OBJ does not encode opening doors or spin.
- Runtime: `mods/bayline/models/bl_rail_goods_van.obj` and
  `mods/bayline/textures/bl_rail_goods_van.png`. Standard unit size,
  local −Z and Y=0 tire datum; +.614 over flat base-zero rail,
  .424 gauge and stock one-unit center-to-center length. Coupler
  points ±.499, centered at Y=.157. No separate loaded geometry.
- Rebuild via `blender -b -t 3 --python-exit-code 1 --python tools/build_rail_goods_van_art.py`.
  `RAIL_GOODS_VAN_REVIEW=/path/to/preview.png` renders an optional
  studio view.

## Verification

`python3 tests/rail_goods_van_art.py` checks the true roof section,
closed double doors, four treads on actual rail, tunnel bore, and
coupled curve envelopes with a sibling Goods Van and several engines
and freight types. Optional flags `--upstream-engines`,
`--upstream-train-sprites`, and `--opengfx-wagons` verify pinned source
rows. Native Linux `tests/rail_goods_van_art_native.sh` inspects
two actual Goods Vans behind a Floss '47 on straight and curved
track. These are geometry/rendering tests, not paid freight tests.
