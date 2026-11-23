# Editing live train orders

Open an owned train's vehicle panel or find it in its depot list. **Orders** shows the current target and lets you add a station, move an order, remove it, replace its destination, or skip to another order. Passenger services still need two different stops that the train can serve as a loop. A freight train's two rows are its designated loading and unloading stages. Replace a stage with a compatible station; wait for the train to leave the currently loading platform before changing that stage.

Rail order cursors and their mutations follow OpenTTD 16.0-RC1's [order commands](https://github.com/OpenTTD/OpenTTD/blob/16.0-RC1/src/order_cmd.cpp). Reorder preserves the active row. Deleting a current loading order keeps that station visit, while explicit skip uses the same physical departure path rather than restarting the train. During motion the train keeps its heading and existing path signal claims; the new route is checked against the physical approach with the existing YAPF port. If the train cannot safely reach the new order going forward, try the edit while it is at a platform. One-off paired and fixed-waypoint scenario trains still show read-only orders.

## Verification

- `lua5.1 tests/rail_owned_service.lua live_orders` and `live_pbs_orders` exercise private ownership and stale edits, genuine movement, an occupied approach with real PBS reservations, deleting while loading, and an explicit skip calling the loading departure boundary.
- `LUANTTD_NATIVE_ORDER_SEQUENCE=true LUANTTD_NATIVE_LIVE_ORDER_EDIT=true bash tests/rail_owned_live_native.sh` edits an active passenger train in Linux Luanti and verifies its physical route, order cursor, six ordered arrivals and fare after SQLite reload.
- `LUANTTD_NATIVE_FREIGHT_ORDER_EDIT=true bash tests/rail_goods_live_native.sh` replaces the receiving platform of an actual Goods train while it is loading, and delivers 25 crates to the newly ordered platform after SQLite reload.
