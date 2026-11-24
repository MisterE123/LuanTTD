# Helidepot and Helistation

Original modular Blender artwork for the OpenTTD 16.0-RC1 Helidepot (1976)
and Helistation (1980). Both have functional +Z-facing maintenance bays,
pressed-metal barrel roofs, glazed low terminals, continuous aprons, and
low field fences. Helidepot has a single ringed stand; Helistation gives
three separately marked stands a continuous apron. The small ochre
painted taxi leads distinguish the route from walk-in terminal entrances.
The category icon uses a rotorcraft silhouette; the two build tools use
the facility silhouettes and stand counts.

Source layout and edges: `src/table/airport_defaults.h` and
`src/table/station_land.h`; apron movement datums:
`src/table/airport_movement.h`. The original upstream's airport preview
art is a design reference only. No sprite, artwork, texture or palette is
included from the reference. All geometry and atlas swatches are original.

- Helidepot's four sections include the depot slot at `(24,4)` and
  stand at `(8,24)`. Helistation's eight sections include the depot slot
  at `(8,3)` and stands at `(40,8)`, `(56,8)`, and `(56,24)`.
- Coordinates convert from stock pixels as `x/8-.5, z/8-.5`.
  Place native tiles at `(tile_x*2,ground_y+1,tile_z*2)`. Grass datum is
  OBJ y=-0.5; the apron and inset markings are flush at native scale and
  do not change vehicle altitude or ground authority.
- Each opening clears the shipped Tricario and Guru X2 rotor sweeps at
  their real scale. Both hangars keep the approach and final shallow
  garage waypoint free of a false black facade or an obstructing rear
  panel. The assets don't change routing or aircraft collision rules.
- Editable masters are `art/helidepot.blend` and `art/helistation.blend`,
  grouped by physical tile and individually named native model section.

Rebuild original OBJ, texture and tool media, then run its regression:

```sh
python3 tools/build_rotary_airfield_art.py
python3 tests/rotary_airfield_art.py
```

To refresh the editable Blender files and produce four visual review
renders (clean field and real Tricario size/clearance for each):

```sh
blender -b -t 3 --python-exit-code 1 --python tools/build_rotary_airfield_art.py -- \
  --blend --preview /tmp
```
