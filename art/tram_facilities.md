# Original tram depot and street stops

`tram_facilities.blend` contains six editable 3D assemblies. The street
stop has two ramp-ended, stone waiting islands, a canopy and bench on each
side, route flags and a catenary mast set behind the waiting area. The tram
shed is a brick-and-steel shop with a real, open single front portal for
both traffic lanes, a closed rear, roof monitor, inspection floor and
interior contact wires. It is not an ordinary bus depot scaled up.

| Runtime mesh | Axis / portal |
| --- | --- |
| `bl_tram_stop_0.obj` | Stock axis 0, native X, arms 10 |
| `bl_tram_stop_1.obj` | Stock axis 1, native Z, arms 5 |
| `bl_tram_depot_0.obj` | NE / -X portal |
| `bl_tram_depot_1.obj` | SE / +Z portal |
| `bl_tram_depot_2.obj` | SW / +X portal |
| `bl_tram_depot_3.obj` | NW / -Z portal |

Each is a complete static overlay, using one
`bl_tram_facilities_atlas.png`. Mount at even world position
`(2*tile_x, base+1, 2*tile_z)`, with the ordinary flat ground or
existing road beneath. Do not add the generic tram rail, wire, or mast
models on a facility tile. This art expects level ground and contains no
logic for construction, routing, fares, or service.

- Both tram lane centers are 0.155 node from the street centerline, with a
  0.106-node wheel gauge. The four embedded railheads are road datum +
  0.012 node. Twin contact wires are datum + 0.500, matching the ordinary
  kit and the streetcar pantograph. Joining edge profiles were compared
  on actual exported OBJ geometry, not visual estimates.
- The paired islands begin at cross-track distance 0.3495 node and are
  0.074 node high over their boarding length, with lower end ramps. The
  current 3D bus, truck and streetcar lateral envelopes (including
  pantograph width) fit the straight passage with at least ~0.060 node
  before the islands. Additional fixed catenary hardware above the lanes
  clears the vehicle envelope.
- The depot's real portal clears both travel lanes and their roof gear.
  Its generic approach joins only on the door side. Rails and wires
  continue into the interior to the stopped vehicle rather than ending
  abruptly at the center of the depot.

No OpenTTD artwork was copied. The colors, models and construction are
original LuanTTD art. Regenerate with Blender, then check the meshes:

```sh
blender -b -t 4 --python-exit-code 1 --python tools/build_tram_facilities_art.py
python tests/tram_facilities_art.py
TRAM_FACILITIES_RENDER=/tmp/tram-facilities.png blender -b -t 4 --python tools/build_tram_facilities_art.py
```

The regression compares all six facility junctions to the separately
authored ordinary tram rail/wire profiles, measures the real vehicle
models around the stop islands and casts 280 clearance rays through the
four directional depot meshes.
