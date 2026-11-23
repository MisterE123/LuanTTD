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
The public game still uses its original command paths. The new endpoint
covers a road slice; the next step is wiring the real forms and world
actions to the worker and replacing direct reads with bounded projections. Use a sequenced command
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
