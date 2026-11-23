# Temperate town construction

Every single-tile Temperate house now follows the [OpenTTD 16.0-RC1 draw table](https://github.com/OpenTTD/OpenTTD/blob/16.0-RC1/src/table/town_land.h). This covers 27 stock roots and all 432 combinations of root, two-bit tile hash, and construction phase. The simulation still decides when a plot is built, how its stage advances, and when it counts toward a town's population. The worker only projects those existing fields; no new save fields or randomness are involved.

The 66 new editable sites and native meshes represent the stock layer distinctions:

- When OpenTTD only draws a dirt lot or paved plaza, there is no upper structure. Some lots already have finished verges around an excavation.
- Houses, churches, warehouses, flats, and offices have distinct footings, unfinished walls or exposed frames keyed to their original stage. The modern office stages can have columns or shafts in place before the tower.
- If the source shows an unchanged building on dirt, LuanTTD keeps that building's full 3D shell and leaves off the finished landscaping. If the stock ground and building layers both already match the final stage, the renderer reuses the final mesh. A visually complete house, park, or fountain can therefore appear before its simulation stage completes. The fountain sprays once the basin is actually painted in phase 2.
- The existing four multipart roots still use their common native hotel, mall, and stadium construction footprints. This slice does not add other climate art or import original pixels, palette remaps, or most sprite animations.

The selector follows [DrawTile_Town](https://github.com/OpenTTD/OpenTTD/blob/16.0-RC1/src/town_cmd.cpp): each house ID selects a set of 16 rows; the existing coordinate translation supplies the two-bit hash slot, and the active construction stage indexes within it. Stage silhouettes were studied from [OpenGFX 7.1](https://github.com/OpenTTD/OpenGFX/blob/7.1/sprites/base/base-1440-houses.pnml) and rebuilt with original Blender geometry. Models use the common scenery palette and the same +Z native entrance as finished houses. No artwork from OpenGFX is distributed.

Rebuild and run geometry/selection checks:

```sh
python3 tools/extract_town_house_draw.py /path/to/OpenTTD-16.0-RC1/src/table/town_land.h --check
blender -b -t 2 --python-exit-code 1 --python tools/build_stock_construction_art.py
lua5.1 tests/stock_town_construction.lua
python3 tests/stock_town_construction_art.py
bash tests/campaign_worker_stock_construction_native.sh
```

The graphical test uses an ordinary generated, worker-owned world. It pauses through the regular worker command, reads that durable revision, and checks seven painted native nodes and their real roadside rotations. It captures screen evidence for bare plots, frames, churches or offices, bare-yard finished structures, and visuals that reach the completed appearance before the house clock. Set `TOWN_CONSTRUCTION_YEAR=1985` for a later-era view.
