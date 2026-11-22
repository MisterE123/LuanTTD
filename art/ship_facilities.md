# Original 3D harbour facilities

`ship_facilities.blend` is the editable 12-mesh library. A two-tile dock
is a narrow, terrain-following gangway joined to a flat timber wharf.
The wharf has raised decking, pilings, treads, mooring bollards, a
tidal ladder, lanterns, and a small timber waiting shelter to one side.
The boat works are two matching masonry halves. They have a shared
standing-seam roof, windows, service catwalks, battered underwater
pilings, a raised door and a physically open center channel at both ends.

All architecture is original; it is not made from OpenTTD sprites or
other external assets. The grass patch in the texture atlas reuses
LuanTTD's ordinary grass pixels.

## Native mounting

Place one static mesh node at world `(2*tile_x, base+1, 2*tile_z)` on an
even tile corner. Every model uses one `bl_ship_facilities_atlas.png`.
The asset deck/ground datum is `base+0.5`, the actual top face of the
ordinary water node. A vessel in the water aligns its own Y=0 with this
datum, not the pier deck or OBJ node center.

| Model pattern | Direction / part |
| --- | --- |
| `bl_ship_dock_ramp_{0,1,2,3}.obj` | Sea direction NE=-X, SE=+Z, SW=+X, NW=-Z |
| `bl_ship_dock_pier_{0,1,2,3}.obj` | Same sea direction and exact gangway seam |
| `bl_ship_depot_0_{0,1}.obj` | X-axis halves; lower coordinate, then higher coordinate |
| `bl_ship_depot_1_{0,1}.obj` | Z-axis halves; lower coordinate, then higher coordinate |

The saved depot part numbers 1 and 2 map to OBJ parts 0 and 1,
respectively. Put ordinary water below pier and depot pieces. A dock
ramp includes its own **exact conventional terrain plane** with grass
UVs: do not stack another terrain slope mesh on it. Its underlying
base soil stays. The shoreline plane is `base+0.5` at the seaward edge
and `base+1.5` at the inland edge. The footway starts only 0.011 node
above that plane at its inland edge and ends at the matching wharf
height, 0.180 above water. The two handrails match exactly at the join.

The depot has no center floor, wall or mullion at working water height.
The straight channel is 1.04 node wide and 1.20 node high above water,
clear below the current vessel's draft. The wharf stays within its own
non-navigable physical tile and does not narrow any adjacent berth.
Routing, station ownership, service, and movement are independent of
these visual meshes.

## Regenerate and verify

```sh
blender -b -t 4 --python-exit-code 1 --python tools/build_ship_facility_art.py
python tests/ship_facility_art.py
SHIP_FACILITY_RENDER=/tmp/harbor.png blender -b -t 4 --python tools/build_ship_facility_art.py
```

The test compares all four ramp planes to the existing stock terrain
OBJ exports, checks that their four plank and handrail joins coincide,
matches the depot roof/wall/catwalk seam profiles, and casts 252
unobstructed rays through the depot channel around the *actual*
`bl_harbor_ferry.obj` hull. The native Luanti art fixture visually
checked the grass slope/wharf join and ferry fit in the open depot. It
does not substitute for pathing or docking playtests.
