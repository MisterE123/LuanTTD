# Street pedestrian

An original stylized coastal town pedestrian in a fitted teal wool
jacket, tan scarf, canvas flat cap, dark trousers, leather boots and
a small shoulder satchel. The face, wool layers and accessories are
modeled rather than billboard graphics. No third-party mesh, texture,
or reference art is embedded.

`street_pedestrian.blend` includes the material swatches, editable
geometry, 12-bone gait rig and the original keyframed idle/walk action.
The GLB root sits at the soles. The asset is authored at 0.511 nodes
before engine scaling; Street View renders it at 57% (about 0.291
nodes tall, with eyes at 0.263 nodes) to fit town doorways.
The Lua walk controller preserves the builder's original model, eye
position and animations on exit.

Rebuild both runtime assets and the editable source in Blender 4.3:

```sh
blender -b --factory-startup --python tools/build_street_avatar.py
python3 tests/street_avatar_art.py
```

The small swatch layout is authored by the generator and packed
into the editable Blender source. The Luanti-compatible GLB carries
its UVs; the game supplies the separate PNG palette.
The animation timeline is glTF seconds (idle 0–1; stride 2–14),
with Luanti playing the stride at 15 times timeline speed.
