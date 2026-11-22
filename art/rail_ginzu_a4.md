# Ginzu ‘A4’

Original native 3D interpretation of the stock temperate **Ginzu ‘A4’**,
OpenTTD 14.1 engine **#9**, image index **1**. The roster defines one
single-head standard-gauge steam engine with default vehicle length;
its base introduction offset is day 5479, maximum speed 128, power
1,200 hp and weight 162 t. The coal tender is its own modeled component
but is not an extra vehicle or an extra length in the game's
[original engine table](https://github.com/OpenTTD/OpenTTD/blob/14.1/src/table/engines.h).

The shape was modeled from scratch after Gresley's full-size 4-6-2
Pacific. The black slanted smokebox, wraparound streamlined garter-blue
skin, low double chimney, molded skirts, crimson spokes, tapered cab
and visible narrow four-axle coal tender distinguish this locomotive
from the open cylindrical-boiler Jubilee. Rectangular cross-sections
at the ends are narrowed and shortened to keep the visible shapes out
of stock neighboring wagons in a small-radius turn. The end couplers
use the existing single-length mount rather than adding a pivot or car.

## References and rights

- [National Railway Museum / Science Museum Group object 1975-7007](https://collection.sciencemuseumgroup.org.uk/objects/co205732)
  identifies the actual Gresley A4 Mallard, 4-6-2 and tender.
- [Gary Lee Todd, Ph.D., Mallard at York](https://commons.wikimedia.org/wiki/File:LNER_4-6-2_A4_Pacific_Class_No_4468_%22MALLARD,%22_Built_1938.jpg)
  ([CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/)):
  overall front-quarter mass and shroud.
- [BWard 1997, Mallard side view](https://commons.wikimedia.org/wiki/File:LNER_Class_A4_4468_Mallard_National_Railway_Museum_(1).jpg)
  ([CC BY 3.0](https://creativecommons.org/licenses/by/3.0/)):
  side cladding, actual handrails, cab cut-outs and open crimson spokes.

Only visual references and stock catalog values were consulted. No photo,
projected tracing, original lettering or upstream sprite/texture data
is distributed. The palette and raised Ginzu fleet lettering are
original. The stock-friendly train proportions are deliberately
stylized and are not a scale model of the museum object.

## Mount contract

- `mods/luanttd_core/models/bl_rail_ginzu_a4.obj` and
  `mods/luanttd_core/textures/bl_rail_ginzu_a4.png`.
- **Native scale 1**, local **−Z nose**, +Y up. Ten OBJ units per native
  ground node. The rail crown is the model's Y=0; the ordinary mounting
  point is the same **+0.614** elevation as the existing Jubilee.
- Wheel centers are **.424** apart across the rail, with twenty tread
  contacts. Flanges reach Y=−.009 into the rail opening. The broad
  working contact bands support the tight game's curved presentation;
  only a narrow middle strip is nickel bright.
- The two centered knuckle ends are Z=±.499 at Y=+.157. Neighboring
  stock centers stay one native node apart. The body is clear of the
  ordinary passenger coach, open wagon and loaded coal wagon, in
  both turn directions and under composition reversal. As on
  Jubilee, there are eight conservative fixed-knuckle vs. buffer
  envelope contacts on the tightest sampled curved tangent. These
  are not shroud/cab/tender/coach interpenetrations.
- `art/rail_ginzu_a4.blend` has separately named nose/skirts/footboards,
  cab pieces, mechanical rods, coal tender parts and ten axle pivots.
  Scrub frames 1–65 for one full main-driver cycle; other axles turn
  at their own radii. The moving rods are quartered and derived from
  16 distinct shapes. The runtime OBJ is the baked rest frame and
  does not animate the engine in-game.

## Regenerate and inspect

```sh
blender -b -t 3 --python-exit-code 1 --python tools/build_ginzu_a4_art.py
python3 tests/ginzu_a4_art.py --upstream-engines /path/to/14.1/src/table/engines.h
blender -b art/rail_ginzu_a4.blend --python-exit-code 1 --python tests/ginzu_a4_blender.py
BAYLINE_NATIVE_TOOLS=/path/to/native/tools tests/ginzu_a4_art_native.sh
```

The upstream table audit is optional. The mesh proof includes actual
standard railhead overlap, 1,200 neighboring consist phases and the
arch of an actual native tunnel. The independent graphical test
pictures both current OBJ and atlas in Linux Luanti, with front, side,
street, attached passenger coach and curved survey angles.
Set `GINZU_A4_REVIEW=/path/preview.png` to add a Workbench render while
generating the assets.
