# Stock landscape index and sparse visit windows

`openttd/landscape_index.lua` is a detached helper for the existing OpenTTD
14.1-style landscape clock. It does not replace the live campaign clock,
advance game state on a worker, or make 4096² worlds playable. It provides
the exact visit timing of a *known active subset* without enumerating the
whole map or building a position table for every tile.

## Interface

```lua
local L = dofile(modpath .. "/openttd/landscape_index.lua")
local I = L.new(clock.log_x, clock.log_y)
local active = I.compile({0, 6090, 21098})  -- stock zero-based tile IDs
local events, next_clock = I.window(clock, 74, active)
for tile, tick, slot, x, z in events do
  -- Publish or perform authorized work in this exact stock visit order.
end
-- Only apply next_clock after the owner accepts the window.
```

The example assumes all listed tile IDs fit the chosen map. Both axis
exponents accept the stock range 6–12. Coordinates are **zero-based**:
`x = tile % 2^log_x`, `z = floor(tile / 2^log_x)`. The clock carries the
next nonzero `head` and the last completed absolute `counter` as in
`town_passengers.lua`. Resumed windows can use any valid saved head and
counter; they do not assume head 1, a fresh day, or a square width.

* `I.step`, `I.unstep`, and `I.jump(nonzero, signed_steps)` use exact forward
  and inverse GF(2) transforms. `I.index(nonzero)` and `I.at(rank)` use the
  canonical nonzero cycle (rank 0 is tile 1). They reject tile 0, not
  silently fold it into the cycle.
* `I.skip(clock, ticks)` returns a new clock and number of nonzero steps
  without tile/tick callbacks. The source runs `area/256` visits per tick.
  Tile 0 is generated separately at the **first slot** on each positive
  tick divisible by 256 and takes one of that tick's slots; it does not
  advance the nonzero state. The other slots retain their exact stock
  positions. `slot` in a window is zero-based.
* `I.compile(ids[, previous_set])` stores each active tile's absolute rank once. IDs must
  be unique and form a dense plain array (at most 65,536), and the opaque
  result belongs to the exact index that compiled it. Reuse this token
  across windows while membership is unchanged, or pass the previous
  set to reuse known ranks when membership changes. Schedules handle any
  number of repeated visits within the supported window; they do not
  materialize all visits. A one-head hint accelerates sequential
  resumed windows without depending on saved state.
* `I.advance_active(clock,ticks,active,visit,before_tick)` mirrors the
  clock update and visits the same selected cells as `I.window`. Optional
  `before_tick(tick)` runs on **every** source tick, even where there are
  no active records. Without it, the iterator skips empty ticks. Neither
  the input clock nor active list is mutated by `window`/ `skip`; the
  `advance_active` call updates the clock only after it finishes.
* A window is at most `2^32−1` ticks and must end at an exactly
  representable absolute counter. Signed jump distances are limited to
  Lua 5.1's exact integer range. Long jumps reduce the count by folding
  power-of-two digits for the Mersenne cycle, to avoid float division
  roundoff near the safe-integer boundary.

## Where sparse visitation is sound

The owner must prove that omitted tiles have neither a side effect nor
an RNG draw in the window. In particular, keep live coast/reflood,
houses, industries, construction, and any effectful void/tile-zero
callback. Rendering visibility is unrelated to this set. Membership
is static per window: a callback that activates another tile changes
the problem. In that case the owner must partition the window at an
authoritative boundary and recompile/reconcile events before proceeding,
or use the full stock walk. This module is not a dynamic graph of
all possible effective tiles and does not reconcile intra-tick
membership changes.

## Cost and proof

One map uses an O(log²(area)) basis-power table for jumps. The lazy
baby-step/giant-step rank has at most **4,096 entries** plus six small
nibble tables at 4096², instead of a 16.8-million-position table.
A previously unknown rank can still cost O(sqrt(area)) bounded steps.
The compiled active records and iterator heap are O(active); even a
multi-period window stores only the next occurrence of each active
record. Warm scheduling avoids full-map walks but has event-heap and
tick-position search costs. LuaJIT bit primitives are optional; plain
Lua 5.1 uses a shared ~65 KiB byte-XOR table.

One Linux Lua 5.1 check at 4096² measured about 273 KiB retained after
building the rank index, about 300 KiB with 129 active records, and
~0.40 s to cold-compile that set. One hundred subsequent 74-tick
windows (3,729 actual selected visits) took ~16 ms total with empty
callbacks. A single full 74-tick source walk over 4,849,664 tiles took
~1.38 s on the same interpreter. These are detached CPU measurements,
not end-to-end server throughput. Cold discovery of many active cells,
or a world where most cells really have effects, needs separate profiling.

```sh
lua5.1 tests/landscape_index.lua
python3 tests/landscape_index_upstream.py /path/to/openttd-14.1 lua5.1
lua5.1 tests/landscape_index_bench.lua
```

The Lua test compares all 49 stock exponent pairs and over one million
direct `H.advance_houses` visits, canonical rank sampling over one
128² cycle, zero slots, huge jumps and capped/invalid inputs. It also
replays partitioned windows with real stock house cargo, landscape
effects, lift/rating callback order and shared RNG in both stock house
production modes. The independent oracle compiles the SHA-pinned
OpenTTD 14.1 `RunTileLoop` and stock scalar step: 51 event windows,
130 signed jumps and 39 canonical ranks, including safe-integer-edge
absolute counters, arbitrary heads and rectangular strides.

Source: OpenTTD contributors, GPL-2.0-only, tag 14.1
`src/landscape.cpp::RunTileLoop`, reproduced clock semantics in
`openttd/town_passengers.lua`. See `COPYING.OpenTTD.md`.
