# Rail route worker performance

OpenTTD 16.0-RC1's `CYapfCostRailT::PfCalcCost` advances its tile records
as `prev = cur; cur = next`. The Lua port now does the same with its
board adapter's descriptors. The track follower passes the destination
descriptor back to the cost loop, including the last tile of skipped
platforms. The same current descriptor serves the signal and reservation
checks. No tile descriptor is stored on a search node or shared between
searches; a new search still reads live aspects and reservations.

## Measured result

A/B comparison inside the native Luanti 5.15.2 async VM, with the same
allocating board, signal, and reservation adapters on a deterministic
256×64 test network. Twelve alternating batches of 96 complete station
and safe-tile queries including reconstructed routes, facing path signals,
one-way block signals, turnouts, occupied rail and four-tile platforms:

- Median time per batch: 185.88 ms before, 94.78 ms after (49% less).
- Board descriptor reads per batch: 237,792 before, 53,784 after.
- Cost, estimate, end reason, expanded nodes, track directions and
  skipped tiles matched exactly. Removing a one-way signal on the same
  board was visible to the next search without a topology revision.

Reproduce using `tests/rail_yapf_perf_native.sh LUANTI_SERVER BASELINE_REV NEW_OUTPUT_DIRECTORY`.
This measures rail routing, not the entire simulation or rendering FPS.
The existing compiled OpenTTD 14.1 follower, cost and search tests are
historical regression coverage, not evidence of full RC1 train parity.

## Reuse stock rail availability across company view polls

OpenTTD 16.0-RC1 keeps its calculated rail types on the company and
updates them as engine availability changes. The current LuanTTD
adapter has public-sale availability only. Companies still need to
exist, but do not need separate copies of the same public result.
The worker now computes the public mask once per simulation day and
reuses it in the company HUD and rail construction checks. Changes to
fleet identity, electrification, or mounted assets invalidate it.
No new availability is saved or granted; exclusive previews will need
their own per-company calculation when ported.

In the native async benchmark, 1,024 company observations across 32 days
and four companies took a median **270.64 ms → 5.72 ms** CPU per batch.
The old path calculated 2,048 masks for the two gauges; the current path
calculated 32. All returned gauge flags matched over twelve alternating
batches in different calendar eras. This measures the queried company
status only, not whole simulation-day performance.

```sh
tests/railtype_worker_perf_native.sh luantiserver 372a434 /tmp/railtype-bench
```
