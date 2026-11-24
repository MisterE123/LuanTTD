# Early wide-body jets: Guru Galaxy and Airtaxi A21

Exact source: OpenTTD 16.0-RC1, commit `07b339c`, `src/table/engines.h` MA
#232/#233 and AVI #17/#18. The calendar uses the original date seeds;
the date below is the base date, not a promise of that day's public offer.

| Engine | Base introduction | Passenger seats | Mail | Cost before inflation |
| --- | --- | ---: | ---: | ---: |
| Guru Galaxy #232 | 1 April 1969 | 240 | 35 bags | $68,359 |
| Airtaxi A21 #233 | 1 January 1972 | 260 | 30 bags | $54,687 |

These are fast CTOL jets. Buy each in a City Airport hangar when available;
order two City Airports with town catchment. Their independent passenger
and Mail holds use the shared station loading and payment rules.

## Original 3D art

The Galaxy is an early tri-jet with a third open intake carried at the tail
root, a wide pressure shell and turquoise-and-gold livery. The A21 is an
early wide-body twinjet with two forward underwing nacelles, a longer nose
and rust-and-navy livery. The fan recesses, wing lights, axle pairs,
glazing, door outlines and hinges are modeled. The native flight exports
replace only extended landing gear and door skins with the clean profile.

- Editable Blender scenes: `stock_guru_galaxy.blend`, `stock_airtaxi_a21.blend`.
- Export/build: `tools/build_stock_guru_airtaxi_art.py`; the generator shares
  production mesh tools, not third-party art. No original game sprite,
  proprietary livery, manufacturer image, or external geometry is embedded.
- `tests/airport_city_airframes_rc1.py` checks the stock source rows.
  `tests/guru_airtaxi_art.py` checks distinct atlases, true intake recesses,
  the runway contact plane and matching exterior geometry.
- `tests/airport_city_paid.lua 232` and `233` verify offers, both capacities,
  City Airport restrictions, paid service and restore. The normal graphical
  `tests/stock_city_airport_native.sh` verifies real taxi, gear-up flight,
  gear-down arrival and checkpoint recovery for each native model.
