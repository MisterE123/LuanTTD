# Temperate stock town artwork

There is native artwork for all 31 buildable Temperate town roots in [OpenTTD 16.0-RC1's house table](https://github.com/OpenTTD/OpenTTD/blob/16.0-RC1/src/table/town_land.h). This is artwork coverage, not a claim that every climate, every town-rule branch, every animated sprite effect, or every map seed matches OpenTTD.

Twenty-six editable `town_stock_*.blend` sources were modeled with original geometry and a shared scenery palette. Five established house and shop models remain mapped to their stock identities. The stock catalog still decides the ages and zones that may build each house. No OpenTTD/OpenGFX sprite pixels are distributed here.

The hotel, both stadiums and mall are modeled as continuous landmarks, then clipped at exact tile boundaries into two or four OBJ pieces. This lets the native game project each part across separately loaded worker sectors. Construction has three distinct native stages; the entire footprint is admitted, built, completed and demolished as one building. Single-tile doors use the existing deterministic frontage rule.

Generate assets from Blender:

```sh
blender -b -t 2 --python-exit-code 1 --python tools/build_stock_town_art.py
STOCK_TOWN_IDS="07 14 20 28" STOCK_TOWN_RENDER_ONLY=1 STOCK_TOWN_REVIEW=/tmp/town-landmarks.png \
  blender -b -t 2 --python-exit-code 1 --python tools/build_stock_town_art.py
```

Run the QA passes:

```sh
python3 tests/stock_town_art.py
lua5.1 tests/stock_town_art.lua
bash tests/stock_town_city_native.sh
```

These check editable sources and native footprint, all stock root IDs across 1950/1975/2020 seeds, source dates, shared construction, and a worker-owned native football ground that is cleared from a child tile with one durable charge.
