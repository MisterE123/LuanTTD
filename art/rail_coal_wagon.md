# Coal Truck #29

This is LuanTTD's original model for the **Coal Truck**, vehicle 29 in
pinned OpenTTD 14.1. `rail_coal_wagon.blend` contains editable original
empty and loaded collections with a paired studio scene. The mineral
wagon is made from separately modeled rolled steel edges, side and end
drop doors, recessed floor, wheelsets, W-irons, suspension leaves,
handbrake links, buffer castings and matched knuckles. The empty model
has a genuinely open bin; the full model adds an irregular three-lobed
coal load and individual fragments, not a flat black top.

The original gray/bauxite livery and `CEDAR` / `29` stencils are newly
modeled designs. The silhouette takes cues from midcentury British
steel mineral wagons. See the
[National Railway Museum's Wolverton works drawings index](https://www.railwaymuseum.org.uk/sites/default/files/2018-07/Wolverton-Archive-Carriage-Wagon-Drawings-List-WOLV_3_2.pdf)
for welded and riveted short steel mineral wagon precedents.
The Blender shapes, lettering and palette were authored from scratch.
No OpenTTD, proprietary, or historical raster or geometry was imported.

## Roster and mount

Pinned `src/table/engines.h` identifies vehicle 29 as a conventional
rail wagon, 18 t tare, capacity 30 coal, acquisition factor 176, no
power and no wagon speed cap, available in temperate and sub-arctic
climates. It has the stock full length of eight vehicle units.
The historic precedent is visual, not a change to those numbers.

- Assets: `bl_rail_coal_wagon_empty.obj`,
  `bl_rail_coal_wagon_loaded.obj`. Both use
  `bl_rail_coal_wagon_atlas.png`. Use an ordinary Luanti mesh entity
  with X/Y/Z visual scale **1.0**; no legacy Z shrink or extra Y offset.
- Mount at rail crown Y `base+.614` (or evaluated span level + .614),
  center of the stock track, nominal local −Z nose. The two running
  axles are at Z ±.269, with exact .424 gauge; both cars present
  identical wheel/body/coupler geometry and origin. Drawing the full
  state is an in-place mesh swap, not a second wagon.
- Both knuckles stop at Z ±.499, centered at Y .157 above rail crown,
  giving .002 straight clearance to the Kirby Paul Tank at 1.000-node
  center spacing. Maximum half-width .258; empty rim is .447 above rail,
  full coal peak is .528. The actual load is inside the rolled rim in
  X/Z. This fits all ordinary coal stage variants, including beneath
  the loader and inside the receiver's rotary cradle.
- The wagon supplies two cargo display states; stock loading progress
  and when to choose the full asset are runtime decisions. This art
  change does not animate discharge, couplers or revolving wheelsets.

## Rebuild and verify

```sh
RAIL_COAL_WAGON_RENDER=/tmp/coal-wagon.png blender -b -t 4 --python-exit-code 1 --python tools/build_rail_coal_wagon_art.py
python tests/rail_coal_wagon_art.py
python tests/rail_coal_wagon_art.py --upstream-engines /tmp/bayline-ott-src/engines.h
BAYLINE_STOCK_COAL_WAGON_NATIVE=1 BAYLINE_NATIVE_TOOLS=/tmp/bayline-run BAYLINE_NATIVE_TCP=1 bash tests/rail_coal_stage_art_native.sh
```

The structural check uses the actual exports to compare the complete
shells, empty-bed volume, wheel flange and railhead contact on stock
straights and curves, the Kirby drawgear, and the genuine stage
clearances. The native Linux fixture loads both models next to actual
mine, receiving plant and Kirby assets, then changes the model in
place without moving its wheelsets or couplers.
