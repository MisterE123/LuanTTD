# Managed Forest

This is original 3D art for OpenTTD 14.1's ordinary temperate Forest,
industry type 3. The two exact stock layouts have 18 and 23 occupied
tiles. Ordered, deep blue-green conifers echo the 1950 OpenGFX 7.1
view. No OpenGFX pixels or other graphics were imported. Every needle
cluster, raised bough, bent branch, tapered woody stem and ringed log
end is original 3D geometry.

The planted rows use individually scattered four-tree plots, gently
varied height, crooked branch tips, leaf litter and fern relief.
One lightly thinned log transfer landing opens to the east on
`(3,1)` in layout 0 and `(4,1)` in layout 1. That positioning lets
a road or truck stop sit outside the footprint without placing a
model over the road. Both layouts retain ordinary ground in their
real footprint holes. The interchangeable harvested state has
four tapered stumps with genuine cut rings, scattered chips and
a small stack of roundwood. It does not encode a harvest timing rule.

Stock layouts and graphic states come from
[OpenTTD 14.1 `src/table/build_industry.h`](https://github.com/OpenTTD/OpenTTD/blob/14.1/src/table/build_industry.h),
`_tile_table_forest_0`, `_tile_table_forest_1`, and tile gfx 16/17.

## Runtime mount

- Mature mesh `bl_forest_{layout}_{x}_{z}.obj`, where `x,z` are the
  **layout-local offsets**. Shared atlas `bl_forest_atlas.png`.
  Layout 0 occupied offsets: four-by-four block plus (1,4), (2,4).
  Layout 1: five-by-four block plus (1,4), (2,4), (3,4).
- Optional `bl_forest_harvested.obj` replaces the selected mature mesh
  during the stock-looking gfx 17 **visual state**. No position or
  texture change. It is not a second overlay. Regrowth restores the
  original offset-specific asset. Choose harvest timing and persistence
  in the industry code, not a geometry script.
- Mount at even native node `(2*x, base+1, 2*z)` for world board coordinates
  `x,z` on flat foundation/terrain. Keep ordinary terrain underneath;
  the trunks, ground litter and logging landing sit at or above
  `base+.5`. Natural or terrain-specific grades are not baked into the art.
- `managed_forest.blend` includes editable native **all 41 plots**,
  the optional harvested model and a layout-0 studio view.

## Regeneration and evidence

```sh
FOREST_ART_RENDER=/tmp/managed-forest.png blender -b -t 4 --python-exit-code 1 --python tools/build_managed_forest_art.py
python tests/managed_forest_art.py --upstream-layout /tmp/bayline-ott-src/build_industry.h
BAYLINE_NATIVE_TOOLS=/tmp/bayline-run BAYLINE_NATIVE_TCP=1 bash tests/managed_forest_art_native.sh
```

The geometry test checks exact counts and gfx against the pinned header,
all tile boundaries, 70/90 actual sculpted trunks, and the genuine
non-tree harvest state. The native graphics fixture assembles both
stock layouts, changes one mature offset to gfx 17, and shows the
working log landing. It does not change a shipped save or prove wood
production, terrain generation, trade or pickup logic.
