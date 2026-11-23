# Darwin twinjets

The remaining classic Darwin twinjets are available for paid City Airport
service when introduced by the stock calendar. They use the existing
stock terrain, airport movement tables, route orders, cabin loads,
company charges and save state.

| Airframe | Stock ID | Passengers | Mail | Base purchase |
|---|---:|---:|---:|---:|
| Darwin 200 | 227 | 110 | 15 | $46,484 |
| Darwin 400 | 229 | 200 | 25 | $49,218 |
| Darwin 500 | 230 | 240 | 25 | $51,953 |
| Darwin 600 | 231 | 260 | 40 | $73,828 |

Engine dates and technical data are transcribed from
[OpenTTD 16.0-RC1's engine table](https://github.com/OpenTTD/OpenTTD/blob/16.0-RC1/src/table/engines.h).
In that release all four use image 4; the
[OpenTTD art guide](https://wiki.openttd.org/en/Archive/Old%2032bpp/32bpp%20graphics%20development%20tracker#aircraft)
distinguishes their compact early twinjet, stretch narrow-body and two
wide-body forms. The 3D assets are original designs with invented
liveries, editable Blender geometry, modeled intakes and real wheels,
including the 600's three-axle main bogies. No original sprite pixels or
manufacturer logos are embedded. Gear is retracted in Luanti's airborne
view; this is a 3D visual choice, not a change to stock flight physics.

Do not substitute a different airframe when a required model or texture
is absent. The native manifest only enables complete working bundles.
These aircraft use paved City Airports and the existing single-airframe
dispatch envelope; they do not expand the qualified shared-airport fleet.

```sh
blender -b -t 2 --python-exit-code 1 --python tools/build_stock_darwin_family_art.py
python3 tests/darwin_family_art.py
for id in 227 229 230 231; do lua5.1 tests/airport_city_paid.lua "$id"; done
LUANTTD_QA_AIRFRAME=231 LUANTTD_QA_AIR_YEAR=2000 LUANTTD_QA_AIR_RESTART=1 \
  bash tests/stock_city_airport_native.sh
```

The geometry test can also consume the original City runway and movement
tables and the native pose trace from `tests/darwin_city_art_trace.lua`.
It checks wheel contact on the actual exported runway, and height-sliced
clearance through all three stock terminal turns and the hangar return.
