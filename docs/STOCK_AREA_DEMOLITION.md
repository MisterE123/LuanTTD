# Stock area demolition

The mode-global Bulldozer now has the OpenTTD 14.1 selection and command
order on shared-corner worlds. Press and release without moving to
preserve ordinary single-tile and specialized single-object dismantle.
Hold left-click between two tiles for a rectangle, hold Aux1 at release
(default E) for a diagonal, or right-click while held to cancel.
Construction is only applied on release.

- Rectangles visit increasing X within increasing Z rows, regardless of
  drag direction. Diagonal traversal starts at the release tile and uses
  the stock rotated/parity iterator, not a selected bounding rectangle.
- During execution an individually rejected tile is skipped without cost
  or allowance. Each successful tick of demolition uses one 16.16
  clearing unit, even for a zero-cost operation. On the first otherwise
  valid positive-cost tile the current balance cannot cover, remaining
  cells are not tried. Earlier work remains charged. Feedback shows
  the cost of the next tile requiring money.
- The detached port records source query semantics separately: the
  internal query uses the initial allowance, skips rejects, and does not
  check funds. It decrements its temporary allowance only for nonzero
  quotes and omits the cost at the exact exhaustion boundary. The world
  preview shows the **projected payable prefix**, not that intermediate
  command quote.
- The company's allowance is saved in its existing authoritative company
  record. The default burst is 4,096 pieces and the source replenishment is
  64 units per source frame. As with existing terrain limits in LuanTTD,
  the host accrues the equivalent 74 source frames when one economy day
  passes. It does not accrue while paused. This can appear as a daily
  refill, not continuous feedback each rendered frame.

This ports the area controller, not all upstream clear-tile authorities.
The host uses its current ordinary road/land/water quote/apply paths and
their existing prices, including stock ordinary-water prices. It does
not force-clear a multi-tile structure or its water substrate on a drag.
Rail and road bridge/tunnel portals, stationary transit structure
footprints, and protected layers still require their existing specialized
single-object command; level crossings, foreign infrastructure, public
roads and vehicle/reservation restrictions cannot be bypassed. Plain
ground uses the host's existing zero/no-change handling. The stock
tile-type-specific demolition prices of every possible ground,
infrastructure or building type are outside this slice.

## Verification

```sh
lua5.1 tests/clear_area.lua
python3 tests/clear_area_upstream.py /path/to/openttd-14.1 lua5.1
BAYLINE_NATIVE_CLEAR_AREA=1 bash tests/native.sh
```

The pinned C++ differential compiles `CmdClearArea`,
`CmdLandscapeClear`, both stock iterators and the fixed-point update.
It verifies 7,572 cases including parity and clipping, directional
partial operations, protected and zero-cost cells, refunds, flags,
the query/execution boundary, and fractional counters. C++ tile-type
procedures are deterministic fixtures; native pricing and physical
safety are checked separately through the actual host.
