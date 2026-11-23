# Vehicle selection, live orders and follow

Right-click the vehicle in the world, or click it with **Inspect** selected. Click **Orders & follow** in the existing road vehicle sheet. Alternatively, open its home depot, ship depot or hangar, choose **Depot vehicles / Follow**, and select a vehicle. You can open its orders or go straight to the follow camera.

**Follow vehicle** puts your camera above and behind the selected vehicle. Look around normally. The camera follows the vehicle without inheriting the rotation of the model. Right-click to return to your original builder position and view. You can follow while the game is paused, and a vehicle waiting to depart is tracked from its depot.

On the vehicle sheet, select an order to move, remove or skip to it, or select a destination to add it. The arrow marks the active order when the sheet opens. An edit does not teleport the vehicle; it respects its current path, signals, approach and equipment. Passenger railway orders can also replace the selected stop. On supported freight trains, choose a compatible replacement for the load or unload stage, without mixing the two cargo roles. The preview tram applies edits at a safe through-stop boundary. Initial orders for trains, ships, trams and aircraft still start through their depot's setup controls.

The order controls cover the shipped vehicle systems, not all OpenTTD order options. Some scenario-specific and inactive rail consists are read-only, and operations such as a plane already committed to landing or a freight train loading can defer or reject a change. Vehicle orders are saved with the world; follow camera is per player and not saved.

## Verification

Linux Luanti client input confirmed selecting the bus in the 3D world, moving an order in the form while the bus was in service, following it from the depot list, and returning to the exact builder position. The common interaction tests exercise six rendered actor classes. Native Linux SQLite checks cover live passenger rail edits, a Goods train delivering after a destination change, and the Yate leaving partial loading and delivering after a restart. Road, tram, ferry, and air motion/state tests cover their own order adapters.
