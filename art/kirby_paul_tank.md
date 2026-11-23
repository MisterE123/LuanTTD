# Kirby Paul Tank

`kirby_paul_tank.blend` contains an original standard-gauge 0-6-0T in
olive tank livery, with separate editable parts for the rolled boiler,
smokebox door, flared open chimney, dome, riveted side water tanks, hollow
cab and coal bunker. Each of the six driving wheels is an annular tyre
with eleven separately modeled spokes. Quartered crankpins carry the
long side rods; the main rods connect to real piston slides and cylinders.
Spring buffers, matched knuckles, brake air hoses and the sealed lamps
are modeled rather than painted shapes. Native asset uses one pose; its
running gear is not animated by this art change.

## Source and design

This is the original model for OpenTTD 14.1's stock temperate rail engine
**0**, not an exact museum scan. The pinned `src/table/engines.h` entry sets
64 km/h, 300 hp, 47 t, zero cargo capacity, regular rail, steam running
cost class, acquisition factor 7, running cost factor 50, 15-year life and
30-year base model life. `src/vehicle_type.h` sets its unshortened stock
length to eight. This document records the roster; asset files don't
encode the simulation or art from OpenTTD.

For historical silhouette, use the
[Great Central Railway's preserved LMS Fowler Class 3F No. 47406](https://www.gcrailway.co.uk/engine/no-47406/):
six coupled drivers, side tanks and a large rear bunker are characteristic
of that short-wheelbase British tank design. Wheels, shape, colors and
lettering are original modeling. No raster or proprietary asset was
imported or traced.

## Mount

- `bl_rail_kirby_paul_tank.obj` and `bl_rail_kirby_paul_tank.png`.
  Standard Luanti mesh entity, native X/Y/Z visual scale all **1.0**.
  No legacy longitudinal correction is needed. Nose is local -Z.
- The origin is wheel contact: use board terrain base + **.614** on a
  flat running piece, or evaluated span level + .614. Axles at longitudinal
  -.269, -.051, +.171; tread centers are exactly ±.212 on the existing
  .424-node rail gauge. Both curve turns are checked against the real
  width of the existing .060-node rail heads using the game's tangent
  pose and radius-one stock half tiles.
- The two knuckle faces stop at Z ±.499, centered .157 above rail crown,
  leaving .002 longitudinal play at 1.000-node stock straight center
  spacing to the existing passenger or open freight wagon. As on the
  other LuanTTD rolling stock, diagonal alignment and wheelbase chord
  are handled in presentation, independently of the mesh. The model's
  maximum half-width is .264 at the running gear and its refitted
  highest point is .613 above rail crown. The cab has a lowered side
  rail and raised doorway reveal, without moving any wheel contacts
  or coupling mounts.

## Rebuild and verify

```sh
KIRBY_ART_RENDER=/tmp/kirby.png blender -b -t 4 --python-exit-code 1 --python tools/build_kirby_art.py
python tests/kirby_paul_tank_art.py
# Optional independent roster assertion against the pinned engines.h:
python tests/kirby_paul_tank_art.py --upstream-engines /tmp/bayline-ott-src/engines.h
BAYLINE_NATIVE_TOOLS=/tmp/bayline-run BAYLINE_NATIVE_TCP=1 bash tests/kirby_paul_tank_art_native.sh
```

The native fixture includes survey and ground-level views with the existing
open coal wagon, plus a tangent view of the 0-6-0 on the tight stock curve.
This is mesh and mount QA, not a route, payment or train control proof.
