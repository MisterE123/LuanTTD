# Copying and sharing road vehicle orders

In a normal worker-owned campaign, stop the receiving bus or truck and
select it in its road depot. Choose **Copy orders…**, select another
compatible vehicle from your company (it may still be running), and
press **Copy selected orders**. The source keeps its route, progress,
and service state. The depot accepts only current lists and checks every
destination before changing anything.

In interfaces that expose the separate **Copy / share…** feature:

- **Copy orders** replaces the destination's orders with independent
  duplicates. Future edits affect only that vehicle.
- **Share orders** links both to one list. Each vehicle still has its own
  fare history, cargo, physical pose and progress through the list.
- **Stop sharing** removes the receiving vehicle from the list and
  clears its orders. The other vehicles keep theirs. To retain an
  independent schedule, use **Copy orders** instead.

You can share schedules only between vehicles you own, and buses never
share with trucks. A vehicle must be able to call at the relevant
stations. Fleet members can start and stop independently; to edit a
linked list, stop every member and wait for them to finish their
current active route. This safety restriction is specific to the
current host runtime; OpenTTD also supports some edits in motion.

The stock port covers the station-order portions of OpenTTD’s
[`order_cmd.cpp`](https://github.com/OpenTTD/OpenTTD/blob/16.0-RC1/src/order_cmd.cpp)
(`CmdCloneOrder`, `DeleteVehicleOrders`, `DeleteOrder`). The worker depot
uses 16.0-RC1’s independent **Copy** behavior, not **Share**.
A shared group is keyed independently of vehicle IDs, rebinds the
recorded list after SQLite reload, and preserves each vehicle's cursor.
An equal-length replacement keeps the receiving cursor, a differing
length resets it, and an actual order removal adjusts each member.
This does not add timetable, conditional/implicit orders,
non-road vehicles, stock order warning UI or depot unbunching.

Engine-independent assertions: `lua5.1 tests/road_order_list.lua`.
Graphical Linux: `BAYLINE_NATIVE_SHARED_ORDERS=1 BAYLINE_NATIVE_FRESH=1 tests/native.sh`.

The ordinary worker-backed depot and scrolling are exercised by
`tests/campaign_worker_depot_copy_native.sh`.
