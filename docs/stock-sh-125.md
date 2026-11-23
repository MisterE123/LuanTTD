# Stock SH '125' express

Buy the SH '125' from an ordinary rail depot when its stock introduction date
arrives. A single purchase creates two linked power cars in opposite
orientations. Assemble one or more passenger carriages between them or use
the depot's express offer with one included carriage. Assign two suitable
passenger platforms. The two heads are physical bodies, not a decorative
copy, and either leads on reversal. Only the passenger coaches board
passengers; the four stock Mail capacity of each power car is not counted as
passenger seating.

The OpenTTD 16.0-RC1 MT/RVI rows supply the 4,500 hp power pair, separate
body weight, length, 200 stock speed and price/running factors. The physical
pair uses the stock depot normalization and reciprocal links already used
for double-ended stock. The native depot and renderer substitute neither a generic
diesel nor a single stretched model in place of the heads.

The ordinary worker graphical test built track/depot/platforms, bought a
regular depot offer and saw two outward-facing power cars surrounding an
independent coach. The service regression earned fares, reversed and
reloaded with live coach passengers. Test with
tests/rail_owned_service.lua sh_125 and tests/stock_sh_125_native.sh.

The stock #28 Mail Van source row and original Blender body are staged for
the next pass. Rail Mail shipping (including use of the express heads' mail
holds) is not yet implemented.

The tested shared Mail allocator is groundwork for that next pass. It
compares truck and rail catchments and station ratings in one allocation
of each house's Mail, without duplicating supply. The default road-only
Mail production path remains unchanged until a rail cargo service is
registered.
