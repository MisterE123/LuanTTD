# Wildlife mesh materials

Each ordinary wildlife asset now exports one OBJ group using the shared
opaque atlas. Blender source collections keep the separate anatomical
parts, and the exported files preserve their names in comments. The
native loader no longer creates a material section for each part.
The change does not affect any vertices, normals, UVs, face order or
animation poses. Across ten runtime assets, OBJ groups dropped from
407 to 10. This is a reduction in material sections, not a measured
overall frame-rate claim.

`python3 tests/wildlife_art.py` checks geometry, editable source, atlas and
poses. The native Linux test `bash tests/wildlife_native.sh` renders the
five species and checks that the client does not report extra material
sections for their shared atlas.

Wildlife now averages **24% of the prior number of active animals** in a
fixed-view sea, coast, farm and woods comparison (2.14 versus 8.90 over
30 simulated minutes per habitat). Boats and shop-car simulation are
unchanged. Porpoises swim below the surface between leaps and pitch
with their arc. Humpbacks come up to breathe, dive, and occasionally
breach. Foxes are half their previous height, width and length, without
moving the ground contact point. The per-viewer `/candy` toggle is
unchanged. `tests/wildlife_motion.lua` exercises the production pose
and abundance logic, and the Linux client replay uses actual sampled
swim/surface poses.
