# Same-tile crossing host bridge

This adapts the pinned 14.1 crossing kernel to native save records,
construction, and **conservative host-only admission**. The independent
adapter's mounting contract and native preview status are below.

## Mounting contract

- Instantiate the module with Sim, Terrain, Crossing and Track. Set
  `s.level_crossing_enabled=true` only in an opt-in test world after
  wiring the safeguards below. `W.quote(s,owner,id,{kind="rail",track=0|1}
  or {kind="road",pieces=...},ctx)` prices existing own ordinary road or
  straight stock rail. Road masks N/E/S/W equal stock NW/SW/SE/NE; axis X
  rail is perpendicular to road mask 5, axis Y rail to road mask 10.
  `W.commit(s,owner,quote,ctx)` rechecks topology, geometry, budget and actual
  occupancy before debiting; returns success, price, dirty ID list, and record.
  It does not clear, replace a stop, mix companies, build one-way road or
  tram, or reserve the track. Default flat only. Sloped test worlds can
  explicitly ask for the source flattened foundation via `ctx.allow_sloped`,
  but do not expose that until native seams/geometry are wired.
- Native write shape: exact `s.tiles[id].level_crossing` descriptor, same ID,
  `build="road"` and completed road bits for compatibility, no raw
  `rail_tracks` field to accidentally open a generic rail mutation path.
  Independent mode ownership is in the descriptor. Protect any
  `W.protected(s,id)` from ordinary road/rail edits, stop/depot/signal
  replacement, tram/ship, span building over/under, bulldozer, source town
  edits and terrain mutations. No removal command yet. Keep wrappers and
  protection active if loading a save with crossings even when opting
  out of construction; never silently expose them as ordinary tiles.
- Wrap `road_yapf_board` with `W.road_board(s,base)`; wrap the plain
  `Lab.board(s)` with `W.rail_board(s,base,ctx)` **before** PBS and signal
  overlays. The boards retain callbacks and ordinary geometry; stock
  Trackdirs route across independently while admission is checked before
  actual motion. Crossing stock pixel height is flattened `record.top*8`;
  preserve existing height fallback on noncrossings.
- Supply `ctx.vehicles_at(id)` from actual head, tail and road-part committed
  positions, including stationary/crashed vehicles. Return an empty list
  only for a known-empty tile, `nil` for no trustworthy sample. Records
  must contain matching board `tile` and `type="train"|"road"`. Hidden or
  wormhole parts are not on-surface; train fronts need owner and track
  direction (or raw direction/trackbits) plus compatibility for early
  approach detection. Set `ctx.rail_board` to the underlying rail geometry.
  `W.dispatch_parts(s,id)` extracts all real parts from
  `stock_rail_dispatch.runs` but does not cover other independent pilots.
  Road speed runtime's local W.vehicles_at already reports active road
  frames; the cross-clock observer must cover stopped vehicles and retain
  the latest authoritative poses when rail ticks outside its road loop.
  An absent active road W or empty render sample is not proof of clearance.
- Reservations come from `ctx.reserved(id,rail_axis)` (must return bool or
  nil for unavailable), otherwise `stock_rail_dispatch.life.bits` when
  present. No independent reservation is written by this adapter.
  Standalone fixtures may fall back to the canonical flag. Do not turn a
  bar into a reservation or attempt a second PBS acquire here.
- Road driver gate: `W.road_step(s,ctx,oldid,newid,td,tram,commit)` before
  publishing a new physical frame; commit is synchronous and returns truthy
  only after the observed pose has changed. A false means the prior frame
  is retained. Normal road proximity and occupancy still apply. The td is
  the next directed track, not heading. Current crossing has no tram layer.
- Rail driver gate: `W.train_batch(s,ctx,transitions,owner,commit)` around
  the whole consist's atomic move, where transitions are the real
  `{from,to,td}` (ordinary depot/portal transitions may also be included).
  The batch must include wagons even when the head does not change tiles.
  `W.train_step` is convenience for a single physical transition.
  `rail_consist_dispatch.step` currently plans internally and its
  existing `allowed` callback only runs for the head: it is not sufficient
  on its own. Expose/forward the actual plan or batch preflight in the
  journal before `Motion.commit`. Interpret road draining/unobserved as
  waiting, not crash. Keep stock PBS/owner/entry checks (the adapter
  blocks mode conflict, not train-versus-train). A gate must never be
  bypassed for a supported actor, creation/teleport, or recovery.
- `W.refresh(s,id,ctx)` returns phase and changed barrier events;
  `W.refresh_all(s,ctx)` returns changes in deterministic group order.
  Call after authoritative PBS/line/occupancy changes and save restore.
  Renderer reads `W.record(s,id).phase/.barred` and top height, but cannot
  write this state. `W.reindex(s)` reconstructs the compact ID index.
  Persistent phases are not permission. Entry probes are fresh. Missing
  observations close the gate; rail requires an authoritative clear group.

## Policy vs stock

OpenTTD can crash a road vehicle already on a crossing; the pure 14.1
kernel retains that predicate. This host instead stops new road entrants
to the **whole** barred contiguous road group, lets existing roads drain
through its internal crossing tiles without being stopped by throat
bars, and blocks new rail parts until the entire road group is empty.
This is more conservative than the source's grouped directional red bits.
Actual train occupancy (including a stopped or crashed train) blocks
entrants until its last part leaves, even if its PBS flag already cleared.
Normal exits remain allowed when an observation is unavailable.
`mixed_occupancy` diagnoses a pre-existing inconsistent save, not a
collision repair. Safety assumes actual moves go through the gates and
committed poses update synchronously. Stopped road vehicles keep rail
held rather than being teleported or despawned.

Run `lua tests/level_crossing_world.lua` for both native-ID construction
branches, both source followers, a reserved rail layer, road tail drainage
over adjacent crossings, train head/wagon/tail, reentrant rejection, a
save/reload with missing occupancy, and stale quotes/no debit on failure.
Native game movement and screenshots remain a separate release gate.

## Mounted Linux preview

Level crossings are available in Rail Engineering. The safety observer
uses both the exact road frames
(including a stopped bus) and all physical dispatch consist parts. Road
publishes only after admission; rail arbitrates the entire real motion
and PBS journal at publication time. Crossings are protected construction
surfaces, not ordinary road junctions or plain Trackworks. The preview uses
the stock flat foundation with independently directed road and rail masks;
native rail bridge/tunnel reservations and spans are retained in their
ordinary contexts. Conservative host admission is not a stock crash rule.

The UI-facing calls are `api.crossing_quote(owner,id,request)`,
`api.crossing_commit(owner,quote)`, `api.crossing_tools`, and
`api.crossings.world.record(S,id)`. The native node uses Blender's
raised/unlit or horizontal/red armed mesh according to actual committed
occupancy, not locally predicted graphical motion.

`tests/level_crossing_live_native.sh` runs two real Luanti server processes
against one native save. Seed 1751 has road stops at (11,12), (17,12) and
the same-tile road crossing at (14,12), perpendicular stock rail along
x=14 from depot z=4 to platform z=18..20, with a wooden bridge from z=6..9.
The fixture preps the rail corridor without altering the gameplay rules.
The train crosses timber, then waits for a genuinely admitted bus. Restart
disables new crossing construction, retains the closed mesh and hold,
denies another bus at the outside edge, and demonstrates drain then travel,
last wagon down, open mesh, and formerly blocked bus reaching its order.
The test machine checks actual Luanti nodes and real movement. A graphical
interaction/capture remains separate from this native two-process test.

## Ordinary Road and Rail placement

With level-crossing construction enabled, the normal **Road** drag can lay a crossing over owned perpendicular plain rail. The normal straight rail or AutoRail drag can likewise lay a crossing over an owned perpendicular plain road. The existing manual Crossing tool is not required. The same native planner, canonical crossing record, clock-based occupancy checks, and mesh are used.

When connecting an existing crossing, include its tile in the drag along the existing road axis. The crossing itself is unchanged and free; an approaching half-road must receive its missing road bit before it connects. The same rule lets an existing crossing be included in a straight rail drag along its rail axis. This also works on saved crossings after disabling *new* crossing construction.

Under the current native safety envelope, flat ordinary same-company, unoccupied, unsignalled infrastructure is required. Unsupported track (including electrified crossings), wrong orientations, through stops, one-way roads, and unknown occupancy are not secretly altered or bulldozed. The quote checks the entire drag, keeping ordinary segments and crossings in the single total. A failed later tile or stale occupancy means the entire drag changes nothing.

`tests/ordinary_level_crossing.lua` exercises production construction entry points, price and both axes, including extending through an existing crossing. `tests/ordinary_level_crossing_native.sh` uses the real Luanti registered normal Road toolbar selection, preview, build callbacks, and crossing mesh; it verifies the formerly disconnected half-road is repaired for $63 without changing or billing the crossing again. The reference tariff and eligibility remain differential-tested by `tests/level_crossing_upstream.py`.
