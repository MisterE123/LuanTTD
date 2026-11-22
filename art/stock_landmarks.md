# Stock temperate landmarks

Original 3D **lighthouse** and **transmitter** for the classic one-tile
OpenTTD landmark objects. [OpenGFX 7.1's object mapping](https://github.com/OpenTTD/OpenGFX/blob/7.1/sprites/base/base-2601-objects.pnml)
was consulted for type and silhouette: 2602 is the stone lighthouse,
warm lantern and attached low keeper's wing; 2601 is the tall open
transmitter with three dishes and three guy anchors. No sprite,
proprietary mesh, texture, tracing or donated asset is copied or
embedded. The shared swatches and editable Blender geometry were
authored for LuanTTD.

- `bl_stock_lighthouse.obj`: tapered pale masonry shaft, keeper
  quarters with windows and pitched slate roof, stone gallery,
  separate iron railing, divisions in the warm lantern and a cupola
  finial. Height above ground is 1.686 native nodes.
- `bl_stock_transmitter.obj`: open galvanized diagonally braced tower,
  ladder, shallow service cabinet, grounded guy cables and three
  curved reflectors with modeled feedhorns. Height is 2.557 nodes.
- Models share `bl_stock_landmarks_atlas.png`. Place at even anchor
  **(2x, base + 1, 2z)**, neutral rotation; the nominal ground plane is
  local Y=−.5, and the tile center is local (+.5,+.5) in X/Z.
  Every component stays inside its 2×2 tile footprint; small tie
  ends are embedded by less than .006 node. The amber glass and red
  beacon use opaque static color; neither model implies a light
  animation or lighting-system change.

Editable source: `art/stock_landmarks.blend`. Regenerate with
`blender -b -t 3 --python-exit-code 1 --python tools/build_stock_landmarks_art.py`.
Set `STOCK_LANDMARKS_REVIEW=/path/to/preview.png` for an optional
native-scale Blender workbench image.

`tests/stock_landmarks_art.py` validates the approximate silhouette,
three dish concavities, 36 actual open lattice braces, exact mounting
datum and ZIP budget. Pass `--opengfx` with the original object mapping
to verify stock sprites. `tests/stock_landmarks_art_native.sh` opens
a minimal Linux Luanti fixture showing the actual runtime meshes
placed on the real native node datum.
