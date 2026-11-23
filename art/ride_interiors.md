# First-person transit interiors

Three original, editable scenes in [ride_interiors.blend](ride_interiors.blend):
a cream-and-green bus with oxblood seats and a driver's console, a varnished
railway coach with blue upholstery and brass luggage racks, and a small steam
cab with boiler, sight windows, pressure dials, handbrake and controls.
Seats, mouldings, sills and window posts are solid geometry. The windows are
openings, not textures; the ground, scenery and traffic seen through them are
from the actual game. No OpenTTD sprites, textures, or proprietary references
are used here.

The geometry and atlas are reproducible from original sources in this repo:

```sh
python3 tools/build_ride_interiors.py
blender -b -t 2 --python tools/build_ride_vehicles_blender.py
python3 tests/ride_interior_art.py
```

The Blender collection separates panel, frame, seat and hardware parts with
named editable materials. The Blender file is the nominal body scale.
The game's exported presentation geometry is enlarged about its eye so its
nearest faces stay outside Luanti's clipping plane. This preserves the cabin's
angular scale and must not be used as collision or drawn for bystanders.

Local presentation coordinates are +X right, +Y up and +Z forward. Game OBJ
units are 10 times world node units with X mirrored for Luanti's OBJ loader.
Use mesh and RGB atlas together at entity `visual_size=1` (no extra scaling).
The nominal local origin is the center of the existing vehicle body at the
given floor elevation. For current exterior models that face −Z, add π to
their presentation yaw.

| Interior mesh/atlas basename | Origin Y above exterior body origin | Local eye (X, Y, Z) |
| --- | ---: | --- |
| `bl_ride_bus_interior` | 0.071 | −0.020, 0.117, −0.042 |
| `bl_ride_train_interior` | 0.202 | −0.091, 0.207, −0.080 |
| `bl_ride_train_cab` | 0.247 | 0.075, 0.228, −0.228 |

`tests/ride_interior_art.py` checks byte-stable exports, assets' outward winding,
asset budget, and real openings in four horizontal directions starting at each
seat. `tests/ride_interior_art_native.sh` is a Linux Luanti visual probe that
takes first-person front and side screenshots in a disposable scene; it does
not exercise travel or ride controls.
