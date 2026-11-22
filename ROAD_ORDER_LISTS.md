# Copying and sharing road vehicle orders

Stop the receiving road vehicle. Inspect it from Fleet or its depot,
then choose **Copy / share…**. Select a source row in your fleet:

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

The stock port covers the station-order portions of OpenTTD 14.1
`order_cmd.cpp` (`CmdCloneOrder`, `DeleteVehicleOrders`, `DeleteOrder`).
A shared group is keyed independently of vehicle IDs, rebinds the
recorded list after SQLite reload, and preserves each vehicle's cursor.
An equal-length replacement keeps the receiving cursor, a differing
length resets it, and an actual order removal adjusts each member.
This does not add timetable, conditional/implicit orders,
non-road vehicles, stock order warning UI or depot unbunching.

Engine-independent assertions: `lua5.1 tests/road_order_list.lua`.
Graphical Linux: `BAYLINE_NATIVE_SHARED_ORDERS=1 BAYLINE_NATIVE_FRESH=1 tests/native.sh`.
