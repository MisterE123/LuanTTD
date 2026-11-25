# Stock airport council approval

The default is the same as OpenTTD 16.0-RC1: each town allows up to two
non-oil-rig airports when noise limits are off. Permissive councils waive that
number cap. At other council settings, a company rated Very Poor (−200) or
worse cannot build a new station within the standard local-authority range.

To use OpenTTD's alternate rule, set **Limit airports by town noise instead of
airport count** in Luanti's game settings (server setting
`luanttd_station_noise_level = true`). This is not a switch to enable airfields.
The airport build preview reports the existing and proposed noise for the
affected town, and **Local Authority** reports the live budget. A large airport
may fit when it is farther out, and a town can allow more than two quiet
airports. Removing an airport releases its share immediately.

The relevant town is measured to the closest occupied airport perimeter tile;
that can differ from the town associated with the station's build origin.
An equal distance is resolved by the lower town ID. The original distance
falloff, nine buildable airport noise values, population limits and council
tolerance are from [RC1 station_cmd.cpp](https://github.com/OpenTTD/OpenTTD/blob/16.0-RC1/src/station_cmd.cpp#L2514-L2707),
[airport_defaults.h](https://github.com/OpenTTD/OpenTTD/blob/16.0-RC1/src/table/airport_defaults.h#L367-L377)
and [Town::MaxTownNoise](https://github.com/OpenTTD/OpenTTD/blob/16.0-RC1/src/town.h#L218-L230).
Neutral oil rigs are excluded. Totals are derived from authoritative saved
airport footprints, not from loaded terrain or the UI. This scope does not add
cross-mode station joins or change which sites can be leveled or cleared.

[Compiled comparisons](../tests/airport_noise_upstream.py) exercise 36,288
combinations. The [graphical worker replay](../tests/airport_noise_native.lua)
uses an ordinary generated town, buys enough heliports to reach its limit,
verifies a refused quote, opens the actual council panel, then verifies that
demolition, replacement and relaunch preserve the correct total.
