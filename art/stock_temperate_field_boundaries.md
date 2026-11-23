# Highfield crop ground and field boundaries

Original opaque, seamless 64×64 temperate crop materials, six physical
boundary styles on flat and single-grade edges, and optional dimensional
barley and straw. The order of growth and fence silhouettes follows
[OpenTTD 14.1's clear-land display](https://github.com/OpenTTD/OpenTTD/blob/14.1/src/clear_cmd.cpp)
and [OpenGFX's stock field set](https://github.com/OpenTTD/OpenGFX/blob/master/sprites/base/base-4090-farm-fields.pnml)
for guidance only. No upstream pixels are used.

## Ground

For a record whose `ground == "field"`, use `bl_farm_field_{variant}.png`
(0 through 8), north at top, east at right. These materials are opaque.
Furrows have the same periodic centerline in each stage, so the rows meet
across tile boundaries, including while adjacent plots change stage.
`bl_farm_land_{mask}.obj` preserves the exact 19 stock slope mesh shapes,
UVs, and triangle creases, including flat. The only change is a +.004-native
vertical lift to separate the surface from its ordinary ground substrate.
Use the raised mesh at the **north-west node of the logical tile**,
Y=base+1; retain the ordinary floor/soil support underneath. Unmodified
ground meshes have coplanar surfaces and should not draw new crop colors
over existing grass.

Stages 5 and 6 can optionally receive occasional sparse standing barley.
Stage 8 can receive modeled straw bales. The meshes are named
`bl_farm_field_detail_{5,6,8}.obj` and share `bl_farm_fence_atlas.png`.
Instantiate at its flat tile center (NW +.5 in X and Z) with unit scale
and Y at visible ground; do not place these meshes on slopes. Vary
sparsity by stable tile ID rather than generating random art or more cargo.
The terrain surface alone renders all nine crop stages.

## Physical boundary

`bl_farm_fence_{style}_{grade}.obj` uses `bl_farm_fence_atlas.png`, grade 0
for level, 1 for a one-level rise. Style numbering is stock: 1 low leafy
hedge, 2 oak split rail, 3 spaced exposed wood palings and fine wire,
4 high lush hedge, 5 narrow arable hedge, 6 dry-stone wall. The mesh
orientation is native local +X, spans −1 to +1, and comes in individual
small objects with physical rail sections, plants, stones, and posts.
Use entity scale 1 (ten OBJ units per native node), lighted and decorative
(nonphysical; no authority about passability from the art).

For real native endpoint samples `a,b`, place the mesh centered at the
edge midpoint, Y=min(a.y,b.y). Positive rises go along model +X, which
must point toward the higher endpoint. Let direction dx,dz point from
low to high (choose either if equal). Use Luanti entity yaw `atan2(dz,dx)`; +X is 0, +Z is +π/2, −X is π,
and −Z is −π/2. The cross-tile terrain validity rule
limits adjacent corner heights to one native level even on stepped tiles.
Fence directions on a stock record are 0=west (−X edge), 1=south (+Z),
2=east (+X), 3=north (−Z). Art geometry does not invent boundaries where
the record has no fence; never derive a model from an empty world tile.

## Reproduce

```sh
blender -b --python-exit-code 1 --python tools/build_stock_field_art.py
python3 tests/stock_field_art.py
tests/stock_field_art_native.sh
```

The editable mesh source is `art/stock_temperate_field_boundaries.blend`.
The native fixture uses true flat, rising, and steep stock shapes and
records survey, field-edge, and close hillside views. The shape test
checks the raised ground meshes have identical source face topology,
vertical lift only, all nine texture seams and coherent diagonals, and
actual fence geometry fits both supported grades.
