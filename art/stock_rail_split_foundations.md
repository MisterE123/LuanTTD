# Split rail foundations

These 32 original LuanTTD meshes cover the 36 legal OpenTTD 16.0-RC1 standard-rail profiles that use half, anti-zigzag, steep-lower or steep-both foundations. Some track layouts share the same foundation shape. They use the existing individual curved rail meshes, each at its stock railhead, rather than stretching the rails across a discontinuous surface.

- Editable, UV-mapped objects with packed grass and stone texture: [Blender source](stock_rail_split_foundations.blend).
- Reproduce the OBJ files from the exact Luanti height projection in the game root: `lua5.1 tools/build_rail_split_foundations.lua`. Pass `--check` to verify them without changing assets.
- Reproduce the grass-and-cut-stone atlas: `python3 tools/build_rail_split_atlas.py` with Pillow. It reuses LuanTTD's existing grass and generates original stone courses. Pass `--check` to compare stored pixels.
- Assemble the authored variants in Blender after rebuilding the meshes and atlas: `blender -b -t 2 --python-exit-code 1 --python tools/save_rail_split_foundation_blend.py`.

[Geometry tests](../tests/rail_split_profile.lua) evaluate the continuous track and the integer train movement in both directions. [Native graphical QA](../tests/rail_split_native.lua) builds two paid curved rails on one ordinary generated slope and inspects separate railhead and wall meshes. This change does not enable wet half tiles, special-foundation fences or advanced railtypes on those foundations.
