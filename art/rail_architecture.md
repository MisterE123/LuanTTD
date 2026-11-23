# Original railway platform and depot

`rail_architecture.blend` contains six editable assemblies with named
submeshes for rails, stonework, slate, glazing, ironwork, benches and lamps.
They were built for the two-node LuanTTD board, not extracted from OpenTTD.
The models use the existing original railway meshes and wheel gauge, so
approach rails join the ordinary Trackworks rails without a position or
height seam.

The timber canopy and fixtures were shortened independently of the
coping and deck. The boarding surface remains .280 above the ground
while the canopy is .729; the smaller street pedestrian is .291 tall.
The brick shed is now 0.82 of the previous shell width and about 0.81
of its previous height. The actual mounted stock body envelopes clear
the more compact vault. The depot's front-only opening, rail endpoints,
buffer and foundation interface stay fixed. The slim running formation
is .716 wide on a straight, with .600 sleepers; its .424 gauge and .114
running-rail crown are unchanged.

- `bl_rail_platform_1.obj` is a straight X-axis platform and track;
  `bl_rail_platform_2.obj` is its Z-axis counterpart. The stone deck can
  run across multiple station tiles; the coping and track profile are
  continuous. Mortar joints and stone tops partition a single deck
  surface rather than stacking tiny raised planes. Each end has a
  stone face slightly recessed inside the platform, so a freestanding
  end looks finished and two neighbors cannot double up a join plane.
  Each tile has a shelter, glazed panels, seat, lamps and train clearance.
- `bl_rail_depot_0.obj` through `bl_rail_depot_3.obj` are genuinely
  open single-portal structures. Directions are stock NE (-X), SE (+Z),
  SW (+X) and NW (-Z). They contain physical rails through the arch,
  a closed rear with end-of-line buffers, a slate roof and a brick shell.
  Only the open portal side joins another track.
- Use one `bl_rail_architecture_atlas.png` for each combined OBJ. Place
  the mesh at `(2*x, flat_base+1, 2*z)`, with ground underneath as for
  ordinary track. The running surfaces are 0.114 node above the ground and
  0.424 node center-to-center. These meshes are for flat decks/foundations;
  rules for building a station or depot on one belong to the simulation.

Regenerate from the game root with Blender 4.x and the GEOS library used
by the track authoring script:

```sh
blender -b -t 4 --python-exit-code 1 --python tools/build_rail_architecture.py
python tests/rail_architecture.py
```

The structural check reads the shipped OBJ files, verifies all stock
approaches and continuous platform seams, tests the actual triangles
for positive-area overlaps and casts 120 locomotive-envelope
rays through the four arches. Opposite rays confirm those depots have closed
backs. This is an art/fit check, not a substitute for rail operations tests.
