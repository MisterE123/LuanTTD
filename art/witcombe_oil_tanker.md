# Witcombe Oil Tanker

Original native 3D fleet art for OpenTTD 14.1 engine **#132** (road row 16, image 3).
The pinned [engine table](https://github.com/OpenTTD/OpenTTD/blob/14.1/src/table/engines.h)
assigns oil cargo in temperate, arctic and subtropical climates and capacity 21
(21,000 L). In [stock road rendering](https://github.com/OpenTTD/OpenTTD/blob/14.1/src/roadveh_cmd.cpp)
image 3 has base sprite 3308 and full-adder **0**: a completely enclosed vehicle
with the same exterior at every load. Only one runtime mesh is needed.

## Files and mount

- Editable: `art/witcombe_oil_tanker.blend`. Four collections separate the coachwork,
  chassis/tires, tank/mount and rear transfer hardware. The tank is a true oval section
  with sealed dished ends, two bolted band saddles, twin inspection lids and narrow
  tread boards. An open rear ladder, hose spool and capped transfer manifold remain
  separately editable. Plumbing shapes are intentionally stylized, not functional plans.
- Runtime: `mods/luanttd_core/models/bl_witcombe_oil_tanker.obj` and
  `mods/luanttd_core/textures/bl_witcombe_oil_tanker_atlas.png`; one original color atlas,
  no texture dependencies. Use a uniform .42 visual size and the existing Witcombe
  road vehicle transform. Y=0 is tire contact; native nose -Z. At .42 scale the
  total envelope is .25830 wide × .27778 high × .66675 long in Luanti nodes.
- Rebuild: `blender -b -t 3 --python-exit-code 1 --python tools/build_witcombe_oil_tanker_art.py`.
  `WITCOMBE_OIL_REVIEW=/path/to/preview.png` adds an optional studio render.
- Geometry: `python3 tests/witcombe_oil_tanker_art.py` verifies the closed welded
  shell, real curved shoulders and open lower cutout, both sets of road lane
  pivots, 6,768 real right-hand stock road poses and 6,760 freight-stop poses
  at the exact scale. Optional `--upstream-engines`, `--upstream-roadveh` and
  `--opengfx` point at the original data tables to check source identity.
- Linux native inspection: `tests/witcombe_oil_tanker_art_native.sh` drives a
  Luanti client on an isolated X display to photograph front, side, rear, a
  real diagonal road turn pose, and the survey view.

## Historical and stock references

Jeremy (Sydney, Australia), [Leyland Hippo Fuel Tanker 17554360565](https://commons.wikimedia.org/wiki/File:Leyland_Hippo_Fuel_Tanker_(17554360565).jpg)
and [17527868876](https://commons.wikimedia.org/wiki/File:Leyland_Hippo_Fuel_Tanker_(17527868876).jpg),
© Jeremy, [CC BY 2.0](https://creativecommons.org/licenses/by/2.0/), photographed
at the Historical Aircraft Restoration Society on 9 May 2015. The first
photograph was visually consulted for period oval tank proportions, pressed
cab surfaces and the tank-top equipment runway, not traced or incorporated.
The blue two-axle Witcombe, its warm steel tank and its small OIL/132 marks
are original fictional fleet artwork, not the photographed Shell liveried
vehicle. No photos, stock sprite bytes, manufacturer logo or proprietary
assets are embedded in the scene or game files. The OpenGFX road mapping was
checked only for stock image identity.
