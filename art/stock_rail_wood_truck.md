# Stock conventional Wood Truck #34

The editable Blender original preserves the stock Temperate Wood Truck's blue open timber carrier, low brown deck, four distinct steel stake pairs, and full-length stacked logs. The unloaded chassis, original plank floor and pegs remain in both poses. Loaded-only geometry includes five separate closed rough pine logs, visibly stepped end-grain rings, and two restrained blue bands; the timber and bands are independently editable. No raster art from other projects is shipped.

[OpenTTD 16.0-RC1 engine table](https://github.com/OpenTTD/OpenTTD/blob/16.0-RC1/src/table/engines.h), [sprite lookup](https://github.com/OpenTTD/OpenTTD/blob/16.0-RC1/src/table/train_sprites.h), [cargo specifications](https://github.com/OpenTTD/OpenTTD/blob/16.0-RC1/src/table/cargo_const.h), and [train image selection](https://github.com/OpenTTD/OpenTTD/blob/16.0-RC1/src/train_cmd.cpp) define conventional #34. Its capacity is 30 t at 16 sixteenths of a ton per unit, tare 16 t, cost factor 181 ($1,414 at the stock base price), zero motive power and no individual speed cap. The nominal length is 8 units, five load units per pulse, base day 1827 (1925-01-01), decay 20, vehicle life 20 years and base market life 50 years. Stock lists it in Temperate, Arctic and Tropic; the ordinary local Forest→Sawmill route is Temperate. Sprite image 40 uses base 2765, four orientations and load adder +24: base 2789 is shown at 15/30 t.

The stock grid [OpenGFX 7.1 wagon graphics mapping](https://github.com/OpenTTD/OpenGFX/blob/7.1/sprites/base/base-2733-rail-vehicles-wagons.pnml) and [Temperate wagon sheet](https://github.com/OpenTTD/OpenGFX/blob/7.1/sprites/png/trains/temperate_railwagons_28px.png) informed the original blue/brown silhouette and load profile. Thanks to the OpenTTD and OpenGFX contributors. No source sprite pixels, palettes, or third-party geometry are shipped.

Assets use native −Z longitudinal nose, tread datum Y=0, gauge X±.212, axle centers Z±.269, drawknuckles centered at Y=.157 and ending at Z±.499, with 1.00-node stock centers and native rail offset .614. The loaded OBJ preserves the complete byte-identical empty shell before its separate log geometry.

In Rail Freight → Timber & Goods trains, designate a Wood loader at a Forest and a Wood receiver at a Sawmill. Assemble a single supported locomotive with the Wood Truck and order Forest first, Sawmill second. A separate station and Goods Van or ordinary truck can collect the sawmill's existing production; the Wood platform is dedicated. Both multi-industry campaigns and the Timber-only scenario use their existing station and receipt ledger.

```sh
blender -b -t 2 --python-exit-code 1 --python tools/build_stock_rail_wood_truck_art.py
python3 tools/build_rail_timber_icons.py
python3 tests/stock_rail_wood_truck_art.py
lua5.1 tests/stock_rail_wood_roster.lua
bash tests/stock_rail_wood_live_native.sh
BAYLINE_WOOD_MIXED=true bash tests/stock_rail_wood_live_native.sh
bash tests/stock_rail_wood_art_native.sh
```
