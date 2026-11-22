# Original Terrain Exploration (read-only)

A separate native Luanti world mode, with real OpenTTD 14.1 Original
temperate geography. It makes no company or transport simulation. The
default region is 64×64 stock tiles, seed 1751, terrain type 3, sea
value 0 and freeform edges. Each power-of-two axis can be chosen
independently from 64 through 4096. The whole selected rectangle,
including its unplayable outer tiles, uses real stock heights and
water classification, without procedural padding. This is the initial source terrain, before rivers, towns, vegetation,
rough-ground or industries are added.

## Configure a separate world

Create a new world and choose **Original Terrain Survey**. Choose
the side length and seed in the setup screen. The packed height base
is generated at startup; Luanti builds scene mapblocks near viewers.

Before launch, put the verified mask bank named `original-mapgen.bin`
inside that world's folder. It is a local numeric input, not project
art. Use your local OpenGFX 7.1 installation to prepare it:

```sh
python3 tools/extract_original_terrain_masks.py /path/to/ogfxi_logos.grf /path/to/new-world/original-mapgen.bin
```

The extractor refuses overwrite and only accepts the pinned OpenGFX 7.1
GRF. The startup gate independently verifies the mask bank SHA-256.
No GRF, masks, pre-generated map, or screenshots from external assets
are distributed with the game. See [Original terrain source provenance](original-terrain.md).

The survey is a read-only world type, not a company campaign.
The setup screen checks for the verified local mask bank.

## Fly the map

Use mouse look and **WASD** to fly horizontally, **Space** to rise,
**Shift** to descend, and **E** to move faster. The flight controller
keeps the camera above the true terrain surface and in stock playable
bounds. It does not require changing player privileges. The HUD shows
the underlying tile type, coordinates and terrain height.

- `/terrain coast` starts offshore with a close shore view.
- `/terrain transect` faces east across the two neighboring source
  chunk borders at x=17 and x=25 on the default size/seed. On another
  board it starts near the center. Hold **W** to cross both seams.
- `/terrain summit` overlooks the high ridge.
- `/terrain tile X Z` goes to a playable tile (each coordinate from 2
  through the respective dimension minus 1).
- `/terrain inspect` reports exact source slope and height at your tile.

All exploration terrain is non-diggable, protected, and has no
simulated inventory, transport tools, or company UI. The usual map
database records terrain already generated and Luanti still saves normal
client state such as player accounts.

## Native geometry, memory and proof

The adapter only processes actual Luanti mapblocks requested by the
engine. It uses one 8×8 source chunk cache, and each 16-node mapgen page
can use at most four detached source chunks. Each tile's 3D mesh follows
the shared OpenTTD corner heights. At sea the water surface is a separate
horizontal mesh; on shore it is clipped against the actual terrain
planes with a small visual depth offset. The dry/shingle split only
changes material, not shape. The physical source sea level remains 0.
There is no flat image pretending to be landscape, no water flowing
uphill, and no world allocation for scenery outside the selected bounds.

The native Linux test uses a disposable game with the same bootstrap:

```sh
python3 tools/build_original_coast_art.py --check
python3 tests/original_terrain_coast_geometry.py
lua5.1 tests/original_terrain_explorer_gate.lua
tests/original_terrain_explorer_native.sh /path/to/ogfxi_logos.grf /path/to/private/new-evidence
```

It verifies all 4,096 native tile anchors (2,246 land, 1,292 sea,
306 shore, and 252 void), continuous interpolation across two neighboring
seams, the four-source-chunk ceiling, read-only mode, and identical
board contents after a SQLite process restart. In the visual client
the test uses the real flight controls to cross both seams and captures
the coast, each stage of the transect, and summit. Its logs and
screenshots stay in the private evidence folder. The same native
probe uses bounded disjoint samples for larger shapes and verifies
the actual slope/shore meshes, streamed flight and SQLite restore.
It does not claim full generated-world gameplay or simulation parity.
