# Tideland oil wells and refinery

Artwork for the stock land oil chain. Both sets are original, solid 3D
geometry. The completed roles and addresses follow the layout 0 entries in
[OpenTTD 14.1's industry placement table](https://github.com/OpenTTD/OpenTTD/blob/14.1/src/table/build_industry.h)
and [industry drawing table](https://github.com/OpenTTD/OpenTTD/blob/14.1/src/table/industry_land.h).
[OpenGFX's industrial sprite index](https://github.com/OpenTTD/OpenGFX/blob/master/sprites/base/base-2011-industries.pnml)
was used as silhouette reference only. No upstream pixels, meshes, color
palettes, or sprite sheets are included.

The oil wells are on land, not the offshore Oil Rig. The five separate
steel walking-beam pumps have genuine frames, open support spaces, pivot
axles, rounded horseheads, bridle ropes and plungers, eccentric cranks
and paired pitman links, covered gathering drums and bent pipes. The
editable rig runs a periodic 12-pose crank cycle from frames 1 to 49.
Neighboring pumpjacks have different phases. Its mechanical link lengths
stay constant at solved poses; interpolated poses are preview
approximations. Native per-tile OBJ meshes bake frame 1 and do not
currently animate. The component names and axes in `stock_oil_well.blend`
provide attachment points for future native animation without affecting
industry logic.

The refinery has a banded fractionating tower, red steel heat exchanger
frames, paired raised process vessels, a row of separate welded storage
tanks with low bund retaining curbs, two staff control huts, and the
three crude tanker unloading pads. Three raised flare columns are
positioned next to the pads, not across them. They're unlit nozzle
geometry, not source flames or effects. Each receiving pad has a
marked concrete lane, flush spill grate, protected off-lane unloading
station, flow gauge and quick hose coupling. A stable approach is
clear in all three locations. The graphics do not implement a station;
normal adjacent industry catchment and freight operations remain under
the simulation's control.

## Runtime tile contract

```text
Oil Wells #11 layout 0   Oil Refinery #4 layout 0
 z  x=0  1  2             z  x=0  1  2  3
 0   29 29 29             0   20 20 23  .
 1   29  .  .             1   21 19 18 23
 2   29  .  .             2   22 22 18 18
                          3   21 20 18 18
```

- Oil Wells: `bl_industry_oil_well_{x}_{z}.obj`,
  `bl_industry_oil_well_atlas.png`, `art/stock_oil_well.blend`.
- Oil Refinery: `bl_industry_oil_refinery_{x}_{z}.obj`,
  `bl_industry_oil_refinery_atlas.png`, `art/stock_oil_refinery.blend`.
- Asset suffixes are local stock offsets, not GFX indexes. Use only the
  occupied positions shown and leave (3,0) open at the refinery. Place a
  mesh at **the NW node of each logical tile**, at grade+1 with static
  mesh-node scale 1. North is −Z. Cell pitch is two nodes and each mesh
  bounds X/Z within [−0.5, 1.5]; author and artwork use flat physical
  pads. Local ground Y=−0.5, just as in the existing farm/factory kits.
- Only GFX 20 accepts crude Oil. At (0,0) and (1,0) the visually marked
  truck lane opens toward −Z; (1,3) opens toward +Z. Each lane is centered
  at local X=.44 and the clear swept region is [0.168,0.714] X at
  floor-facing heights [0.034,0.433] above grade. The huts on GFX 23 have
  the stock one-eighth passenger acceptance each, not Oil acceptance.

## Reproduce

```sh
blender -b --python-exit-code 1 --python tools/build_stock_oil_well_art.py
blender -b --python-exit-code 1 --python tools/build_stock_oil_refinery_art.py
python3 tests/stock_oil_art.py
blender -b art/stock_oil_well.blend --python-exit-code 1 \
  --python tests/stock_oil_well_blender.py
tests/stock_oil_art_native.sh
```

Use `STOCK_OIL_WELL_RENDER=/path/wells.png` and
`STOCK_OIL_REFINERY_RENDER=/path/refinery.png` for Blender survey previews.
The isolated native fixture records both sites at ground and survey
heights, using the real Witcombe tanker if that separately developed
asset is present. Geometry verification includes conservative collision
checks against the three open trunk approaches, exact footprints/roles,
and atlas and OBJ addressing. There are 22 runtime assets totaling about
580 KiB compressed outside the editable sources.
