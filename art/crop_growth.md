# Farm crop growth art

Original low-poly assets for LuanTTD. Regenerate via
`python3 tools/build_crop_growth_art.py`; the OBJ files import into Blender
as editable meshes. `--check` verifies committed exports against the source.
The generator uses a single shared palette, with no per-rotation mesh copies.

OpenTTD 16.0-RC1 `DrawTile_Clear` and `_clear_land_sprites_farmland` define the
nine ground identities. The existing far textures preserve their row patterns
on all nineteen legal slope masks. Near the camera, phase 2 adds shoots, phases
3–4 add bushier leaves, phases 5–6 add tall grain stalks and golden heads,
phase 7 leaves stubble, and phase 8 shows bundled straw on flat land. No growth
timer, placement logic, freight logic, tile collision or fence behavior is changed.

On slopes the same quarter-tile asset follows four height samples.
Stems are rooted beneath the surface to avoid floating uphill edges. Beyond the
close range, simplified diagonal strips retain the crop silhouette up to 38
nodes out (45 before they are removed), and at survey heights up to 22 nodes.
The scene caps crop objects at 64 total and 28 simplified objects, prioritizing
near views. Distant fields keep the original patterned ground texture.
