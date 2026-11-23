# Darwin 100 #226

Original 1960s-era long-body rear-engined jet, in ivory and cobalt with an
ochre pinstripe. The stock rear-engine/T-tail sprite is shared by six
airliners; this independent model gives the higher-capacity Darwin a
longer pressure fuselage, swept wings with genuine dihedral, rounded
period cockpit, flap track fairings, and a high tailplane. Two aft pods and
a center dorsal S-duct give it an original period trijet silhouette. Three
open intake bores have individually modeled fan vanes and spinners and
three rear metallic exhausts. The trijet interpretation, liveries, and
detailed pressure-shell geometry are original. No stock art or logos are
packaged.

## Mount and art

- `mods/luanttd_core/models/bl_stock_darwin_100.obj`
- `mods/luanttd_core/textures/bl_stock_darwin_100_atlas.png`
- `art/stock_darwin_100.blend`: separate editable pressure cabin, wings/tail,
  three engine bores, and tricycle gear collections. Studio is not exported.
- Native scale **1.00**, nose **−Z**, with all six tires exactly touching
  **Y=0**. Blender +Y nose and +Z up. At unit scale span **1.91958**,
  length **2.21000**, maximum height **.68100**. There is no shape
  reduction or special offset for a short runway.
- Stock base image does not change by flight state, so this art packages
  one exterior. The wheels stay visible in flight in this representation;
  there is no invented gear-state transition.

## Upstream

- [OpenTTD 16.0-RC1 engines](https://github.com/OpenTTD/OpenTTD/blob/16.0-RC1/src/table/engines.h):
  engine #226, aircraft row 11, image index 2, design day 15,461 since
  1920 (1962-05-01), model life 20, vehicle life 25, retirement field 25,
  temperate/arctic/subtropical. Aircraft fields are purchase factor 18,
  annual running factor 240, subtype J (fast CTOL), jet departure sound,
  acceleration 40, stock speed field 74, 35 mail and 170 passengers.
- [OpenTTD 16.0-RC1 stock image selection](https://github.com/OpenTTD/OpenTTD/blob/16.0-RC1/src/aircraft_cmd.cpp):
  image 2 maps to 3781; stock picks the base plus heading without
  checking altitude, landing or cargo. Fast CTOL is unsafe on airports
  flagged as short strips.
- [OpenGFX 7.1 sprite sheet](https://github.com/OpenTTD/OpenGFX/blob/7.1/sprites/png/aircraft/FFPDart.png)
  was consulted for outline only. No rotors or propellers are present.

## Rebuild and verify

```sh
blender -b -t 2 --python-exit-code 1 --python tools/build_stock_darwin_100_art.py
python3 tests/darwin_100_art.py
lua5.1 tests/darwin_city_art_trace.lua > darwin-city-poses.txt
python3 tests/darwin_100_art.py --city-model-dir mods/luanttd_core/models \
  --city-ground-poses darwin-city-poses.txt
```

Set `DARWIN_REVIEW` to a directory to render original front, rear and
ventral inspection JPEGs. An isolated build can set `LUANTTD_HELPERS`
to the production tools directory. Source checks optionally accept
`--engines`, `--aircraft`, `--city-movement`, and `--city-layout`, the
four pinned 16.0-RC1 headers/source files. The stock City runway source
test projects all six real tire contact footprints down the six-tile
takeoff/landing paths. The separate City structural-art test consumes
a true stock-motion replay through all three terminal slots and the
hangar, and checks native mesh clearances, not dispatch economics.
No safe Country Airport operation is claimed.

### City fit and known simultaneous-aircraft limit

On the checked City art the full-size Darwin cleared all static building
and equipment meshes over 2,302 native/eased sampled ground poses through
three stands and their depot returns. All 1,872 source runway wheel samples
sit on the actual wearing course, with at least .31133 node horizontal
margin. This verifies one airframe against the airport, not every dispatch
pair.

Two full-size vehicles can intersect in the faithful City ground paths if
one Darwin is parked at terminal 2 and another uses terminal 3. The optional
`tests/darwin_city_parked_contact.py` diagnostic finds positive 3D triangle-edge
contacts in both directions on the recorded motion. The model scale and
stock paths were not reduced or shifted to hide this limit.
