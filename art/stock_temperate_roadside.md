# Temperate roadside art and behavior

OpenTTD 16.0-RC1's road landscape visit changes bare shoulders to grass or paving, and installs roadside trees or streetlights in the appropriate town zones. A change from trees to lamps goes through barren ground and then pavement. Grass and paved roadworks keep their own shoulder surfaces, and the same build cost, road topology, and routing rules. Street furniture is hidden during works and below bridges with insufficient headroom.

The original artwork includes 28 small models: all ten source layouts for trees and for lamps on flat roads, and the four relevant ramp directions for each type. Grass and paving reuse the existing native road top. New compact sheets provide barren shoulders and the paved/barren ramp surfaces without modifying the actual road or lane markings. The trees and stained-metal street fixtures are native 3D models; this package does not redistribute sprites.

- Editable [Blender models with packed material](stock_temperate_roadside.blend).
- Regenerate or validate the assets with `python3 tools/build_roadside_temperate_art.py [--check]` using Pillow.
- Reassemble the editable Blender gallery with `blender -b -t 2 --python-exit-code 1 --python tools/save_roadside_temperate_blend.py`.
- [Compiled upstream comparison](../tests/roadside_temperate_upstream.py), [worker/projected data regression](../tests/roadside_temperate_world.lua), and [genuine native campaign check](../tests/roadside_temperate_native.lua) from a 128×128 generated map.

The native fixture waits for a real town road to change state, then verifies both the road shoulder and the lamps/trees mesh. This is the standard-road set; level crossing and unpaved tram-only combinations have separate art requirements.
