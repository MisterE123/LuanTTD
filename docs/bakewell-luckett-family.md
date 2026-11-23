# Bakewell Luckett jet family

Four stock aircraft extend the ordinary hangar catalogue. The depot offers
them on the stock engine calendar, charges the stock purchase price, and
dispatches them through the existing paid passenger service and airport
movement tables. The purchase, orders, and airframe persist together.

| Aircraft | Stock ID | Passenger capacity | Stock mail parameter | Base purchase | Airfield |
|---|---:|---:|---:|---:|---|
| Bakewell Luckett LB-9 | 221 | 100 | 15 | $46,484 | Country or City |
| Bakewell Luckett LB80 | 222 | 150 | 30 | $49,218 | City |
| Bakewell Luckett LB-10 | 223 | 220 | 40 | $51,953 | City |
| Bakewell Luckett LB-11 | 224 | 230 | 25 | $54,687 | City |

The stock specifications are from
[OpenTTD 16.0-RC1's engine table](https://github.com/OpenTTD/OpenTTD/blob/16.0-RC1/src/table/engines.h).
The LB-9 plays a jet takeoff sound upstream, but has only the `AIR_CTOL`
flag. The other three set `AIR_FAST`. This is why the LB-9 can use the
Country Airport although its real layout is a rear-engined twinjet.
The City-only restriction for fast aircraft and the solo dispatch envelope
are existing LuanTTD limitations; this change doesn't expand runway-sharing,
crash behavior, or mail carriage.

The [OpenTTD air graphics tracker](https://wiki.openttd.org/en/Archive/Old%2032bpp/Air%20Vehicles%20%28New%20Graphics%29)
distinguishes the compact DC-9 and stretched MD-80 forms from the DC-10 and
MD-11 wide-body trijets. The native models take those visual references,
not their pixels: four new Blender files under `art/` have editable
pressure shells, painted liveries, wing surfaces, hollow fan intakes and
working geometry for the deployed wheels. The LB-11 has upturned winglets
and a separate center bogie. Every aircraft exports the same body with
either deployed gear (ground) or closed gear bays (airborne). No third-party
sprite, logo, or mesh is embedded.

```sh
blender -b -t 2 --python-exit-code 1 --python tools/build_stock_bakewell_luckett_art.py
python3 tests/bakewell_luckett_art.py
for id in 221 222 223 224; do lua5.1 tests/airport_city_paid.lua "$id"; done
python3 tests/airport_city_airframes_rc1.py /path/to/OpenTTD-16.0-RC1/src/table/engines.h
```

With native Linux Luanti and Xvfb, pass `LUANTTD_QA_AIRFRAME` and
`LUANTTD_QA_AIR_YEAR` to `tests/stock_city_airport_native.sh` to observe a
real two-airport flight. For the LB-9, set `LUANTTD_QA_AIR_LAYOUT=country`
to exercise the other airfield. Set `LUANTTD_QA_AIR_RESTART=1` to restart the
native server and check that the same purchased aircraft is still flying.
