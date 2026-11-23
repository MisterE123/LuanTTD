# Campaign simulation and Luanti threads

## Shipping boundary

Generating a new interactive campaign runs the same terrain, town and
industry pipeline on a native async worker. The main thread sends only the
selected settings and receives progress and completion. The worker writes
the packed checkpoint atomically; it does not copy the full world back to
the main VM. The next open reads that checkpoint before placing the starting
area. This is generation, not ownership of the running simulation.

The exact [OpenTTD 16.0-RC1 landscape visit order](https://github.com/OpenTTD/OpenTTD/blob/16.0-RC1/src/landscape.cpp#L742-L776) is produced by a real async worker. The [differential test](../tests/landscape_visit_rc1.py) checks nearly one million visits, including both rectangular axes, the zero visit and the largest stock dimensions.
One outstanding request carries `log_x`, `log_y`, `head`, and `counter`.
The output contains three bytes per tile per visit (227,328 bytes per day on
a 512×512 map) plus the ending cursor. No world tile records,
house records, stations, fleet, map engine data, or RNG state cross threads.
The server consumes only the tape for the current day and cursor. It keeps
the original intra-tick ordering, including the zero tile every 256 ticks,
before the existing house/industry/vehicle callbacks. A pause is still a
pause and the headless campaign uses the same cursor. On shutdown only
committed days are saved; there is no tape to reload. A rejected job, invalid
result or five-second timeout falls back to the exact in-thread clock, without
dropping a tick, replaying a day, or waiting indefinitely.

House and industry actions, route execution, fleet interactions, accounting,
construction, and engine callbacks are **not** moved by this change. Main
still holds the authoritative full mutable campaign. Local presentation and
full simulation ownership are separate requirements.

The renderer uses nearby interest sectors. It defers offscreen terrain
repaints, avoids creating out-of-range vehicle models, and removes models
that leave the window without touching their simulation actors. The native
client test observed the same active bus move offscreen with no graphical
entity and regain a new entity when the camera came back.

## Qualified ownership path

Luanti's `handle_async` delegates to a pool with no worker affinity. Repeated
separate jobs must not assume the previous job's globals. Using one **running**
job prevents the state from switching VMs, and Luanti 5.10 can communicate
through `ipc_set`, `ipc_get`, and a bounded `ipc_poll` on that worker. No
Luanti entity, player, or map handle belongs there. IPC is copy-by-value,
not shared references.

`tests/async_state_owner_native.sh` exercises that arrangement on a real
dedicated server. The worker alone owns sparse mutable 4096×4096
`WorldStorage`; the host sends edits and queries rather than terrain copies,
receives bounded 3×3 snapshots, and sees a stale write rejected without
replacing live state. It requests explicit stop and separately proves a
bounded idle exit. It also verifies a native server shuts down while a worker is in a bounded idle wait. That fixture does not mount a 4096×4096 playable game.

Road vehicle market/service, flood rules and town growth now mount through
state-only constructors shared with the native game; a standalone checkpoint
round trip verifies paid bus service and transport-backed house growth and
production without a Luanti engine object. The [native worker economy probe](../tests/campaign_tick_worker_probe.lua)
then runs a real paid bus and town growth on one worker and resumes
a partially built house from disk in a new job. The host sees only a tick,
summary counters and the requested viewport. The same native probe then runs
paid buses, trains, ferries and aircraft with the real shared clock and
checkpoint rebinds inside a worker. State-only road/rail geometry and passenger
fleet bindings are shared with the game. The engine discovers the model
capabilities once; the paid controllers do not mount via a view. These are
verified fixtures, not yet the everyday game-ownership path. The ordinary
streetcar uses a view-independent clock and continues with no players
connected. Noncommercial rail, ferry and air pilots also no longer depend
on a rendering callback to advance.

The [native mailbox probe](../tests/campaign_tick_worker_probe.lua) mounts
one long-lived worker from a real saved campaign, queries nearby tiles and
vehicles, stops and resumes a real bus, refuses a stale or foreign action,
and loads its authoritative day and revision from disk in a fresh worker.
The native proof feeds that mailbox into the existing vehicle panel; it
adds a destination, refuses duplicate submission, and reopens from worker
state without saving the host view. Paid road, rail, ferry and air use the
same order adapters on either side. Projections can batch up to nine
nearby sectors at one committed tick and combine a train's bodies without
mixing old and new samples. The projected terrain contains exact shared
corners and linked station, bridge and other render records for the current
sector, not the full map. The existing terrain ray picker produces the
same hit on a hydrated slope and no hit on an unhydrated sector.

Worker endpoints now cover ordinary road, railway, dock and airport
construction, paid purchases and route dispatch across the four modes,
terrain and bulldozing, and bridge/tunnel construction within the existing
port. The disposable native test mounts a regular generated campaign on the
worker and leaves the host paused. It advances days with no player or
viewport, quotes and builds a real track segment, and saves the changed tile
and company debit only on the worker. Its ordinary native node painter
then consumes projected terrain, and the same stock steam locomotive and
coach spawn, run, despawn, and reappear as subscriptions change. The
ordinary order panel reads the worker's selected train; the HUD reads the
worker's calendar and balance. The stock Autorail release path can submit
to the owner and gets the priced construction receipt. A Linux graphical
test exercises real client movement and clicks the existing train order
panel; the new order list reopens from the worker checkpoint. Deliberate
inputs are queued behind at most one in-flight viewport operation and
outrank the next render request. The authority host also renews its lease
with only a clock receipt when there are no observers. Its native test
waits longer than the old idle timeout and confirms service can still
resume in view. Verified confirmed construction can save before replying
and durable autosaves occur on the worker.

The worker-facing control desk can fetch live company finance and issue
loan or authorized speed changes. The native Linux graphical replay changes
the train's orders and takes out a loan; the loan increases by the exact
amount on the durable worker ledger while the host balance and loan remain
unchanged. Nearby depots can request actual stock purchase offers and issue
basic service orders through the same worker.

Sector updates now separate static terrain from actor, clock, and company
refresh. The worker compares bounded scene contents, not only topology:
landscape or town changes can invalidate a scene without a player action.
The host retains a static scene only while it remains subscribed. The
native engine paints one hydrated or changed sector at a time and does not
repaint an unchanged sector on an actor tick. One-way road drag now uses
the ordinary directional road quote and commit on the worker, including
its occupancy and ownership checks. Single-tile demolition shares the
same layer choices as the existing Bulldozer. The owner offers a
company-specific confirmation ticket and rechecks the terrain, options,
ownership and occupancy before taking anything away. Removing an overhead
bridge leaves the surface intact; the graphical replay uses the native
confirmation modal to remove a depot, with no effect before confirmation.
Road and train poses are computed once per batch and sampled from the
owning worker's actual clock fraction.

A company fleet query pages the owned roster independently of terrain or
visibility. It opens the same vehicle order form for parked or offscreen
vehicles and can obtain an authoritative location for the follow camera.
The Linux replay opens train orders through the fleet menu after the train
entities and their viewport have been removed.
Bridge choices and rail-signal approach/flip choices use their original
native menus, with stock prices, ownership, and occupancy checked on the
owner. Hover previews do not consume mutation tickets. Crossings are built
through the same source command as the old direct tile action. The owner
also supports freight loading-stop construction and bounded canal, lock,
and aqueduct commands.

An internal integration replay now starts the owner from the actual server
lifecycle, including after generated terrain placement. A real Linux client
can join and move horizontally while its company is created only on the
worker, and the same server world restores the exact company, tick and
command revision on restart. No player-facing switch was introduced.
Builder guidance uses the owner's live fleet, stations and deliveries. The
worker indexes depot ownership and updates only changed tiles; the native
HUD does not scan the full world to show the next suggested action.
The next integration step is the full dispatcher, all physical build
and depot interactions (especially freight dispatch), and making
this ownership lifecycle standard with no desktop-specific controls.

The regular application's ownership switch remains unshipped: remaining
tools, the rest of the company UI and normal session lifecycle still need
to use these paths by default. Projected rail bodies share the real
coupling and reversal poses; multipart powered-bridge collectors and
other specialized effects are not yet delivered by projected snapshots. Use a sequenced command
stream for **every** mutation, including player build/route/order requests
and fixture actions; run authoritative quotes against the worker's topology
revision and settle company debits there. Do not mirror writable tile or
fleet tables in both VMs. The view takes versioned subscribed-sector
snapshots, visible actors with stable IDs, and bounded request/reply queries
for remote destinations/inspection. Spawn/despawn engine objects without
stopping controllers. Keep engine writes, input, HUD, audio and node
projection exclusively on main. Save a worker-produced durable checkpoint;
acknowledge accepted commands only once recoverable and never have main
spin on an IPC lock. Stop/idle exit must checkpoint or relinquish ownership
with an explicit saved revision so a replacement cannot replay commands or
silently reset an active world. Measure CPU/memory and worker-pool contention
alongside replay parity before enabling that owner for ordinary games.
