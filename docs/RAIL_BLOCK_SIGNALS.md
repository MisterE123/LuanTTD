# Stock conventional rail signals (detached controller)

This is an OpenTTD 14.1 port of `src/signal.cpp`, not a PBS reservation or
a generic vehicle exclusion rule. It evaluates the physical connected block
and changes the signal head **toward that block**, not both faces. It works
through ordinary straight track and junctions, including the independent
UPPER/LOWER and LEFT/RIGHT track pairs, and stops propagating through other
companies' track. An occupied branch closes the same block from the other
branches, whereas an occupied parallel half-track does not. It counts physical
consist members, including the last wagon and train parts on the boundary
signal tiles. The traversal also follows stock station, crossing, depot and
wormhole boundaries. Presignal ENTRY/EXIT/COMBO propagation is implemented at
this layer, and mixed PBS boundaries are classified without changing PBS
heads; this does not add construction controls or train dispatch for them.

## Host API

Instantiate `B=dofile(".../rail_block_signals.lua")(Track,Signal)` with the
existing `rail_track.lua` and `rail_signals.lua` modules.

- `B.update_segment(board, signals, owner, train_tracks, tile, side)` returns
  `"free" | "full" | "pbs", changes, overflow, first_flags`. `side` is the
  actual *tile edge* (stock NE=0, SE=1, SW=2, NW=3), not the direction a train
  faces when approaching the tile. For the block ahead of head `td`, seed
  `Track.exit_side(td)`. Use `B.INVALID_SIDE` for an update originating inside
  a depot or span. `changes` is the ordered list of `{tile,td,green}`;
  `first_flags` is the raw stock `SigFlags` bitmask, or nil if there was no
  connected work. If a stock search buffer overflows, that block keeps its
  previous aspects; do not treat a stale green as successful admission.
- `B.train_moved_change_signals(board, signals, train_tracks, tile, travel)`
  is the stock `TrainMovedChangeSignals` helper. After a physical move, call
  it for the *leading* part on the new tile with travel direction, and the
  *last* part on the old tile with reverse travel direction. Non-signaled
  tiles are no-ops. The leading call first returns true exactly when stock
  needs a PBS reservation attempt from a conventional head in a mixed
  segment; the caller still has to implement that source branch. This is
  distinct from releasing a PBS reservation.
- `B.update_track(board, signals, owner, train_tracks, tile, track)` checks
  both ends of a placed or removed track. Batch callbacks via
  `B.update_buffer(board, signals, owner, train_tracks, entries)`, whose
  inputs are `{tile,side}` or `{tile,track}` records with named fields for
  a single owner. Source worksets are ephemeral and bounded at 64 boundary
  heads, 256 open nodes and 128 scheduled edges; topology batches flush at
  64 scheduled entries.
- `board.tile(id)` and `board.adjacent(id,side)` use the rail follower's
  existing tile schema. Use stable IDs including for in-world void tiles when
  practical. `train_tracks(id)` gives a dense array of **actual** stock
  TrackBits for each train part whose simulation tile is `id` (or nil);
  exclude road vehicles and do not substitute a reservation mask. A hidden
  part wholly in depot supplies 128; a part in a bridge/tunnel wormhole
  supplies 64 at its stock simulation endpoint. Each ordinary part supplies
  its physical track bit, not a trackdir or the tile's full layout.

Save the existing Signal records and actual consist state, not temporary
search sets. The live controller still needs to wire build/removal triggers,
startup/depot calls and source movement events in order, and use existing
`Signal.capture_entry` and `Signal.entry_wait` for the front-engine gate;
this module does not schedule or reverse trains. No live rail UI, saved
network migration, or broader interlocking support is claimed.

## Verification

```sh
lua5.1 tests/rail_block_signals.lua
python tests/rail_block_signals_upstream.py /path/to/OpenTTD-14.1 lua5.1
```

The deterministic fixture runs all four directions, preserves red through
a copied save and trailing carriage, reopens it only after the tail clears,
and tests occupied branches, both kinds of independent half-track, presignal
propagation, and stock aspect admission. The differential compiles the
whole pinned processing body of `signal.cpp`, `TrainMovedChangeSignals`,
the relevant occupancy callbacks from `vehicle.cpp`, and directional/source
primitives against a synthetic map and vehicle-query shim. It compares
segment decisions, ordered writes and final lamp masks over 6,513 cases.
`signal.cpp` was cross-checked via the pristine OpenTTD 14.1 source tar from
Debian (tar SHA-256
`2c14c8f01f44148c4f2c88c169a30abcdb002eb128a92b9adb76baa76b013494`);
its bundled `rail.cpp` matched the existing pin and the test checks each
source file's SHA-256.
