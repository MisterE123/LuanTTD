# Cedar Coal, original temperate pithead

`cedar_coal_mine.blend` contains the editable mesh collection for the
pinned OpenTTD 14.1 `_tile_table_coal_mine_0` layout. No OpenTTD artwork
was used. The layout, including the three vacant slots, is also checked
against `openttd/coal_industry.lua`.

| Tile offset | Stock gfx | Original native geometry |
| --- | ---: | --- |
| (0,0) | 5 | Weigh house, flat truck scale, low west apron and signage |
| (1,0) | 6 | Two genuinely open tapered coal screens, in-bin piles, truck and yard conveyor |
| (2,0) | 3 | Main irregular stockpile, loose coal and open yard retaining strips |
| (1,1) | 0 | Open four-post steel headgear, guide cage, seven-spoke winding wheels |
| (1,2) | 2 | Raised/open winding-house door, real hoist drums and cable connections |
| (2,2) | 3 | Low rail transfer bunker and unobstructed east/lower rail-station frontage |

Place `bl_coal_mine_0_{offset_x}_{offset_z}.obj` on the occupied tile's
even native node `(2*x, base+1, 2*z)`. Use
`bl_coal_mine_atlas.png`. The flat deck datum is `base+0.5`. Keep the
ordinary ground or landscape underneath. No art is placed on the
three stock holes. Track, roads and their stop/rail-station facilities
remain separately built and owned by the game.

The standard `..._1_1.obj` has both winding wheels installed. For
runtime animation, substitute `bl_coal_mine_0_1_1_nosheaves.obj` and
add `bl_coal_mine_0_sheaves.obj` as a default-scale mesh entity with
the same atlas. On the **headframe tile**, its shared axle anchor is:

```
X = 2*x + 0.5
Y = base + 0.5 + 2.395
Z = 2*z + 0.5 - 0.080
```

Rotate the entity about its local X axis. The base keeps the fixed
bearings, cables and cage. The fixture turns the assembled wheels and
verifies native entity angles; it does not simulate the mining machinery,
cargo generation or transfer.

```sh
blender -b -t 4 --python-exit-code 1 --python tools/build_coal_mine_art.py
python tests/coal_mine_art.py --lua lua5.1
# Optional pinned header comparison and Blender review:
python tests/coal_mine_art.py --lua lua5.1 --upstream-layout /path/to/14.1/src/table/build_industry.h
COAL_MINE_RENDER=/tmp/cedar-coal.png blender -b -t 4 --python tools/build_coal_mine_art.py
```

The regression checks the occupied positions, exact joints of three
conveyors and the winding cable, the correctly centered separate
wheel geometry, both frontages, and the presence of real bins, coal
lumps, and winding drums. The assets represent the completed layout.
