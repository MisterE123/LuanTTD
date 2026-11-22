# Paired same-direction stock passenger trains

`bayline_rail_pair_preview = true` (with owned rail and the paid rail world clock enabled) opens an explicitly limited paired passenger order. Two already purchased Kirby Paul Tank + Passenger Carriage consists use independent owned depots and one loading order and terminal order each. A shared loading platform is allowed. The trains must have shared, same-direction track and distinct end platforms that stay clear of the other train’s path. The terminal uses the stock unload/no-load order, then the coach visibly parks with its reservations and paid row retained. This is not arbitrary scheduling, opposite-direction dispatch, alternate routing around a blocked planned branch or an automatic return to depot. The original alternating shuttle and repeating coal service stay separate and exclusive.

Stock YAPF plans the actual rail directions and each safe waiting position. If a merge or diverge has choices, the stock planned trackdir must still be reachable from the actual inbound track. At runtime reserve only a stock route consistent with the agreed path. The same PBS track masks, moving consist geometry, signal aspects, and last-vehicle cleanup decide movement; there are no substitute tile locks or time-gap guesses. A parked train keeps its occupied station claims. A failed preflight cannot register only half the pair, consume paid actor IDs or debit again.

## Mount and inspect

- Stage both stock pairs in separate depots, then call `Owned.start_pair(S, owner, {id=a, first=loading_station_id, second=terminal_id}, {id=b, first=..., second=...})`. This operation does not buy either locomotive.
- `Owned.toggle(S,owner,id)` controls each active train independently and leaves the occupied rail intact. Completed trains cannot be deleted by the pilot Clear operation. Returning or moving a parked consist requires a separate, future rail order workflow.
- `Sim.rail_paid_status(S,id)`, `Sim.rail_paid_pose(S,part,fraction,id)`, `Owned.running(S,owner,id)` and `Run.current_paid(S,id)` identify the actual stock unit. With no selector the existing singleton status and pose remain compatible; coal still uses its existing cargo branch.
- The original saved commercial row migrates without replacing its carried packets, timers or loading order. With a pair, both saved rail rows use individual paid serials in one physical stock station clock. Each run keeps independent visit counters, fares and stock running costs.

## Proof

```sh
lua5.1 tests/rail_paid_actors.lua
lua5.1 tests/rail_owned_pair.lua
TMPDIR=/path/to/qa BAYLINE_NATIVE_TOOLS=/path/to/tools tests/rail_owned_pair_native.sh
```

The isolated actor test upgrades a live singleton while retaining its load and adds a second stock coach on the actual passenger station timing rules. The integration fixture builds two depot branches merging to one eastbound line and a shared loading station, then splitting to distinct terminals. It tests invalid pair rollback, stop/start of the second train, same track occupancy, rear-only merge reservation across a save, loading persistence and retained terminal claims. The native two-boot fixture verifies both coaches’ entities on their actual poses, red PBS on restart with one last wagon still occupying the merge, admission only after that wagon leaves, separate paid fares and two visibly occupied terminals. See the reproducible map in `tests/rail_owned_pair_fixture.lua`.
