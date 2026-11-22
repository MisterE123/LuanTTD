# Detachable SH '30' / '40' collector

Additive presentation assets for the original
[SH '30'](rail_sh_30.md) and [SH '40'](rail_sh_40.md). All geometry
and the two palettes derive from the original LuanTTD Blender source.
The old complete OBJ/atlas pairs remain byte-identical.

| Asset | Paint |
| --- | --- |
| `bl_rail_sh_30_body.obj` | `bl_rail_sh_30.png` |
| `bl_rail_sh_40_body.obj` | `bl_rail_sh_40.png` |
| `bl_rail_sh_collector.obj` | same as the parent locomotive |

- Body stays at its original anchor, scale 1 and −Z nose. It retains
  the bolted roof heel feet, ceramic stand-offs, switchgear and cabling.
  Moving child has both linked arms, elastic return arms, pivots and
  contact shoe. Reset to children scale 1 to reproduce the exact
  original rigid model at any pose.
- Pivot in parent-local native node coordinates: `(0,.580,.053)` (X,Y,Z).
  Nominal shoe top in child-local units: `(0,.204,-.022)` (X,Y,Z),
  transversely ±.083. Full shoe world height is .784 above flat rail
  before any pitch. OBJ sizes are in ten units per native node, so
  the Luanti entity attachment offset takes `{x=0,y=5.80,z=.53}`.
- Pitch body normally. Vary only the child visual Y scale; X and Z
  stay one. Let the unscaled plane-section center of the shoe at zero
  stroke be `P`, the parent body-up unit vector be `U`, `a` be the
  horizontal axial coordinate of the line, and its underside be
  `y = intercept + slope*a`. The needed scale is
  `(intercept+slope*P.a-P.y)/(.204*(U.y-slope*U.a))`.
  Choose the solution whose transformed shoe coordinate is actually
  on that wire section, including when the heel and shoe are on
  opposite sides of a tile edge. Do not apply a fixed ramp factor
  at the approach or crest without solving that intersection.
- At the center of a real 1-in-2 grade the native scale is .594–.597
  (exactly `(.784*cos(atan(.5))-.580)/.204`), compared with 1 on
  flat sections. This qualifies the pure split mesh and actual rigid
  wire profile at full grade, **not** transition travel, persistent
  entity behavior or a shipping renderer integration.
- Blender coordinate system Z is up. The moving collections in
  `art/rail_sh_sprung_collector.blend` are parented around a visible
  heel empty; stretch Blender Z about that origin.

Regenerate: `blender -b -t 2 --python-exit-code 1 --python tools/build_rail_sh_collector_art.py`.
`python3 tests/rail_sh_collector_art.py` verifies exact palette/face
reassembly with the old runtime models and real shoe intersections
at both steady grades and axes. `tests/rail_bridge_catenary_native.sh --sprung`
exercises parent/child scale and rotation in the actual Linux client
with both opposing coastal rail test fixture ramp meshes and the ordinary bridge deck.
