# Yate Cargo Ship

Original editable, part-separated `yate_cargo_ship.blend` and a deterministic,
UV-atlased Luanti OBJ. The stock OpenTTD 14.1 temperate vehicle is engine
**#211**, local ship row **#7**, sprite index **0**, introduced in **1927**.
It buys as 160 crates of goods and can refit to coal; the engine still uses
160 capacity for that dry cargo. See upstream
[`table/engines.h`](https://github.com/OpenTTD/OpenTTD/blob/14.1/src/table/engines.h)
and [`ship_cmd.cpp`](https://github.com/OpenTTD/OpenTTD/blob/14.1/src/ship_cmd.cpp).
The stock sprite sequence adds only the vessel's direction to its base frame;
it does not select alternate fills for the stock Yate. Both hatch covers
remain shut, with one mesh and atlas for the empty, loaded and refitted ship.

Visual reference was an installed *OpenGFX 7.1* catalogue in OpenTTD, not
the proprietary Transport Tycoon data. Reference cues: long blue company
sheer, twin black rectangular hatches, salmon/orange cargo derricks, white
wheelhouse aft and a red exhaust. The game's blue is a fixed art livery here,
not an assertion that there is no stock company recolor. The model was
authored anew from period break-bulk vessel cues and no upstream sprites,
cutouts, dimensions, brushes or texture pixels are packaged. The tiny color
atlas is authored by the builder and used for physically modeled materials,
not as a painted cutout: recessed wheelhouse glazing, individually modeled
coamings, winches and hooks, open rails, hollow steam stack, clinker lifeboat,
forged bow anchor and below-water screw/rudder are actual geometry.

## Mounting

- `mods/luanttd_core/models/bl_yate_cargo_ship.obj` and
  `mods/luanttd_core/textures/bl_yate_cargo_ship_atlas.png`.
- Entity origin at the real waterline, including a moving lock pool.
  Blender +Y fore / +Z up; native visual -Z fore / +Y up.
  Ten OBJ export units per native node, `visual_size={x=1,y=1,z=1}`.
- Approximate size: 1.84 long, .704 maximum beam; highest mast lamp
  .824 above and .184 deepest keel below water.
- Remains centered on the existing port/depot/lock trajectory, no render-only
  centering offset. The moulded proportions were sized against the lower
  gate's inward-pointing closed leaf, not merely the nominal two-node tile.
  Both headings keep more than .031 native node of fore/aft clearance from
  the two closed gate meshes at chamber center. Bore tests include both
  depot axes and the actual four lock rotations with water measured from
  their original stone and gate datums.
- Derrick/winch hardware is a static stowed configuration. It does not add
  loading semantics, refit control, changing cargo meshes or animation.

## Build and QA

```bash
blender -b -t 3 --python-exit-code 1 --python tools/build_yate_cargo_ship_art.py
python3 tests/yate_cargo_ship_art.py /path/to/OpenTTD-14.1
BAYLINE_NATIVE_TOOLS=/path/to/native/tools tests/yate_cargo_ship_art_native.sh
```

The source-comparison argument is optional for the geometry tests.
Use `YATE_REVIEW=/path/yate.png` on the Blender command for a preview at its
exact water plane. The native test loads these actual OBJ and atlas files into
an isolated Luanti map; it shows low waterline and cabin perspectives at a
real short pier, wider harbour survey, nose toward an open depot, and both
physical lock gates closed around the same vehicle at the 3/8 water step.
