# Balogh Goods Truck

Original LuanTTD 3D model for the early covered goods lorry available in
OpenTTD's 1950 temperate road depot. This is **Balogh Goods Truck**, not
the coal tipper and not the generic legacy truck: global engine **138**,
road row **22**, road image index **5** in pinned OpenTTD 14.1
[`src/table/engines.h`](https://github.com/OpenTTD/OpenTTD/blob/14.1/src/table/engines.h).
It has the stock general goods capacity 14, introduction baseline day
5479 after 1920-01-01, cost factor 107, running cost factor 90, raw
speed 96, raw quarter-ton weight 38, and 120 hp. Art does not set
simulation values.

## Art reference and provenance

The original shape takes the color blocking and cargo treatment of the
[OpenGFX](https://github.com/OpenTTD/OpenGFX) 7.1 DOS-palette 8bpp depot
screen: light company-blue cab and blue lower cargo sides below a dark
cover. The edited colors are project-original slate blue, charcoal
canvas and muted nickel, not sampled sprite pixels or a retro sprite
wrapped around a box. The conventional bonnet, folded front wings and
separate wheel arches take loose period cues from the
[Midland & Great Northern Joint Railway Society's 1946 Austin K2](https://www.mandgn.org/post/1946-austin-k2-to-join-collection).
All geometry, letterforms, period plate, cloth folds and colors were
created from scratch. No OpenGFX image, source file, historic photo or
proprietary original was imported.

The charcoal cover is clothed over modeled curved hoops with individual
rack ribs, visible tie-down cords, pleated rear canvas and closed lower
double tailgate. It stays closed. The stock
[`_roadveh_full_adder`](https://github.com/OpenTTD/OpenTTD/blob/14.1/src/roadveh_cmd.cpp)
entry for image 5 is 0, so this lorry uses the same appearance loaded
or unloaded. The genuine cargo compartment is modeled beneath the
closed cover and not a visible exposed load. The split windshield,
wiper blades, wheels, brake hardware, raised grille, mirrors, lamps,
fuel box, running board and nameplates are geometry.

## Runtime mount

- `bl_balogh_goods_truck.obj`, palette `bl_balogh_goods_truck_atlas.png`.
  Standard mesh entity; 10 OBJ units per native unit, **.42** uniform
  `visual_size`; nominal −Z nose and local Y=0 at tire contact.
- Runtime-scaled width × height × length = **.2495 × .2855 × .6560** nodes.
  Each wheel meets the same floor datum. At standard .155 road lane
  offset, the maximum width still stays on one side of the road center
  and inside the asphalt. Use the existing surface placement convention
  and right-hand/town-side projection, not a separate visual lane.
- `balogh_goods_truck.blend` contains the editable meshes, materials and
  two-view review scene. This change does not add a purchasable vehicle,
  dispatch, freight economy, UI, or suspension animation.

## Regeneration and QA

```sh
BALOGH_GOODS_RENDER=/tmp/goods.png blender -b -t 4 --python-exit-code 1 --python tools/build_balogh_goods_truck_art.py
LUA=/tmp/bayline-run/usr/bin/lua5.1 python tests/balogh_goods_truck_art.py \
  --upstream-engines /tmp/bayline-ott-src/engines.h \
  --upstream-roadveh /tmp/bayline-ott-src/roadveh_cmd.cpp
BAYLINE_NATIVE_TOOLS=/tmp/bayline-run BAYLINE_NATIVE_TCP=1 bash tests/balogh_goods_truck_art_native.sh
```

The offsets/dimensions tests use the actual OBJ. Source motion samples
check conservative full-vehicle overlap and the real tire contact patch
through the six freight stops, both traffic sides, and the compact
street turns. The isolated native Linux fixture shows the exact asset at
tire contact, with opposing-lane coal traffic, and on the tight stock
turn. No existing save or game connection is changed.
