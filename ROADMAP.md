# LuanTTD parity roadmap

The next release bar and source port are defined in [PORTING.md](PORTING.md).
Polish and fidelity of shipped content take precedence over breadth.

LuanTTD is a standing background project. Keep each milestone playable and
testable; don't treat a nominally implemented feature as parity.

## Direction: 3D first

Use Luanti's native hotbar for common tools, Inventory for secondary menus,
and the live HUD for tool, target, date and cash. The optional map jumps to
a place; never require it to build. Evaluate the view at street and survey
height. Use actually simulated activity as the source for visual effects.
All vehicles are meshes. Passenger particles show actual queues up to platform
capacity, are scaled to the buses, and expire promptly when people board.
The stop panel keeps an exact count even when the visual crowd caps out.

Benchmark privately against running OpenTTD (installed on the Linux build
workspace). The first visual comparison shows that vegetation variation and
settlement density matter even with no service in view. Next compare a
built two-town service: camera readability, active vehicles, station
arrivals, cargo feedback, town growth, and time-to-first-fare.

## Systems

1. **3D world and rails.** Improve direct placement feedback, scenery density,
   camera, and moving, stoppable vehicles. Bring the entire fleet from
   original Blender prototypes up to the approved reference quality.
   Independently verify Creative Commons references per model. Rails: Safe following on a signal-protected corridor, fair use
   by opposing trains, and clear feedback. Then introduce independent track
   pieces/directions, actual direction-specific path and block signals,
   passing loops, multiple platforms, depots and consists.
2. **Network operations.** Vehicle replacements and breakdowns, scheduled
   service, shared/timed orders, cargo routing, meaningful station ratings
   and transfers, road markings/levels, water and airport operations.
3. **World and economy.** Target selectable dimensions from 64 to 4096 tiles
   per side without allocating a dense Lua table for 16.8 million tiles.
   Use deterministic terrain chunks plus sparse edited infrastructure. Keep
   immutable job inputs bounded and tagged with tick and generation; workers
   build chunk or route results, while a single authority commits state.
   Handles, mesh objects and mapblocks must not control economic time.
   Test headless offscreen service and compare active-viewport and no-viewport
   results. Then add scenario editor, richer town rules, industry graphs,
   cargo economy and company competition.
4. **Usability and compatibility.** Faster map tools, visual validation, save
   migrations, usable multiplayer, AI interfaces and a defined compatibility
   target for extensible rules. [Playable OpenTTD save import](IMPORTING.md)
   is a standing compatibility goal, starting with vanilla saves. NewGRF
   and fork support are later, explicit compatibility levels.

## Port core systems

Port the upstream logic for advertised OpenTTD features rather than keeping
simplified stand-ins. Start with terrain, road construction, routing, orders
and economy, then port rail geometric and signal state along with YAPF. Keep the [stock half-tile rail pieces](https://wiki.openttd.org/en/Manual/Building%20tracks)
for diagonal and shared-tile track layouts; regular [stock roads](https://wiki.openttd.org/en/Manual/Building%20roads)
use connected edge bits, not invented diagonal road pieces. Keep
the Lua/Luanti UI, rendering, asset pipeline and native interaction separate.
See PORTING.md for the pinned source, license and Linux playtest gates.
