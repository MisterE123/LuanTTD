# Timber road bridge

The editable `road_bridge_wood.blend` is an original 3D road bridge and
showcase, using weathered timber stringers and planks, side railings with
forged fasteners, lower trestle bents, and masonry bearing faces. The
snap-together parts refer to the wooden bridge at stock catalog index 0
in OpenTTD 14.1; no source sprites or textures were used.

## Mesh contract

All pieces use `bl_road_bridge_wood.png`. Render a regular bridge part at
native node `(2*x, deck_level, 2*z)` where `x,z` is the logical tile and
`deck_level` is the floor of the continuous main-span running surface.
The road is centered on native `(2*x+.5, deck_level+.5, 2*z+.5)`, with the
same .625-node two-lane road width and .0625-node shoulders as nearby
roads. The dashed marking stops before tile edges as it does on the
existing straight road art.

| Part (prefix `bl_road_bridge_wood_`) | Units and orientation |
| --- | --- |
| `span_0.obj` / `span_1.obj` | Repeat over interior tiles only; axis 0 = X, 1 = Z. Running surface local Y +.5 end to end. Includes a short pier cap. |
| `head_flat_{dir}.obj` | Level bridge head, running surface local Y +.5 at both ends. For a head whose post-foundation terrain grades toward the gap. |
| `head_ramp_{dir}.obj` | Bridge head rising one node from outside (local Y -.5) to inside (Y +.5). For a head whose post-foundation terrain is flat. |
| `pier_0.obj` / `pier_1.obj` | Optional stackable vertical support. Place immediately below a span, with the same axis and X/Z as the deck, at Y `deck_level-1`, `deck_level-2`, etc. Its upper and lower footprints join at local Y ±.5. Use an independent mesh overlay when a terrain/water node should remain under the bridge. |

Head direction points **toward the other end** in stock `DiagDirection`
order: 0 = -X, 1 = +Z, 2 = +X, 3 = -Z. A minimum-length bridge can join
two heads directly. Height/foundation, span clearance, pier spacing,
construction costs, vehicle compatibility and pathfinding belong to the
simulation, not the meshes. In particular the asset fixture does not
implement the stock bridge command or select a support when a road lies
underneath.

## Regeneration and checks

```sh
blender -b -t 3 --python-exit-code 1 --python tools/build_road_bridge_art.py
python tests/road_bridge_art.py
# Optional Blender overview:
ROAD_BRIDGE_RENDER=/tmp/bridge.png blender -b -t 3 --python-exit-code 1 --python tools/build_road_bridge_art.py
# Isolated native client, using the actual OBJ/atlas and original bus model:
BAYLINE_NATIVE_TOOLS=/tmp/bayline-run BAYLINE_NATIVE_TCP=1 bash tests/road_bridge_art_native.sh
```

The structural check measures 64 head/span and direct head-to-head seam profiles, both stock
axes, both head types in all four orientations, vertical pier joins and
ramp height at every running-surface vertex. The native fixture shows
both a river-side overview and a street-level approach; it is art QA, not
a test of live overpass construction.
