# Stock conventional Armoured Van #37

This original editable Blender wagon reproduces the basic appearance of the small closed blue Temperate armoured van. Its rolled steel shell, double door, lock guard, pressed channels, rivets and roof vents are original, individually editable geometry. The native mesh and palette are derived from that Blender project and the same rail-gauge helpers as the Iron Ore Hopper and Steel Truck.

Exact stock conventional rail data: OpenTTD 16.0-RC1 [engine and wagon tables](https://github.com/OpenTTD/OpenTTD/blob/16.0-RC1/src/table/engines.h), [sprite dispatch tables](https://github.com/OpenTTD/OpenTTD/blob/16.0-RC1/src/table/train_sprites.h), [capacity and weight](https://github.com/OpenTTD/OpenTTD/blob/16.0-RC1/src/table/cargo_const.h), and [train image selection](https://github.com/OpenTTD/OpenTTD/blob/16.0-RC1/src/train_cmd.cpp). The #37 has 30 t tare, 20 bags of Valuables at 2/16 t each, price factor 255 ($1,992 at stock base prices), 5 bags per load pulse, 8 nominal length units, no power or wagon speed cap. Its stock base introduction is day 1827 (1925-01-01), decay 20, vehicle life 20 years and base market life 50 years. Stock enumerates the conventional wagon in Temperate/Arctic/Tropic; the live Bank service is Temperate only. Sprite image 43 uses base 2777 with a 3 direction mask, zero direction adder and **zero load adder**: the van remains visibly closed when loaded.

The OpenGFX 7.1 [wagon graphics mapping](https://github.com/OpenTTD/OpenGFX/blob/7.1/sprites/base/base-2733-rail-vehicles-wagons.pnml) explicitly maps sprite 2777 to the same design both empty and full; the [Temperate wagon sheet](https://github.com/OpenTTD/OpenGFX/blob/7.1/sprites/png/trains/temperate_railwagons_28px.png) was consulted for the closed blue body, relatively flat rolled roof and centered grey doors. Thanks to the OpenTTD and OpenGFX contributors. No source sprite pixels, texture palettes, or third-party geometry from those sources are shipped.

The native wagon uses unit scale, longitudinal nose −Z, tread at Y=0 on rail surface base +.614, gauge ±.212, axle centers Z ±.269, knuckle center Y .157, tip Z ±.499. The buy menu requires a live mounted Bank rail service and the actual mesh and texture. In Rail Freight → Bank trains, designate a loading platform in one Bank's catchment then a delivery platform in a different Bank's catchment. The catchments must not share a Bank. As with the existing dedicated rail freight services, the ordinary live route is one supported locomotive and one wagon per dedicated cargo controller.

Build and test:

```sh
blender -b -t 2 --python-exit-code 1 --python tools/build_stock_rail_armoured_van.py
python3 tools/build_rail_bank_icons.py
python3 tests/stock_rail_armoured_van_art.py
lua5.1 tests/stock_rail_valuables_roster.lua
bash tests/stock_rail_valuables_live_native.sh
```
