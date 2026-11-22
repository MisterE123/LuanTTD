# Rail Oil workbench

Linux playtesting built the source rail/road route in seed 1751,
designated its two platforms, purchased and ordered the real tanker
from the native UI, and reopened the world during loading. The train
delivered 30,000 L of crude, and a separate Goods truck carried the
refinery output to town. This workbench runs a single Kirby with one
tanker; it does not yet provide general freight consists.

## Set up the oil world

Choose **Oil and Refinery** in the new-world setup screen. The
oil fixture places the well near **(11,2)** and the refinery near
**(15,17)**. These are industry anchors, not platform or track placement
instructions. Inspect each catchment before laying the platforms.

## Move crude by rail, then Goods by road

1. Build a rail depot and two owned rail platforms. Place the
   loading platform where its catchment covers the well. Put the
   unloading platform where its catchment accepts oil for the refinery.
   Open **Railworks → Rail Operations (7) → Rail Freight (5)**, then
   use **Oil wells: designate loading platform (4)** and
   **Oil refinery: designate unloading platform (5)**. Connect the
   terminals with clear track and a place to wait safely at the end of
   each platform.
2. Inspect the depot and choose **Buy Kirby Paul Tank + 30,000 L Oil
   Tanker** ($12,499 at the default prices). Set the orders to **load oil at the well first**,
   then **unload at the refinery**. Confirm the oil station roles
   before starting. The 30,000 L tanker looks the same empty and full;
   inspect the train or station count rather than judging from the mesh.
3. Build a freight road stop in the refinery’s Goods catchment and a
   second stop where town buildings accept Goods. Purchase a
   **Goods truck** and order refinery pickup first, then town delivery.
   The road-only oil-world fixture uses refinery-side **(16,16)** and
   town-side **(14,8)** truck stops. Use those only if they do not
   conflict with the railway you build.
4. Verify actual crude received at the refinery, Goods waiting at the
   truck stop, and Goods received in town. An initially empty station
   does not by itself indicate failure; check its catchment and allow
   the stock production and loading clocks to run. After the first
   deliveries, inspect the train and the truck separately to see the
   two payments. Saving preserves both services and their cargo.
