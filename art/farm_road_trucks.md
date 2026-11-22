# Hereford Grain Truck and Talbott Livestock Van

Two originally modeled working vehicles for the stock temperate grain and
livestock supply chain. The bodies differ where the stock roles do: the
Hereford has an open grey steel bin and a separate gold grain load, and
the Talbott has a vented blue lattice body and dark, slightly curved roof.

| Stock name | ID / road row / image | 1935 catalog capacity | Vehicle mesh |
| --- | --- | --- | --- |
| Hereford Grain Truck | 141 / 25 / 6 | 20 tonnes of grain | `bl_hereford_grain_truck.obj` and `bl_hereford_grain_truck_loaded.obj` |
| Talbott Livestock Van | 135 / 19 / 4 | 14 items of livestock | `bl_talbott_livestock_van.obj` |

Both are ordinary first-generation vehicles with introduction table offset
5479 and displayed road speed 48 km/h. The stock
[roster](https://github.com/OpenTTD/OpenTTD/blob/14.1/src/table/engines.h)
and [road sprite selector](https://github.com/OpenTTD/OpenTTD/blob/14.1/src/roadveh_cmd.cpp)
were checked. The Hereford's stock full-sprite adder is 48, selected at
ten tonnes or more in the stock 20-tonne body. The Talbott's adder is zero,
so it has the same drawing with or without livestock. There are no pretend
animals always on board and no second load mesh for this vehicle.

We inspected the 1950 catalog with Free OpenGFX, and its licensed
[road sprite sheet](https://github.com/OpenTTD/OpenGFX/blob/master/sprites/png/roadvehicles/vehiclesroad01.png)
provided silhouettes at OpenGFX's 3316 (Talbott), 3340 (empty Hereford),
and 3388 (loaded Hereford). No sprite, cutout, or texture pixels from that
file were distributed. The blue livery is originally authored and fixed
in the runtime models. The tarp, framework, upholstery and grain colors
are authored palette shades, not source texture sampling.

## Mount and editable sources

- The runtime origin is the exact wheel tread contact plane, local **Y=0**,
  and the nose is local **−Z**. 10 OBJ units equals one Luanti node at a
  visual size of 1. Use uniform **.42** for both, with the same view
  transform as the other source road trucks.
- Each asset uses the correspondingly named `bl_*_atlas.png`. Both 368×8
  atlases contain the same tiny original color map; this keeps each vehicle
  mount self-contained.
- The empty and full Hereford OBJ files share byte-identical coachwork,
  up to the final backing mesh group. The separate load is a closed,
  sloped 3D body with faceted wheat and subtle raised kernels, within
  the steel rim; no geometry moves when the display swaps the mesh.
- In `art/hereford_grain_truck.blend`, hide the named removable wheat
  collection to see the genuine recessed floor. The body has actual
  grain-side walls, a tailgate and working-looking latch/hinge parts.
- `art/talbott_livestock_van.blend` contains an open slat frame, internal
  cattle floor, clear ventilation gaps, hinged rear gate and shaped
  roof with distinct lining and hoops. This is still one static mesh,
  with no procedural animation or stock transfer semantics.
- Existing runtime economics, cargo transfer, movement, and selections
  are out of scope for these assets.

## Build and proof

```bash
blender -b -t 3 --python-exit-code 1 --python tools/build_farm_road_trucks_art.py
LUA=/path/to/lua python3 tests/farm_road_trucks_art.py
BAYLINE_NATIVE_TOOLS=/path/to/native/tools tests/farm_road_trucks_art_native.sh
```

Optional `FARM_TRUCK_REVIEW=/path/scene.png` makes a Blender comparison
sheet. The Python test accepts optional `--upstream-engines`,
`--upstream-roadveh`, and `--opengfx` files for auditing. Geometry QA
includes detached grain groups, true lattice openings, full tire contact,
conservative lane clearance and exact right-hand road motion. The native
fixture uses game meshes and paints, beside the stock layout-0 farm. It
shows a same-camera model swap that changes only the wheat, both vehicles
passing, the van's rear and side vents, and a sharp stock corner.
