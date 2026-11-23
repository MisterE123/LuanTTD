# Temperate stock town artwork

There is native artwork for all 31 buildable Temperate town roots in [OpenTTD 16.0-RC1's house table](https://github.com/OpenTTD/OpenTTD/blob/16.0-RC1/src/table/town_land.h). This is artwork coverage, not a claim that every climate, every town-rule branch, every animated sprite effect, or every map seed matches OpenTTD.

There are 38 editable original Blender scenes for the 31 stock roots, including 12 completed town-house, cottage, detached house, and shop/office looks that replace the five former shared models. The original house table still controls construction years and zones. For the five rebuilt roots, the native renderer follows the visual slots in [the stock drawing table](https://github.com/OpenTTD/OpenTTD/blob/16.0-RC1/src/table/town_land.h) and [DrawTile_Town](https://github.com/OpenTTD/OpenTTD/blob/16.0-RC1/src/town_cmd.cpp), with [TileHash2Bit](https://github.com/OpenTTD/OpenTTD/blob/16.0-RC1/src/tile_map.h) taking zero-based pixel coordinates translated from our one-based tile coordinates. The visual choice neither writes a save field nor consumes simulation RNG. Road-facing doors retain LuanTTD's 3D frontage behavior.

| Stock root | Stock stage-3 sprite keys by hash slot 0–3 | Original 3D models |
|---|---|---|
| 06 Town houses | 1446 / 1446 / 1506 / 1506 | Brown tile brick gable and a low pair of hipped slate roofs |
| 0E Shops and offices | 1463 in all four slots | Brick street block, tiled shopfront, twin rooftop parapets and glazing |
| 18 Old houses | 1492 / 1494 / 1488 / 1490 | Low brick with a side workshop, limestone cottage, tall clay roof house and grey masonry annex |
| 19 Cottages | 1496 in all four slots | Sandstone cottage, projecting entrance and open picket fencing |
| 1A Houses | 1500 / 1575 / 1512 / 1518 | Gold cross roof, slate hip, red twin gables and ochre entry wing |

The silhouettes and roof forms were studied from [OpenGFX 7.1's house sprites](https://github.com/OpenTTD/OpenGFX/blob/7.1/sprites/base/base-1440-houses.pnml) and rebuilt from separate geometry with the shared original scenery palette. No OpenTTD or OpenGFX images, geometry, or geotextures are distributed here.

The hotel, both stadiums and mall are modeled as continuous landmarks, then clipped at exact tile boundaries into two or four OBJ pieces. This lets the native game project each part across separately loaded worker sectors. Construction has three distinct native stages; the entire footprint is admitted, built, completed and demolished as one building. Single-tile doors use the existing deterministic frontage rule. Their [stock construction appearances](stock_temperate_construction.md) use the same road-facing orientation. The football and athletics entrances use raised Blender lettering, with an export-only handedness correction so both halves of each sign read correctly from the street.

Generate assets from Blender:

```sh
blender -b -t 2 --python-exit-code 1 --python tools/build_stock_town_art.py
blender -b -t 2 --python-exit-code 1 --python tools/build_stock_residential_art.py
STOCK_TOWN_IDS="07 14 20 28" STOCK_TOWN_RENDER_ONLY=1 STOCK_TOWN_REVIEW=/tmp/town-landmarks.png \
  blender -b -t 2 --python-exit-code 1 --python tools/build_stock_town_art.py
```

Run the QA passes:

```sh
python3 tests/stock_town_art.py
lua5.1 tests/stock_town_art.lua
bash tests/stock_town_city_native.sh
bash tests/campaign_worker_stock_residential_native.sh
```

These check all editable sources and native footprints, all stock root IDs and all 12 new completed looks across 1950/1975/2020 seeds, the independent source-coordinate hash, source dates, shared construction, and durable demolition of a worker-owned football ground. The visual test opens an ordinary generated town in the graphical client, points at each present look, asserts the worker-projected mesh and frontage, and saves street-side screenshots. It needs Luanti, Xvfb, a C compiler, and either ImageMagick `import` or `magick-im7.q16` to take screenshots.
