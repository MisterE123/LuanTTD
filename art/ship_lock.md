# Three-tile ship lock

`ship_lock.blend` contains the original editable model library. The
limestone chamber uses dressed cap stones over individually laid blocks,
pedestrian rails, an access staircase and ladder, mooring cleats and
gear drums. Four independent gate poses show genuine paired timber miter
leaves, not an opaque panel over the entrance. Open leaves retract into
the respective side pockets. Moving chamber water remains level while
the original terrain climbs outside the walls.

## Static art

Mount `bl_ship_lock_{lower,middle,upper}_{dir}.obj` mesh nodes at
even native `(2*tile_x, own_base+1, 2*tile_z)`. Their one texture is
`bl_ship_lock_atlas.png`. The direction is **uphill** (0=-X, 1=+Z,
2=+X, 3=-Z). The matching native terrain slope ID is 12, 6, 3 or 9,
respectively. The lower and middle pieces share the low base. The
upper piece uses its own base, exactly one terrain height higher.
Walls, coping, and rails are continuous across both seams.

The lower and upper art already includes the cut-out **flat pool
surfaces** at their actual water levels, `own_base+0.5`. Do not put
an ordinary full water-node top through these meshes: it would cover
the moving water beside the high gate. The middle art replaces the
inclined center with an open lock chamber and retains the exact grass
slope on the outer banks. Water and grass atlas patches reuse the
ordinary LuanTTD texture pixels. No OpenTTD art was used.

## Moving geometry

Use mesh entities with scale `{x=1,y=1,z=1}` and the same atlas.
In the following, `D` is the unit uphill vector, `C` is the
center of the middle tile, and `H = middle_base + 0.5` is the
low water datum. The canonical local axis is uphill +Z. Apply
entity rotations Y = +π/2, 0, -π/2 or π for dirs 0–3, respectively.

| Mesh | Position |
| --- | --- |
| `bl_ship_lock_gate_lower_{open,closed}.obj` | `C - 1.115*D`, world Y `H` |
| `bl_ship_lock_gate_upper_{open,closed}.obj` | `C + 1.115*D`, world Y `H` (not `H+1`) |
| `bl_ship_lock_chamber_water.obj` | `C`, world Y `H+phase`, `phase` from 0 to 1 |

The gate anchors are just inside the neighboring pool pieces so the
actual Bellhaven hull can stop in the center with both gates shut.
Chamber water spans those gate hinge lines; the two longer egress
reaches are static. For a low entrance, open the lower gate, close the
upper and use phase 0. Both gates can close while the chamber rises
or falls. At phase 1, open only the upper gate. These are physically
compatible display states; engine reservation and motion remain
independent of the art. The channel clears at least 1.152 nodes at
all sampled heights, wider than the .762-node Bellhaven ferry.

## Build and proof

```sh
blender -b -t 4 --python-exit-code 1 --python tools/build_ship_lock_art.py
python tests/ship_lock_art.py
SHIP_LOCK_RENDER=/tmp/lock.png blender -b -t 4 --python tools/build_ship_lock_art.py
```

Mesh-level regression checks 12 static poses, the eight modular seams,
672 hull-clearance rays around the real ferry, watertight recesses at
the low/high profile, and all four physical gate states. Native Luanti
fixtures check ship and water placement in a real rendered scene.
No stock simulation or player controls are built into these assets.
