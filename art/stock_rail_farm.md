# Stock conventional Farm and Factory wagons

Two original editable Blender projects preserve the appearance of the stock OpenTTD Temperate rail wagons. The Livestock Van has a dark rolled roof, actual openings between its blue ventilated side/door slats, separate end panels and rolling door hardware. The Grain Hopper is a wide shallow open steel bowl with separate gate control and bracing. Its independently editable golden grain mass and 84 individual husks sit wholly below the hopper lip.

## Stock data and references

[OpenTTD 16.0-RC1 engines and wagons](https://github.com/OpenTTD/OpenTTD/blob/16.0-RC1/src/table/engines.h), [sprite dispatch](https://github.com/OpenTTD/OpenTTD/blob/16.0-RC1/src/table/train_sprites.h), [cargo/weights](https://github.com/OpenTTD/OpenTTD/blob/16.0-RC1/src/table/cargo_const.h), and [train image selection](https://github.com/OpenTTD/OpenTTD/blob/16.0-RC1/src/train_cmd.cpp).

| Conventional Rail stock ID | Tare | Capacity / unit weight | Price factor / stock base price | Sprite image / four-heading base |
|---|---|---|---|---|
| #31 Livestock Van | 20 t | 25 animals / 3⁄16 t each | 192 / $1,500 | 37 / 2749 both empty and loaded |
| #33 Grain Hopper | 19 t | 30 t grain / one t per unit | 182 / $1,421 | 39 / 2761 empty → 2785 at ≥15 t |

Both use eight nominal length units, five cargo units per stock gradual load pulse, no motive power or wagon speed cap, base design day 1827 (1925-01-01), decay 20, 20-year life and 50-year base market life. The stock Livestock Van runs in Temperate/Arctic, the Grain Hopper in Temperate/Arctic/Tropic; these playable Farm→Factory services use the current Temperate world. Both use the existing authority, industry input/output, real station catchment, queues, accounting and clocks.

Thanks to the OpenTTD and OpenGFX contributors. The [OpenGFX 7.1 layout](https://github.com/OpenTTD/OpenGFX/blob/7.1/sprites/base/base-2733-rail-vehicles-wagons.pnml) and [Temperate wagon sheet](https://github.com/OpenTTD/OpenGFX/blob/7.1/sprites/png/trains/temperate_railwagons_28px.png) were consulted for the ventilated dark-roof van and gray open hopper. No original sprite pixels, palettes or outside models are shipped.

Meshes share the usual 1.00 node wagon centers, nose −Z, ±.212 tread gauge at Y=0, belt centers Z±.269, drawknuckle Y=.157 and tips Z±.499. Live projected tread mounting is .614 above the rail surface. The loaded mesh begins with the byte-identical empty hull; no chassis swap or offset is needed.

## Play and verify

In Rail Freight → Farm trains, designate one loading platform at a Farm and one receiving platform at a Factory for each cargo. Use separate stations per cargo. Buy or assemble a supported locomotive with the matching Livestock Van or Grain Hopper at an owned depot, then order loading followed by delivery. You can run both services concurrently. The Factory can then supply Goods through the existing transport flow.

```sh
blender -b -t 2 --python-exit-code 1 --python tools/build_stock_rail_farm_art.py
python3 tools/build_rail_farm_icons.py
python3 tests/stock_rail_farm_art.py
lua5.1 tests/stock_rail_farm_roster.lua
bash tests/stock_rail_farm_live_native.sh
bash tests/stock_rail_farm_art_native.sh
```
