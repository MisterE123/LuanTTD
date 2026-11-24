# International and Intercontinental Airports

Both are ordinary company airfields under **Airfields → Fixed-wing Airports**. The International Airport appears in 1990 and occupies 7×7 tiles; it has six terminal stands, two helicopter pads, two physical hangars and a catchment radius of eight. The Intercontinental Airport appears in 2002 and occupies 9×11 tiles; it has eight terminal stands, two helicopter pads, two physical hangars and a catchment radius of ten.

Aim at the northwest tile to quote construction. Aim at a hangar building to open that specific hangar for aircraft purchase and dispatch. Stations remain single destinations for orders; their hangars are physically distinct depots. The worker validates the selected hangar tile, resolves the stock depot index, and starts the selected aircraft at that hangar's source coordinates, not at the first building.

The footprint graphics roles, terminal groups, runway blocks and ground movement tables are extracted from [OpenTTD 16.0-RC1](https://github.com/OpenTTD/OpenTTD/tree/16.0-RC1/src/table). The second hangar pose follows [GetVehiclePosOnBuild and CmdBuildAircraft](https://github.com/OpenTTD/OpenTTD/blob/16.0-RC1/src/aircraft_cmd.cpp). The [Blender source](../art/hub_airport_parts.blend) supplies original models for the new runway ends, apron stands and fences, service buildings, pads and radar. Common building and runway roles reuse original LuanTTD models.

Checks:
- [Physical hangar offsets](../tests/airport_hub_hangars_rc1.lua) and both exact flight boards, including round trips to City Airport from the second hub hangar.
- [Paid worker transaction test](../tests/airport_hub_paid.lua): separate ownership and correct purchase tile, distinct roster, dispatch by vehicle ID, paid mixed-hub service and source catchment.
- [Graphical Luanti test](../tests/stock_city_airport_native.sh): normal hotbar entry, every tile rendered, Yate YAe46 purchased at Hangar 2, taxi, takeoff, landing and continued travel after restarting SQLite, for both airport types.

Stock fleet expansion, local authority noise, airport station joins/upgrade rules, platform-dependent rotorcraft mixes and animated radar remain separate parity work. Shipped hub art and source schedules do not imply every possible mixed fleet is supported.
