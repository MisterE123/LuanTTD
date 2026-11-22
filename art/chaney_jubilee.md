# Chaney ‘Jubilee’

Original temperate steam locomotive with visible tender. The stock reference is
[OpenTTD 14.1's engine #8](https://github.com/OpenTTD/OpenTTD/blob/14.1/src/table/engines.h)
and the [OpenGFX sprite 2905 layout](https://github.com/OpenTTD/OpenGFX/blob/master/sprites/base/base-2905-rail-vehicles-engines.pnml).
The stock definition is a conventional single-head locomotive (base intro
1934-01-01, 112 maximum stock speed, 1,000 hp, 131 t). A narrow, separately
plated coal tender and drawbar appear behind the cab as part of that one
logical vehicle. There is no second tender vehicle, changed roster row, or
upstream sprite data in this kit.

The native shape is wholly original. It has a cylindrical banded blue boiler,
a hollow chimney, two front lamps and a tail lamp, layered bronze/blue lining,
open cab and coal bunker, handrails, modeled lettering, and real wheels and
valve gear. Its editable source has separately named pieces, eight rolling
wheelset joints, and 16 shape poses for both sides of the rods. Scrub frames
1–65 in `art/chaney_jubilee.blend` for one full driver cycle. The Luanti OBJ is
the baked first frame; it does **not** claim animated rods in game.

## Mounting contract

- Mesh: `bl_rail_chaney_jubilee.obj`. Atlas: `bl_rail_chaney_jubilee.png`.
- Use entity scale **1**, ten OBJ model units per native node. Nose is native
  **−Z**, X is across the rails, and Y is up.
- Mount the mesh origin at the rail crown (surface +0.614 on ordinary
  ground). Both wheel tread contact surfaces sit at Y=0, rail centers
  at X=±0.212, and the inward flanges reach Y=−0.009 in the clearance
  groove. Top Y=+0.694, width 0.528, length 0.998 between coupler ends.
- One native node between adjacent stock centers. Coupler ends reach
  Z=±0.499 at Y=+0.157. The tank, cab, tender and body are trimmed clear of
  the neighboring stock on the stock curved path. A fixed coupler has a
  small straight gap and a visible wider gap in a turn. Only the outer
  coupler envelope can touch existing wagon buffer envelopes in eight of the
  1,200 sampled phases; body clearance passes in every sample. Rendering a
  swiveling coupler rather than a static tip would eliminate that artifact.

## Regenerate and verify

```sh
blender -b --python-exit-code 1 --python tools/build_chaney_jubilee_art.py
python3 tests/chaney_jubilee_art.py
blender -b art/chaney_jubilee.blend --python-exit-code 1 \
  --python tests/chaney_jubilee_blender.py
tests/chaney_jubilee_art_native.sh
```

Setting `JUBILEE_ART_RENDER=/path/preview.png` generates the optional two-view
Blender Workbench preview. Optional flags on the geometry check verify the
locally supplied official OpenTTD/OpenGFX source rows and blue palette cue.
Geometry checks use actual railhead/tread bounds, sampled paths in both
hands, actual passenger/open/coal wagons, and the native tunnel profile.
The standalone native fixture tests the exported assets in Luanti at survey,
street, and turnout-level cameras with real neighboring wagon meshes.
