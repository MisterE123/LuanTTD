# Oil Tanker, stock rail wagon #30

The stock [OpenTTD 14.1 engine table](https://github.com/OpenTTD/OpenTTD/blob/14.1/src/table/engines.h)
defines standard-rail cargo wagon #30 as `RVI(36, W, 200, 0, 0, 24, 0,
RC_W, 30, R, A)`: 24 t empty, 30,000 L nominal oil capacity and the
stock full-length wagon body. The [train sprite table](https://github.com/OpenTTD/OpenTTD/blob/14.1/src/table/train_sprites.h)
uses base sprite 2745 with four directions and a zero full-adder for
image 36, so the closed vessel uses the same mesh at every load.

The original 3D wagon has a low silver steel tank with dished ends,
oxide-red underframe, molded saddles and opposing fixed ladders. Its
thin company-blue side band and lettered oil/30 stencils are fictional
fleet colors. The independent inspection cap, grating, valve and
discharge manifold are visual assets, not engineering models.

## Source and mount

- `art/rail_oil_tanker.blend`: separate editable geometry for the tank
  and its bands, ladders and service equipment, frame and suspension,
  and two independently rolling steel axle assemblies. Frames 1–49
  demonstrate the wheel pivots.
- `mods/bayline/models/bl_rail_oil_tanker.obj` and
  `mods/bayline/textures/bl_rail_oil_tanker.png`: single static mesh
  and original flat swatch atlas. Unit scale, -Z nominal nose, tire
  contact local Y=0, at world +.614 on flat base-zero track. Standard
  .424 rail spacing and one native node between coupled centers;
  centered coupler tips ±.499, Y=.157.
- Build with `blender -b -t 3 --python-exit-code 1 --python
  tools/build_rail_oil_tanker_art.py`. Set `RAIL_OIL_TANKER_REVIEW`
  to a PNG path for an extra two-angle Blender view.

Michael Roots, [*BP tank wagon*](https://commons.wikimedia.org/wiki/File:BP_tank_wagon.jpg),
2 May 2009, [CC BY 3.0](https://creativecommons.org/licenses/by/3.0/).
The Kent & East Sussex Railway museum photograph was visually
consulted for the visible braces and chassis arrangement,
side ladder and inspection dome/treadway arrangement. The work is
not traced and includes no photographic pixels, livery, trademarks
or stock sprite art.

## Verification

- `tests/rail_oil_tanker_art.py` checks the welded tank shell and the
  actual wheel contact based on the real rail sections; 6,800 coupled
  poses with Floss, Ginzu, Kirby, stock Coal Truck and a second Oil
  Tanker at both ends, in both travel hands and independently reversed.
  Narrow-curve sampling allows minor centered-knuckle touches of
  stock buffer hardware only; there are no body/frame intersections.
  The body also clears the modeled native tunnel portal.
- Optional `--upstream-engines` and `--upstream-train-sprites` point at
  the pinned tables to revalidate capacity, stock image, and its load
  behavior.
- `blender -b art/rail_oil_tanker.blend -t 2 --python-exit-code 1 --python
  tests/rail_oil_tanker_blender.py` verifies the editable rig.
- `tests/rail_oil_tanker_art_native.sh` photographs the actual exported
  asset in Linux Luanti, hauling two Oil Tankers behind the Floss diesel
  on the common stock track, including the unit-radius turnout.
