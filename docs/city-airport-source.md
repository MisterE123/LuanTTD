# City Airport and Darwin 100

In a fresh campaign from **1955** onward, open **Sea & Air → Airfields**,
choose **Build City Airport**, and select the northwest corner of a clear,
level 6×6 area. The stock base price is $21,600 and the modified catchment
extends five tiles past the footprint. Ground routing and all three stands
come from the exact [OpenTTD 16.0-RC1 table](https://github.com/OpenTTD/OpenTTD/blob/07b339c0aaeb0a87be9490b2f1c3f17c6b00b837/src/table/airport_movement.h).
The city buildings, tower, hangar, runway and taxiway are original 3D art;
see [the editable City art source](../art/city_airport.md).

Buy the 170-seat Darwin 100 when its stock design is on sale. It costs
$49,218 at a City hangar and needs two City stops. Small planes can fly
between Country and City; both ground profiles use the exact airport
state table. The commercial regression buys and runs the original Darwin
and settles $4,858 for 340 real passengers across reload; near-field
waiting people use the actual commercial queue, not decorative extras.

The current native 3D version supports one assigned service at a City
Airport. Two full-size Darwins can intersect on the stock taxi path by
the second and third stands; their geometry and the stock paths stay
unchanged. Helicopters, Mail holds, airport noise, and full historical
airport lifecycle rules are not covered.

Run `lua5.1 tests/airport_city_paid.lua` for the replay, and
`python3 tools/build_city_airport_tables.py /path/to/pinned-headers` to
verify the recovered movement and facility data. The verifying folder needs
the exact `airport.h`, `airport_movement.h` and `airport_defaults.h`
from the pinned 16.0-RC1 checkout. For the rendered worker replay run
`bash tests/stock_city_airport_native.sh`.

## Stock City jets

Five OpenTTD 16.0-RC1 fast CTOL aircraft have original 3D art and ordinary,
dated depot offers. They use the same paid aircraft orders and loading:

| Stock aircraft | Passenger seats | Stock Mail specification |
| --- | ---: | ---: |
| FFP Dart (#217) | 90 | 10 |
| Bakewell Luckett LB-8 (#220) | 200 | 30 |
| Yate Aerospace YAC 1-11 (#225) | 95 | 10 |
| Darwin 100 (#226) | 170 | 35 |
| Darwin 300 (#228) | 300 | 50 |

Each has its own stock introduction date, purchase price and running cost.
The separate airborne Mail economy is not implemented. The game currently
requires a City Airport for fast planes. The short-strip risk calculation
is source-verified in isolation, but deliberately not mounted until the
wreck, station-cargo and runway-clearance paths can be verified together.

Run the paid service and state-reload test with a stock ID as the argument
to tests/airport_city_paid.lua. The graphical worker test accepts
LUANTTD_QA_AIRFRAME. The Darwin 300 test proves normal company loans and a
fully paid $82,031 purchase, rather than creating a free aircraft.
