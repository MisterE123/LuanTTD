# Live ship and aircraft orders

From a dispatched passenger ferry, Yate cargo ship, oil tanker, or aircraft's vehicle panel,
open **Orders**. Select an owned dock or airfield (or a buoy for a passenger
ferry), then add it. Select an existing row to move it, remove it, or skip
directly to it. The arrow marks the vehicle's current order. A running
service must keep at least two different stations; add a replacement before
removing the old one. The Yate also needs a coal source and a power station.
The initial order picker is still available from the purchase depot.

Paid ship dispatch immediately stores the selected stations as typed orders.
A ferry's chosen buoy is a waypoint on both legs, not a station stop.
Coal and crude-oil routes explicitly start with Full load at the source
and No loading at the receiver. These orders and the cursors exist in a
save made before the player opens **Orders**; the panel only displays
and edits the list.

The list and independent real and implicit cursors use the OpenTTD 16.0-RC1
[order commands](https://github.com/OpenTTD/OpenTTD/blob/16.0-RC1/src/order_cmd.cpp)
and [vehicle cursor rules](https://github.com/OpenTTD/OpenTTD/blob/16.0-RC1/src/vehicle_base.h).
Moving or inserting a row preserves the current order identity. Skip uses
the existing cargo-loading leave operation (releases reserved cargo and
settles deliveries) on the shared simulation tick. Deleting the current
order by itself is not skip: deletion cancels compulsory full loading, while
ordinary loading can finish. A vehicle advances after loading only if the
visited station matches the selected order, as in
[`Vehicle::HandleLoading`](https://github.com/OpenTTD/OpenTTD/blob/16.0-RC1/src/vehicle.cpp).

The aircraft uses the RC1
[`Aircraft::GetOrderStationLocation`](https://github.com/OpenTTD/OpenTTD/blob/16.0-RC1/src/aircraft_cmd.cpp)
rule: a new station updates entry while in free flight, but not while
committed to the approach, runway or terminal. Ships retain the current
physical berth/track position, request a new stock YAPF path when the
destination changes, and advance from a buoy within the stock three-tile
threshold, without loading it. These are editable station lists, not full
timetable, shared, service-depot or conditional order support.

Verification: `lua5.1 tests/water_air_orders.lua` runs real airport/ship motion
and payments across an edited route and reload. The native SQLite Yate test
is `LUANTTD_NATIVE_COAL_ORDERS=true bash tests/ship_coal_live_native.sh`.
