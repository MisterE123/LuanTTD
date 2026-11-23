# Stock SH '125' express

Buy the SH '125' from an ordinary rail depot when its stock introduction date
arrives. A single purchase creates two linked power cars in opposite
orientations. Assemble a passenger carriage between them or use the depot's express
offer with one included carriage. Assign two suitable
passenger platforms. The two heads are physical bodies, not a decorative
copy, and either leads on reversal. Only the passenger coaches board
passengers; each power car has its own four-bag Mail hold.

The OpenTTD 16.0-RC1 MM/RVI rows supply the 4,500 hp power pair, separate
body weight, length, 200 stock speed and price/running factors. The physical
pair uses the stock depot normalization and reciprocal links already used
for double-ended stock. The native depot and renderer substitute neither a generic
diesel nor a single stretched model in place of the heads.

The ordinary worker graphical test built track/depot/platforms, bought a
regular depot offer and saw two outward-facing power cars surrounding an
independent coach. The service regression earned fares, reversed and
reloaded with live coach passengers. Test with
tests/rail_owned_service.lua sh_125 and tests/stock_sh_125_native.sh.

The regular rail Mail system also supports a separate #28 Mail Van.
The express heads use the same house Mail allocator and town station
ratings as those vans and road mail trucks. This does not duplicate
production.

## Running the ordinary combined service

The regular worker depot lists **40 seats** and **8 Mail bags** for the
stock paid service. Order two ordinary town platforms. The two linked
heads have separate 4-bag holds, preserving their distinct stock cargo
type and capacity through RC1 `AddRearEngineToMultiheadedTrain`. In
`economy.cpp`, `ReserveConsist` reserves the front then rear linked hold,
then the coach; `LoadUnloadVehicle` visits physical order and settles
one combined payment. Stock Full load all requires both holds **and**
the carriage. When reversing, loading still uses the actual cargo
vehicle tiles and persistent body identities, not the sweeping camera.

`bash tests/stock_sh125_mail_worker_native.sh` bought and dispatched a
real express, saved 4 bags / 13 riders / 2 bags in its independent
bodies, restored by SQLite and paid exactly 40 riders and 8 bags for
$661 on a reciprocal service. This slice does not mount a bare Mail
train without a carriage, multiple coaches, or refit.
