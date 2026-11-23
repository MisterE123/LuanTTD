# Original standard-length railway wagons

`rail_wagons.blend` contains two editable assemblies. The temperate
passenger coach has a curved vented roof, separate window casements and
vestibule doors, covered bogies, and flexible inter-car gangways. The
open freight wagon has a genuinely open load volume, individual floor
planks, pressed stakes, tie-downs, a reinforced underframe and an end
door. These are original meshes and liveries. No OpenTTD artwork is used.

- `bl_rail_passenger_wagon.obj` and `bl_rail_open_wagon.obj` share one
  `bl_rail_wagon_atlas.png`. Register each as a mesh entity with
  `visual_size={x=1,y=1,z=1}`.
- The editable geometry uses native Luanti nodes; OBJ uses 10 internal
  units per node, like the existing vehicle models. Travel nose is local
  -Z; both wagon ends carry compatible equipment.
- Model origin is the wagon center at **rail crown** height. For a flat
  track board node with terrain base `b`, use world Y = `b+.614`
  (terrain top `b+.5` plus rail top `.114`). The rolling tread centers
  are exactly `x=-.212` and `x=+.212` and touch local Y=0. The slightly
  lower wheel flanges sit inboard of the rail crowns.
- Both models are for unchanged stock full vehicle length **8 stock
  units**. At 0.125 node per stock unit, equal full-length straight
  vehicle centers are 1.000 node apart. Drawgear reference planes are
  `z=±.500` at Y=.157. The modeled faces stop at ±.499 to leave .002
  node between paired metal faces. The passenger flexible diaphragm
  reaches farther than its rigid body but all non-knuckle geometry
  remains within |Z|=.478.
- The lower passenger roof tops out at .600 above the rails; the thinner
  upper shell keeps .322 of clear door height. Steps match the existing
  platform elevation and extend slightly farther out toward its coping.
  Neither the wheel gauge nor the couplings were narrowed.
- The standalone locomotives are physically wider in the longitudinal
  axis than that stock coupled center spacing. If using the existing
  locomotive meshes in a stock consist, only shorten their longitudinal
  visual size: steam `z=.56`, diesel/electric `z=.54`, X/Y unchanged.
  That preserves gauge and prevents their shells from overlapping the
  wagon on a straight. Use the standalone scale for the existing
  single-locomotive pilot if preferred. The original locomotives do
  not have matching drawn coupler hardware, so a small gap remains
  between their stock shortened model and these wagon heads.

## Regenerating and checking

```sh
blender -b -t 4 --python-exit-code 1 --python tools/build_rail_wagon_art.py
python tests/rail_wagon_art.py
# Optional arranged 3D proof sheet:
RAIL_WAGON_RENDER=/tmp/wagons.png blender -b -t 4 --python tools/build_rail_wagon_art.py
```

The structural check reads the actual game meshes and tests the treads,
position of the flanges, coupler clearances, open freight bed and all
three locomotive longitudinal bounds. This is art and mount data only.
Native curve spacing, drawgear articulation and loading simulation are
owned by the consist renderer and controller, not these models.
