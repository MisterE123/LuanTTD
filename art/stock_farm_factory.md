# Highfield Farm and Westfield Factory

Two original editable 3D industries for the temperate grain, livestock and
goods chain. These are graphics, not changes to industry production,
catchment, cargo transfer, or dispatch.

The footprints and completed tile roles use the default layout 0 of
[OpenTTD 14.1's industry placement tables](https://github.com/OpenTTD/OpenTTD/blob/14.1/src/table/build_industry.h)
and [industry drawing tables](https://github.com/OpenTTD/OpenTTD/blob/14.1/src/table/industry_land.h).
[OpenGFX's freely available industry sheets](https://github.com/OpenTTD/OpenGFX/blob/master/sprites/base/base-2011-industries.pnml)
were inspected for broad silhouettes only. No artwork, texture pixels,
or projected sprites from upstream are included in the kits.

## Runtime tile contract

One mesh per occupied map tile. `{x}_{z}` preserves the stock offsets in the
layout, not the GFX index; repeated GFX may have cell-specific detail and
continuous seams. Place at the **north-west native node of the logical tile**,
two native nodes apart along X and Z. The foundation top is local Y=−0.5
at placement height of grade+1, matching the coal power station convention.
Authored horizontal mesh bounds in native node units are −0.5 to 1.5 along
its two axes from each placed node. The grass datum is +0.5 above the
ground node center. These are meshes for leveled sites, not automatic ramps
or foundations for arbitrary slopes.

```text
Farm #9 / layout 0      Factory #6 / layout 0
 z  x=0  1  2            z  x=0  1  2  3
 0   37 33 35            0   39 41  .  .
 1   37 34 38            1   40 42 39 41
 2   36 36 38            2   39 41 40 42
                         3   40 42  .  .
```

- Farm: `bl_industry_farm_{x}_{z}.obj`,
  `bl_industry_farm_atlas.png`, `art/stock_temperate_farm.blend`.
  Open-sided annexes, double barn and farmhouse, two zinc silo banks with
  inspection ladders and grain spouts, cattle sorting corral, and fenced
  paddocks with water and individually modeled stock. Three cattle and two
  pigs wander and pause separately inside the pens in the nearby native
  view. Their standing and walking poses are editable in the same Blender
  source, and are exported separately from the fixed farm mesh. They
  don't affect livestock cargo or the industry's simulation.
  A swept cart approach touches the north and south edges without
  placing road tiles outside the stock footprint.
- Factory: `bl_industry_factory_{x}_{z}.obj`,
  `bl_industry_factory_atlas.png`, `art/stock_temperate_factory.blend`.
  Three staggered production and dispatch bays with reddish masonry,
  separate blue standing-seam roofs, freight elevator towers, six hollow
  exhaust stacks, glazed workshops, open loading doors, covered dispatch
  docks, goods pallets and marked paved truck aprons. Leave the four missing
  cells empty; don't place the factory on a padded 4×4 foundation.
  Three yard tiles have a clear east edge where an independently owned
  station can adjoin. No decorative road pretends to be a station.

## Reproduce and verify

```sh
blender -b --python-exit-code 1 --python tools/build_stock_farm_art.py
blender -b --python-exit-code 1 --python tools/build_stock_factory_art.py
python3 tests/stock_farm_factory_art.py
lua5.1 tests/farm_livestock_view.lua
tests/stock_farm_factory_native.sh
```

`STOCK_FARM_RENDER=/absolute/preview.png` and `STOCK_FACTORY_RENDER=…`
optionally generate Blender survey previews. The geometry test checks exact
stock addresses, per-cell role, atlas/UV agreement, face references, and
factory approach headroom. It also measures compressed runtime size apart
from editable sources. The separate native fixture opens Luanti and captures
survey and ground-level views of both sites, including a real goods vehicle
on a factory apron. No external services or prior world saves are required.
