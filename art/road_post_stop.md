# Roadside post and light-freight stop

Original, editable Blender architecture for a dedicated road-mail or freight
station. It has a low flagged platform, an open two-aperture brick loading
canopy, a porcelain POST/envelope sign, painted shutters, a sorting ledge,
a letter box, bollards, tied canvas sacks and labelled parcels. The
apertures, roof and cargo are modeled, not painted onto a block. No source
game sprites were used.

Open `road_post_stop.blend` and switch between the **Straight stop** and
**Compact bay stop** scenes. The architectural parts are named, separately
editable meshes with per-part materials. The road and lawn in the
presentation collection are not exported.

## Game geometry

Use `bl_road_post_stop.png` for every OBJ, at the same anchor as the existing
bus shelter: native mesh node `(2*x, road_base+1, 2*z)`. The two-way road
center is `(2*x+.5, road_base+.5, 2*z+.5)`. The platform never protrudes into
the asphalt or its shoulder (all hardscape begins at least .432 native units
from the road center, and shoulders end at .375). The game must still render
the underlying road and its markings independently.

| Asset suffix | Intended terminal |
| --- | --- |
| `straight_0` | Through stop on X road, platform on +Z side (road bits 10). |
| `straight_1` | Through stop on Z road, platform on −X side (road bits 5). |
| `bay_0` | Compact bay with approach from −X (road bits 8), platform on +Z side. |
| `bay_1` | Compact bay with approach from +Z (road bits 4), platform on +X side. |
| `bay_2` | Compact bay with approach from +X (road bits 2), platform on −Z side. |
| `bay_3` | Compact bay with approach from −Z (road bits 1), platform on −X side. |

The bay orientation index is OpenTTD's exterior-facing DiagDirection.
Compact versions are shifted away from the entrance and scaled only along
the road axis. None of the visual meshes implements construction, cargo
or ownership logic.

```sh
blender -b -t 3 --python-exit-code 1 --python tools/build_road_post_stop.py
python3 tests/road_post_stop_art.py

# Optional Blender image of the original straight variant:
ROAD_POST_STOP_RENDER=/tmp/post-stop.png blender -b -t 3 --python-exit-code 1 --python tools/build_road_post_stop.py
```
