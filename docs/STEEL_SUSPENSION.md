# Steel suspension bridges

Stock bridges **#4** and **#5** in OpenTTD 16.0-RC1 are the original-finish
and yellow steel suspension bridges. Both open in **1930** and require
at least three interior tiles; the stock campaign's construction limit
continues to cap the other end. Their respective speed values are **96**
and **112**, with price multipliers **185** and **192**. Both road and
conventional track companies use the ordinary Bridge picker.

The two variants share original 3D girder plates, braced tower ladders,
open portal trusses, suspended decking, catenary cables, and concrete
seats. The road and rail running surfaces are distinct. The paint
variants reuse the same mesh and UV slots, rather than adding a second
copy to the client's media catalogue. The editable geometry and both
material palettes are in [steel_suspension.blend](../art/steel_suspension.blend).
No source game sprite or model is included.

The original simulation supplies the dated styles and per-length cable
and bearing composition. See [concrete suspension](CONCRETE_SUSPENSION.md)
for how source piece codes map to the native model positions. The same
two-portal upgrade retains road routes, lower ways, and railway
reservations. Both types are conventionally priced stock construction,
not campaign flags.

`python3 tests/concrete_suspension_art.py` checks 8,060 cable seams on both
axes across the default 3–64-span range and proves that palette variants
have equal atlas dimensions and different color data. With
`BAYLINE_TEST_BRIDGE_STYLE=4` or `5`, the native road and rail upgrade
fixtures verify both purchases and resumed paid trips, and
`tests/fast_girder_graphical.sh` opens the selected bridge in the real
Luanti client. Regenerate using
`blender -b --python-exit-code 1 --python tools/build_steel_suspension_art.py`.
