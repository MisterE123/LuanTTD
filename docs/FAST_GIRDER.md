# High-speed steel girder bridge

The OpenTTD 16.0-RC1 catalogue's second steel girder design is stock
bridge **#9**. It becomes available in 1930, accepts **0–2 interior
tiles** (not including the two ramps), and has a stock speed of 256.
The Roadworks and Railway bridge pickers offer it when the span and date
qualify. Its railway variant is currently available on conventional
track; other rail types still use their previously mounted bridge art.

The new welded closed box sections, flanges, fitted service hatches,
edge rails, elastomeric pads and pier assemblies are original 3D work.
The art uses the catalogue entry, material and piece roles in
`src/table/bridge_land.h` as its specification; no sprites or models
from either TTD or OpenTTD were used. The editable Blender collection
library is [fast_girder.blend](../art/fast_girder.blend), and exports are
under `mods/luanttd_core/models` and `textures`.
The road and rail skins share structure but have separate full running
surfaces. Variants include normal and sloped approaches on both axes,
clear spans above another way and pier bases that meet slope or water.

Build in ordinary play: use the road or rail Bridge tool, select two
aligned ramp tiles, choose **High-speed steel girder**, and connect the
outside of each ramp. To upgrade an existing bridge, choose the same
two endpoints. A road vehicle or a train can stay on the bridge during
the replacement; ordinary paths, train reservations and orders remain.
Use Bulldozer for the whole-bridge layer and its quoted removal price.

## Evidence and reproduction

- Exact RC1 style table and availability verified against the 1950
  reference game; source piece and pillar rules compared to LLVM/GCC
  compiled RC1 rules across 54,080 cases.
- `blender -b --python-exit-code 1 --python tools/build_fast_girder_art.py`
  rebuilds road and rail assets from the editable source pipeline.
- `python3 tests/fast_girder_art.py` compares 168 seam profiles in both
  modes, ordinary running surfaces and clear-span/support variants.
- `bash tests/road_bridge_upgrade_native.sh` builds and upgrades through
  the ordinary worker, preserves a live bus and the other way beneath the
  bridge, restarts the process with the vehicle still on the span, and
  watches it finish paying service.
- `bash tests/rail_fast_girder_worker.sh` does the equivalent with a
  two-part working train, including actual paired rail reservations.
- `bash tests/fast_girder_graphical.sh` exercises both mesh choices in
  the real renderer and opens the scene in the native Luanti client.
