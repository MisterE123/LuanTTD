# Foster Bus

Original editable Blender coachwork and a Luanti OBJ for stock OpenTTD 14.1
temperate road engine **#118**, road row **2**, graphic index **17**.
Its original details are 1986 introduction (design day 24,107 from 1920),
37 passengers, 112 km/h displayed (source speed field 224), purchase factor
150 and running-cost factor 178. In a 1995 OpenTTD/OpenGFX 7.1 catalogue,
Foster and the Hereford Leopard immediately above it have the same stock
livery/silhouette. They do in the source too: both use image 17. The base
sprite's full-load adder is zero, so there is no empty/loaded model switch.
References: [vehicle table](https://github.com/OpenTTD/OpenTTD/blob/14.1/src/table/engines.h)
and [road vehicle images](https://github.com/OpenTTD/OpenTTD/blob/14.1/src/roadveh_cmd.cpp).

The model is original art with no stock imagery packaged. It preserves
the visible short two-axle single-floor outline, blue company paint, bright
roof, and straight dark window band of the reference while giving the
late production coach a distinct pressed steel shell, folding two-leaf
near-side door, dark impact bumpers, rectangular divided lamps, inset
rollsign, roof ventilator, and sculpted wheel wells around actual tyres.
Paint is fixed on this exported atlas; the upstream sprite is recolorable.

## Use

- Mesh `mods/bayline/models/bl_foster_bus.obj`, palette atlas
  `mods/bayline/textures/bl_foster_bus_atlas.png`.
- Uniform native vehicle visual size **.40** (same as Leopard), native
  **−Z nose** and **Y=0 tire contact**. There is no visual offset.
  Blender axes are +Y nose and +Z up; the exporter writes 10 OBJ units per
  unscaled node.
- At mount scale: width **.25776**, height **.28720**, length **.70090**.
  Actual tire tread sits at Y=0 on all four wheels. Nominal adjacent
  lane centres are .310 apart, leaving .0522 clearance between two
  conservative full-model bounds (including both folded-in mirrors).
- Editable `art/foster_bus.blend`: four named axle-pivot empties, each
  carrying its own tire, hub and related geometry. Wheels are not animated
  by the runtime OBJ; their Blender origins allow independent rotation.
- `tests/foster_bus_art.py` tests no geometric shoulder overhang in the
  compact quadratic ease, and 6,768 actual right-hand compiled stock
  poses covering all bearings/corners and opposite-lane passing. The
  original square raster used to leave some tires up to three texels
  off pavement, similar to the Leopard. The [road bend art](road_corner_surfaces.md)
  now covers every measured tread sample without changing stock routes.

## Regenerate and inspect

```bash
blender -b -t 3 --python-exit-code 1 --python tools/build_foster_bus_art.py
LUA=/path/to/lua python3 tests/foster_bus_art.py /path/to/OpenTTD-14.1
BAYLINE_NATIVE_TOOLS=/path/to/native/tools tests/foster_bus_art_native.sh
```

Use `FOSTER_REVIEW=/path/to/preview.png` on the Blender command for an
original review render. The source comparison path is optional for the
fixture. The graphical test runs real Luanti with the game meshes and
a separate short world, and photographs the front/rear, passing the
Leopard on the right-hand road, and actual left/right stock bend poses.
