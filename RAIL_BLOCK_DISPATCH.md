# Conventional rail interlocking pilot

Mount `rail_dispatch_run.lua` with its optional final `Block` argument
(`openttd/rail_block_signals.lua` instantiated with existing Track and
Signal). Set `S.rail_block_preview=true`. Use
`Run.place_signal(S,owner,tile,td,Signal.BLOCK)` and
`Run.start_block(S,owner,depot,station)`. Block heads in this pilot are
one-way, using their stock track direction. Existing `Run.current`,
`Run.tick`, `Run.signal`, `Run.sample`, and `Run.clear` are shared.

This is one narrowly scoped live port: two independent empty stock-style
locomotive-and-carriage consists under their own one-way depot-to-platform
orders and the ordinary main dispatch clock. Each consist runs on flat
ordinary X or Y track. Distinct routes can cross only at an unsigned X/Y
diamond and must each have a conventional forward-facing head both before
and beyond every diamond. The route must end at an owned safe platform;
no paid cargo, return orders, merges, span, 90-degree turns, general train
routing, or mixed conventional/PBS signal layouts are admitted. The
existing ordinary PBS, owned and freight start paths remain separate. The
runtime gate uses stock default `pf.reverse_at_signals=false` and
`pf.reserve_paths=false`. This mode does **not** claim to render stock's
transient per-tile reservation bits or the depot flag: neither is used
by this pilot, and a second train cannot be allocated the same depot.

The stock segment solver reads the physical front and every actual wagon
pose after the move, not a route reservation. The original front-entry
and rear-exit signal processing run on the current consist clock. There
is no junction mutex or route reservation. Saved lamp records and physical
positions already live in `S.stock_rail_dispatch` (`run.block=true` marks
this pilot); disabling the gate on reload freezes its clock. Adding or
removing actual track invalidates or refreshes the blocks at the next
tick. Clearing the pilot recalculates the heads from the empty railway.
`waiting` carries reason `red_block_signal`; each `block_aspect` event
identifies the changed `tile`, `td`, and new `aspect`.

## Reproduce

- X rails from (3,9) to (16,9); Y rails from (9,4) to (9,16).
- Depot mouths (3,9) face SW/+X and (9,4) face SE/+Z.
- Platforms from (14,9) to (16,9) and from (9,14) to (9,16).
- Block heads at (7,9) and (11,9) face SW (td 8); (9,8) and (9,11)
  face SE (td 1). Start the X order first, then the Y order.
- In the fixed simulation fixture both reach their entrance at tick 223.
  The X engine steps through; the Y train is stopped by a red head.
  The X wagon leaves the diamond at 313, but its protected block stays
  red until it also clears the outgoing signal tile at 364. The Y train
  passes its head then, occupies the diamond at 469, and both reach their
  distinct platforms. The regression reloads the persisted state when
  only the X wagon occupies the diamond and checks both parked consists
  keep their own terminal block heads red while upstream heads clear.

```sh
lua5.1 tests/rail_block_dispatch.lua
lua5.1 tests/rail_block_signals.lua
python tests/rail_block_signals_upstream.py /path/to/OpenTTD-14.1 lua5.1
```

The first test runs actual Trackworks rails, YAPF orders, consist motion,
station stops and dispatch speed gates. The differential stock signal
suite covers 6,513 C++ reference cases from pinned 14.1 source. This
document is for the host runtime; native tools/setting integration and
visual testing are separate.


## Native fresh-world layout

Set `bayline_rail_block_preview = true`. This mode exposes Railworks
and the two conventional tools directly. Use `/survey 39 7` if you
need to reach the clear ground. Start by building, not by placing
rails on the depot squares:

1. Lay horizontal rail (34,7)–(46,7) and vertical rail
   (39,3)–(39,14). They form a true X/Y diamond at (39,7).
2. Build east-facing depot on **clear** (33,7) and the horizontal
   platform (44,7)–(46,7); place eastbound heads (37,7) and (41,7).
3. Rotate the fitting to south, build depot (39,2), then platform
   (39,12)–(39,14). Place southbound heads at (39,6) and (39,9).
4. Pause, order each from its depot to its platform with **Order
   block-signal pilot (7)**, and resume. No paid service in this mode.

`BAYLINE_NATIVE_FRESH=1 BAYLINE_NATIVE_RAIL_BLOCK=1 tests/native.sh`
built this on untouched terrain by mouse. Both consists were visible,
the north head was red while the other engine had cleared but its
wagon remained, and the original SQLite restart kept both physical
poses and the red light. The head opened only when the wagon cleared
the *outgoing head's tile*, not just the central diamond.
