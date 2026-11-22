# Ferry buoys (OpenTTD 14.1)

The Harbor builds a neutral buoy on one open, level, uncovered water tile for
$350; clearing it costs $50. The water stays navigable. Sea, river and canal
keep their previous water class, ownership, and geometry. The buoy is an
optional waypoint, not a dock: no catchment, passengers, loading or fare.

Select it as an optional via for the passenger ferry. The depot leg goes to
the first dock; both legs between the docks repeat via the buoy. Stock ship
YAPF targets the exact buoy tile. As in OpenTTD, on an ordinary in-tile motion
step within Manhattan distance three, the ship advances the order without
stopping. The successor order is processed next tick. It sails to the next
real dock, including the ordinary reversal and region route rules. The two
docks' delivery and finance are unchanged.

This preview supports one optional buoy in the single passenger shuttle,
not editing other ship orders or replacing a waypoint during service. A buoy
in a running ferry's orders cannot be cleared, even by that ferry's owner.
Stock checks other companies' orders and has a fuller order-list lifecycle.
Here, withdraw the ferry first; no active order is silently dropped. A hull
on the tile also blocks clearing. Existing unrelated buoys can be removed
while a ferry is operating. Open flat sea, river, and canal only: the host
does not auto-clear any facility or overhead crossing.

Sources: original 14.1 `src/waypoint_cmd.cpp` (`CmdBuildBuoy` and
`RemoveBuoy`), `src/station_map.h` (`MakeBuoy`), `src/water_cmd.cpp`
(`MakeWaterKeepingClass` on unchanged ordinary flat water), `src/ship_cmd.cpp`
(`ShipController`) and `src/table/pricebase.h`.

Verify on Linux:

```sh
lua5.1 tests/ship_network.lua
lua5.1 tests/ship_motion.lua
lua5.1 tests/ship_preview_run.lua buoy
lua5.1 tests/ship_paid_runtime.lua buoy
python3 tests/ship_buoy_upstream.py /path/to/openttd-14.1
```

The motion fixture saves on the exact dummy-order boundary. The paid fixture
saves before the buoy, during passenger loading, and after the first fare.
It requires repeated nonzero-speed passes at distance exactly three and
actual paid deliveries only at the two real docks after reload.
The differential compiles the pinned original `CmdBuildBuoy` and compares
1,536 quotes, including the stock conditional automatic clear and prices.
