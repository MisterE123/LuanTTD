# Dinger 100 and Airtaxi A32

These aircraft follow the YAe46 and A31 in the previously missing
Temperate stock sequence. The base dates come from OpenTTD 16.0-RC1
`src/table/engines.h`; actual public availability uses the seeded calendar.

| Aircraft | RC1 stock ID | Base introduction | Seats / Mail | Airports |
| --- | ---: | --- | ---: | --- |
| Dinger 100 | 238 | 1 January 1986 | 85 / 10 | Country or City |
| Airtaxi A32 | 235 | 1 January 1987 | 160 / 20 | City |

The Dinger's jet sound does not make it a fast-CTOL aircraft. Its stock
conventional runway class is retained. Both aircraft use the existing
independently loaded passenger cabin and Mail bins, paid station service,
and in-flight order state.

The Dinger uses a narrow pressure shell, two rear nacelles with open
intakes, a physically connected T-tail, and six runway-contact tires.
The A32 has a shorter rounded fuselage, swept raked wings, twin
underwing engines and separate original orange-and-cobalt livery.
Each has editable Blender geometry and independent gear-down and
gear-up native meshes. No sprite or external 3D asset is embedded.

- Sources: `stock_dinger_100.blend` and `stock_airtaxi_a32.blend`.
- Generator: `tools/build_stock_dinger_a32_art.py`.
- Tests: exact source table rows, fitted apertures and contact geometry,
  funded paid route plus process restore, real Luanti taxi, takeoff,
  gear-up flight and gear-down arrival.
