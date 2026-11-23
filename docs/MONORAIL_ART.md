# First temperate monorail artwork

The OpenTTD 16.0-RC1 identifiers are X2001 (#54), Passenger Carriage
(#57, 45 seats), and Mail Van (#58, 35 bags). The Blender scenes and mesh
textures are original LuanTTD artwork. No upstream or third-party sprite,
mesh, font, or pixel data is embedded. The three models are not yet
offered for purchase.

Run `blender -b --python-exit-code 1 --python tools/build_stock_x2001_art.py`
to regenerate the models and editable Blender scenes. Set
`MONORAIL_REVIEW` to an existing directory for cab, tail, and side renders.
The window and shutter assemblies are surfaced to the actual shells.

The neutral forward direction is -Z. A vehicle rests at the guideway wear
surface, +0.246 Luanti nodes above the local terrain datum. The two bogie
pivots at -0.259 and +0.246 in local longitudinal coordinates are
independent. The body-only meshes and shared `bl_rail_mono_bogie.obj` allow
the 3D renderer to follow the actual stock path separately at both ends.
Use `bl_rail_x2001.png` with the shared bogie. The assembled previews
contain both bogies in their centerline positions; they are not a
substitute for guideway-following articulation.

`python3 tests/stock_x2001_art.py` verifies wheel contacts, design
features, editable sources, split assets, and straddle clearances.
