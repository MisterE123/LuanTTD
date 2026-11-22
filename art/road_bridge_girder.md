# Riveted steel girder road bridge

`road_bridge_girder.blend` is an editable Blender asset library for
the first stock Steel Girder design, catalog ID **2** in OpenTTD 14.1
(`src/table/bridge_land.h`: available 1930, zero to five interior tiles,
stock speed field 64; road-motion cap 128 in half-km/h units).
The modeled blue-grey plate webs, girder flanges, riveted stiffeners,
balustrades, bearing sills and octagonal concrete piers are original
work. No OpenTTD model, sprite or other art was used.

## Runtime contract

The layout exactly follows [the timber bridge](road_bridge_wood.md):
place at even native X/Z `(2*x, deck_level, 2*z)`, with the middle of the
two-lane road at `(2*x+.5, deck_level+.5, 2*z+.5)`. Choose the shared
`bl_road_bridge_girder.png` texture. The asphalt, stripe rhythm, paved
width .625, and shoulders are identical to timber's through each head
and span, and match the approaching ordinary road profile.

- `bl_road_bridge_girder_span_{axis}.obj` joins either head at the
  interior ends or repeats across interior tiles. Axis 0 = X, axis 1 = Z.
- `bl_road_bridge_girder_head_flat_{dir}.obj` sits at deck elevation
  throughout the tile. Use when the underlying, post-foundation
  terrain slopes toward the bridge interior.
- `bl_road_bridge_girder_head_ramp_{dir}.obj` rises from local Y -.5 at
  the exterior approach to +.5 at the interior. Use for flat
  post-foundation terrain.
- `bl_road_bridge_girder_pier_{axis}.obj` stacks vertically at
  `deck_level-1`, `deck_level-2`, etc. Its top mates to the cap on the
  interior span mesh. Keep terrain/water/underpasses independent.

Head direction points toward the bridge interior, in stock
`DiagDirection` order: 0=-X, 1=+Z, 2=+X, 3=-Z. Direct head-to-head
joins are supported. Only the meshes are provided here; the runtime
chooses legal bridge type, position, foundations and supports.

## Regenerate and check

```sh
blender -b -t 3 --python-exit-code 1 --python tools/build_road_bridge_girder_art.py
python tests/road_bridge_girder_art.py
GIRDER_BRIDGE_RENDER=/tmp/girder.png blender -b -t 3 --python-exit-code 1 --python tools/build_road_bridge_girder_art.py
BAYLINE_NATIVE_TOOLS=/tmp/bayline-run BAYLINE_NATIVE_TCP=1 bash tests/road_bridge_girder_art_native.sh
```

The structural regression checks 128 seams across the two axes, both
head variants and direct joins, the exact 30 corresponding timber
road-surface meshes, and the octagonal pier's stack and cap joints.
The isolated native graphical fixture holds the road approaches and
bus models constant with the timber fixture and changes the bridge
geometry and texture. It does not modify a campaign save or test
player construction.
