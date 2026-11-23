# Native aircraft Mail hold

Reference: pinned OpenTTD 16.0-RC1.

Pinned OpenTTD 16.0-RC1 sources: `aircraft_cmd.cpp` assigns the stock passenger capacity to the primary air vehicle and stores the stock Mail capacity on its immediately linked `AIR_SHADOW` part at construction; both caches receive the normal stock cargo-age period. This is a cargo compartment of the **same** plane, not a second aircraft, airport slot, render actor, or payout. `table/engines.h` gives 25/4 for Sampson #215 and 65/8 for Coleman #216, and aircraft engine load amount 20. `economy.cpp:GetLoadAmount` uses rounded-up quarter (5) for the non-primary hold, `LoadUnloadVehicle` paces one 20-tick aircraft pulse, and passenger-bearing aircraft under `FullLoadAny` cannot leave on a full Mail hold while the primary passenger compartment is not full. Once passengers are full, Mail need not be full for Full Load Any; Full Load All needs both.

Implement one physical terminal visit and timer using the already shared ordered compartment controller. Both actual compartments share the real terminal tile for destination and feeder distance, but each has independent cargo packets, capacity/slice/age, GoodsEntry rating/acceptance, separate town receipts and optional per-cargo fare breakdown. One payment is assigned to and settled by the plane once. Only stock modeled paid aircraft with a native roster Mail hold mount it automatically; no feature settings. Upgrade a preexisting passenger-only commercial actor between terminal visits without losing onboard packets or altering an in-progress payout. Route all three modes through the existing single house Mail emitter and shared ranking/allocation; no extra emitter and no airport-only production. Use physical airport footprint and existing small/city radius paths.

Proof: compare Full Load Any when only Mail versus only passengers are full and Full Load All with partial Mail; test exact per-compartment load slices and independent feeder shares. Then use the ordinary airport build, buy, order and movement commands in a native worker, real house production/terminal arrival, a competing Mail station, SQLite restart during a partly unloaded pending visit, exact payout/cash, actual 3D aircraft pose remains one aircraft, and existing air and single/mixed rail regressions.

## Verified behavior

An actual Linux Luanti authority worker built two ordinary Country airfields, purchased a Coleman Count #216 from the normal hangar offer, and used ordinary editable Full Load All / No Loading orders, alongside a purchased MPS Mail Truck serving the same houses. The production airframe manifest found its original media. Only one moving #216 actor was projected, with its real terminal location.

Four separate native server processes opened the same durable SQLite world:
1. Saved the Coleman at its terminal with 13 passengers and 2 Mail bags, with two independent age/packet stores.
2. Restored those stores, departed, and staged an unpaid $334 after unloading 20 passengers and 5 Mail bags at the actual destination terminal.
3. Restored that exact pending payment and settled $935 once ($790 for 65 passengers and $145 for 8 bags). Split company and town receipts matched, including road Mail in the shared towns and exact operating cost/cash.
4. Reopened the paid visit and observed no re-credit of the $935 or 73 units.

`lua5.1 tests/stock_aircraft_mail_service.lua` verifies the stock cabin-only Full Load Any exception, both exact compartment slices, one 20-tick pulse and payment, no money on transfer and separate feeder shares, and safe between-visit conversion of a preexisting passenger-only saved aircraft. `lua5.1 tests/shared_mail_station_allocator.lua` feeds one stock house emission to a real road/rail/City Airport catchment calculation, confirming a single split of 6/8/12 bags (26 total). Repeat the full authority proof with `bash tests/stock_aircraft_mail_live_native.sh`; it prints its evidence directory. Airframe refits/new cargo classes and airport construction parity beyond the existing native airfields are out of scope.
