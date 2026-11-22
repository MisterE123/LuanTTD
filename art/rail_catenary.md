# Native stock railway overhead line

Original editable Blender wire, cast cantilever mast, grounded footings,
porcelain insulators and suspended messenger/dropper geometry.
[OpenTTD 14.1 elrail.cpp](https://github.com/OpenTTD/OpenTTD/blob/14.1/src/elrail.cpp)
describes wire control points at each track edge and normally skips
alternate pylons on plain straight level runs. LuanTTD's original
geometry follows the same edge connectivity and approximately the same
plain-run mast cadence. It does not implement OpenTTD's full pylon
location arbitration. No upstream art or pixel reference is copied.

## Runtime mount contract

`mods/luanttd_core/rail_catenary_art.lua` is a free-standing presentation
selector, not a track builder or source power rule:

```lua
local Catenary = dofile(mod .. "/rail_catenary_art.lua")
local drawing = Catenary.overlay(mask, grade, kind, stock_x, stock_z, force_mast)
-- drawing has name, mesh, texture, offset, pole; nil for unsupported forms.
-- Anchor the selected mesh at {x=2*stock_x, y=base+drawing.offset, z=2*stock_z}.
```

- `kind="plain"` supports **one** stock piece per tile. Flat masks
  1/2/4/8/16/32 use `bl_rail_catenary_<mask>_<pole>.obj`; codes
  1 and 2 support matched straight grades: X uses grades 1/2 and Z
  uses 3/4 (axis bits 1=X, 2=Z). The grade filename is
  `bl_rail_catenary_grade_<grade>_<pole>.obj`. Suffix `0` is wire only,
  `1` adds the in-tile mast. Curves and grades use `1`; flats use
  a mast every second straight tile unless `force_mast` is set,
  e.g. the last tile before a station or shed. Both variants have
  identical contact wire, messenger and five dropper spans.
- `kind="platform"` accepts flat single X/Z tracks, mounting wire
  only, independently of parity and `force_mast`. Both stock native
  passenger platform shelters, signs and hood lamps have confirmed
  lateral clearance, and will not be replaced by mast geometry.
- Every variant uses `bl_rail_catenary_atlas.png`. On flat terrain
  mount the wire **above** the existing ground/rail at even node
  **base+2**. On graded straight track use **base+3** so the separate
  ground and running rail overlays at base+1 and base+2 stay visible.
  Grade selection must use the actual track/foundation result; raw
  terrain code is not the slope selector.
- Actual joined edges have matched X/Z cross sections and underside
  height relative to rail. `wire_edge(mask, grade, side, base)`
  yields world Y only if present. Join two wire sections only
  at the sides they physically share and only when world Y matches.
- Centerline wire underside is **.898 above terrain**, or
  **.784 above flat rail**. At base zero that is world Y=1.398,
  local Y=−.602 for a flat overlay mounted at Y=2. The baked SH ’30’
  pantograph touches under the flat lines. On the full 1-in-2
  slope the current pitched fixed collector would geometrically
  overrun the wire by ~.093 world-vertical units; its tip would
  need a pitch-aware normal extension of ~.701, rather than .784.
  The grade art has exact sloped seams and vehicle-body clearance,
  **not** animated contact or a grade operational promise.
- Deliberate exclusions: **multi-bit junctions/crossings, bridges,
  tunnels, half/foundation grades, and depot interiors**. Feed
  only validated presentation candidates to this helper. Both
  the raised pantograph and ordinary body clear all four native
  depot arches, but no wire is drawn through the enclosed shed.

Authoring: `art/rail_catenary.blend`; rebuild
`blender -b -t 3 --python-exit-code 1 --python tools/build_rail_catenary_art.py`.
`python3 tests/rail_catenary_art.py` and
`lua tests/rail_catenary_selector.lua` verify meshes and the selector.
`tests/rail_catenary_art_native.sh` renders both actual passenger
platform axes, curve, both grade axes and a pantograph beneath a
straight wire in a small isolated Linux Luanti world.
