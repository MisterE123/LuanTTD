# Vehicle selection, live orders and follow

Right-click the vehicle in the world, or click it with **Inspect** selected. Click **Orders & follow** in the existing road vehicle sheet. Alternatively, open its home depot, ship depot or hangar, choose **Depot vehicles / Follow**, and select a vehicle. You can open its orders or go straight to the follow camera.

**Follow vehicle** puts your camera above and behind the selected vehicle. Look around normally. The camera follows the vehicle without inheriting the rotation of the model. Right-click to return to your original builder position and view. You can follow while the game is paused, and a vehicle waiting to depart is tracked from its depot.

On the vehicle sheet, select an order to move, remove or skip to it, or select a destination to add it. The arrow marks the active order when the sheet opens. An edit does not teleport the vehicle; it respects its current path, signals, approach and equipment. Passenger railway orders can also replace the selected stop. On supported freight trains, choose a compatible replacement for the load or unload stage, without mixing the two cargo roles. The preview tram applies edits at a safe through-stop boundary. Initial orders for trains, ships, trams and aircraft still start through their depot's setup controls.

To pick a station directly in 3D, open **Orders** and choose **Pick in
world**. Aim at a compatible station and use **Pick stop**. Repeat for
as many stops as you need, then use **Done** or right-click to return to
the orders sheet. The destination list is still available. Where order
replacement is supported, **Replace in world** changes the selected
row instead of appending. The worker validates the actual tile, vehicle,
company, order list and cargo rules, regardless of whether you pick in
3D or use the list.

The order controls cover the shipped vehicle systems, not all OpenTTD order options. Some scenario-specific and inactive rail consists are read-only, and operations such as a plane already committed to landing or a freight train loading can defer or reject a change. Vehicle orders are saved with the world; follow camera is per player and not saved.

## Start a train from its depot

Open the rail depot. **Trains in this depot** lists owned trains; **Buy trains** opens the separate purchase catalogue. Use **Assemble wagons** in the roster to manage loose cars.

1. Select the parked train, then **Set or review orders**.
2. Select a station and click **Add selected destination**, or choose **Pick in world** and click the platforms you want to serve. Use **Done** to return to the list.
3. Review the order, then click **Start service**. Closing the window without starting leaves the train parked and keeps the draft. Start requires at least two distinct stops, including a valid return to the first stop.

This workflow covers supported passenger, Mail, and Coach/Mail trains. Industrial trains with specialized loading and delivery rules still use their dedicated depot route controls.

## Copy orders in a depot

Select the receiving vehicle in its depot and choose **Copy orders…**.
Choose another company vehicle with compatible orders, then choose **Copy
selected orders**. This makes an independent list; editing either vehicle
does not edit the other. Road vehicles can copy from a compatible road
vehicle. Parked passenger, Mail and mixed Coach/Mail trains can copy a
compatible town-rail station list, including every stop and its loading and
unloading rules. Use **Set or review orders** to check the copy, then **Start service**
when the track is ready. A rejected start retains the
copied list, so you can fix the route and retry.

Town rail follows the independent-copy branch of OpenTTD 16.0-RC1
[`CmdCloneOrder`](https://github.com/OpenTTD/OpenTTD/blob/07b339c0aaeb0a87be9490b2f1c3f17c6b00b837/src/order_cmd.cpp#L1571).
This is not shared orders, and it does not yet cover dedicated industrial
rail, non-station orders, ships, or aircraft. A native worker test preserves
a three-stop list with Full load all and Transfer across SQLite restart,
then dispatches it unchanged even though the original was edited. Linux
client playtesting also confirmed the actual Copy and Start buttons,
recipient selection, and preservation of Transfer after dispatch.

## Verification

Linux Luanti client input confirmed selecting the bus in the 3D world, moving an order in the form while the bus was in service, following it from the depot list, and returning to the exact builder position. The common interaction tests exercise six rendered actor classes. Native Linux SQLite checks cover live passenger rail edits, a Goods train delivering after a destination change, and the Yate leaving partial loading and delivering after a restart. Road, tram, ferry, and air motion/state tests cover their own order adapters.

## Passenger train cargo rules

Select a station order in a passenger train's sheet. **Cargo rules for selected order** lets you set loading and unloading independently. Loading supports available cargo, full load all, full load any, or no loading. Unloading supports normal delivery, unload all, transfer, or no unloading. A passenger-only consist has one cargo type, so both full-load options wait for the same capacity. Apply each rule separately.

A purchased passenger aircraft also carries Mail in a separate hold. Both cargoes come from the same houses that supply trucks and trains, and the airport panel shows how many passengers and bags are waiting and onboard. In an aircraft's cargo rules, **Full load any** requires a full passenger cabin even if the Mail hold fills first; **Full load all** waits for both compartments.

As in OpenTTD 16.0-RC1's `CmdModifyOrder`, editing the current loading rule applies to the visit already in progress; changing the unloading rule does not reclassify packets already staged for that visit. A native Linux/SQLite test saves a train while it is waiting on Full Load, restores that visit, and releases the train by changing its loading rule. The test is available via `LUANTTD_NATIVE_ORDER_SEQUENCE=true LUANTTD_NATIVE_CARGO_ORDER_EDIT=true bash tests/rail_owned_live_native.sh`.
