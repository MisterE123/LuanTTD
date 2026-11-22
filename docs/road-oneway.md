# One-way roads: OpenTTD 14.1 rules

`openttd/road_oneway.lua` ports the ordinary-road restriction and
long-drag geometry. It is a read-only command planner, not UI or world
construction. `road_cmd.cpp`, `road_gui.cpp` and the stock enums are the
source of truth. Existing source slope and YAPF modules supply foundation
rules and the post-command directed reachability.

## Interface

- Instantiate with `OneWay(RoadSlope, RoadFollow)`. Call
  `plan(board, start_id, end_id, axis, opts)`. Axis 0 is the map's X
  axis; axis 1 is the map's Z axis (OpenTTD Y). The map's ID ordering
  must increase with X and with Z. The GUI passes toggle=2; it is the
  default. Use `tile(snapshot,bits,toggle,opts,id)` for a single
  already-resolved road bit request, or for guarding ordinary
  building with toggle=0.
- `board.xy(id)`, `board.tile(id)`, and
  `board.adjacent(id,diag_direction)` resolve actual in-bounds
  coordinates and records. Ordinary tiles are `kind="road"` and
  bare ground `kind="clear"`. Road records can include
  `roadtype=0,road_bits,tram_bits,slope,owner,disallowed,roadworks,occupied`.
  For the company check, encode town ownership distinctly from nil;
  nil is unowned. Supply actual ground occupancy via
  `opts.occupied(tile,id)` rather than treating every entity above a
  bridge or below the tile as a conflict. Non-roadway vehicles on the
  ground count, and so do stopped road vehicles.
- `board.connects(id,dir)` is optional. Implement the stock endpoint
  condition if the host uses synthetic structures: the compatible
  next tile must expose its road bit facing back toward this tile.
  This concerns compatible geometry, not legal travel direction.
  The fallback reads the board's `road_bits` or optional
  `board.road_bits(id,snapshot)`.
- Quote with `opts.company`, actual source-local
  `opts.piece_cost` and `opts.foundation_cost` (defaults: initial
  stock 95 and 250), and optionally `opts.clear(tile,id)` for clear
  cost or an error. The planner never applies changes. On success
  it yields ordered `changes`, `cost`, `skipped` and any
  `stopped_at`. An existing complete road's sign costs zero. The
  GUI skips initial blocked tiles, then stops rather than jumping
  later obstacles. Already-built is nonfatal. Use `ai=true` only
  for the stock all-or-nothing quote behavior.
- For a multi-tile GUI drag, external endpoints use the half-bit
  only if it can connect outward. Interior tiles are full. For a
  one-tile pointer operation pass the actual `start_half` and
  `end_half` values; stock uses both even when they are equal.
  AI drags always use the supplied half-tile values. To request an
  entire individual tile in map-positive orientation, pass
  `start_half=false,end_half=true`.
- Apply only the edited road fields to existing tiles; do not replace
  their terrain or overlay records. Save `disallowed` and propagate it
  to the YAPF road board; revalidate already-precomputed movement at
  restricted tile entry/turn and when removing pavement. A successful
  ordinary road-bit removal clears restrictions; removing tram bits
  does not.

## Direction, signs and limits

`arrow(bits,disallowed)` returns source diagonal direction, or the
second value `"no-entry"`. On a straight road, place the marking at the
tile center, conformed to the actual road foundation or ramp:

| Stored DRD | Road X (bits 10) | Road Z (bits 5) |
|---|---|---|
| 0 | no marking | no marking |
| 1 | +X (SW), dir 2 | −Z (NW), dir 3 |
| 2 | −X (NE), dir 0 | +Z (SE), dir 1 |
| 3 | no entry from either direction | no entry from either direction |

The sign is an XOR toggle, not a directional assignment. Repeat the
same drag to undo it. Toggle from the reverse end without undoing first
and the road blocks both directions. Closure can be removed under a
vehicle only when the number of disallowed directions strictly
decreases. Adding or changing bits without such a decrease requires
an unoccupied tile.

The supported command is ordinary roads, with tram tracks optionally
running on the same tile but unaffected by the road restriction. Do not
offer this tool for tram construction, crossings, stations, depots,
bridges/tunnels or a road requiring a clearance/conversion path not
represented by the normal tile planner. Such unsupported tiles remain
immutable here; the stock world build command may instead alter
physical infrastructure there and simply omit signs. No road rule
is inferred from a rendered arrow alone.

## Verification

`lua5.1 tests/road_oneway.lua` builds signs on both axes, tests
opposite/XOR drag and tram/occupancy handling, and tests actual YAPF
reachability. `python3 tests/road_oneway_upstream.py /path/to/OpenTTD [lua5.1]`
compiles SHA-pinned stock flat-road normal command blocks, complete long
drag, and road track status. Foundation geometry is separately checked
by `tests/road_slope_upstream.py`. No live UI/native campaign is wired here.
