# Stock RAIL ↔ ELRL bridge and tunnel conversion

OpenTTD 14.1's `CmdConvertRail` treats a rail bridge or tunnel as one
structure. This source fixture tests the `rail_types.lua` quote and
documents broader upstream behavior than the current LuanTTD workbench.

The opt-in transaction fixture also reads actual bridge and tunnel records
through `rail_span_world.electric_record`. It verifies two matching
portals, their shared railtype, geometry index and independent middle
layer before permitting either portal to quote the whole structure. It
refreshes all affected rendered positions, but never writes a ground tile
or reassesses a live route. If a route uses any member or the selection
directly includes stacked ground rail, the workbench refuses. The
production tool mounts the renderer and moving collector for owned
empty wooden rail bridges only. Electric tunnels have no active mount.

The bridge in the grade test fixture (21,15)–(27,15) includes graded heads.
The Lua host fixture quotes one portal versus the full route, checks
the $476 purchase and $84 downgrade, and verifies no write to the
ground layer. A native isolation fixture runs real bridge and tunnel
construction and round-trips the converted typed records through
Luanti's serializer on a detached copy before running the existing
ordinary locomotive through the unchanged test-world spans.
The paid native bridge scenario goes further on the mounted wooden
workbench: it refuses an unpowered bridge, authorizes conversion at one
portal, then moves a sprung electric engine across both ramps, saves
while loading, and pays after reopening. Both body and collector models
remain independent native entities.

| 7 tiles including ends, stock base prices | RAIL → ELRL | ELRL → RAIL |
| --- | ---: | ---: |
| Select either end only | $476 | $84 |
| Select both ends; no additional selected ground rail | $476 | $84 |
| Select both ends plus one ordinary ground-rail piece on the same selection line | $544 | $96 |
| Select only the independently convertible ground-rail piece | $68 | $12 |

Internally the two mouths are the only map records whose span railtype changes.
The cost counts the five middle tiles plus two ends. Infrastructure moves
28 units between railtypes, with the stock tunnel/bridge multiplier of four,
but prices the seven pieces without that multiplier. If the iterator includes
both mouths, the higher tile index is skipped because the other end is in the
selection. This is independent of traversal order. A road-only tunnel or
bridge isn't eligible. Ownership and stock target availability still apply.

The land layer beneath a bridge, or over a tunnel, is independent. Selecting
one portal does not implicitly change lower/surface track anywhere between
them. A drag along the span can also select ordinary ground-track tiles in
its own right; each such tile is converted and charged independently,
not as part of the structure. Never paint the lower layer just because span
wires traverse that position.

## Occupancy, reservations and apply order

- Vanilla RAIL and ELRL are compatible both ways, so the command does **not**
  run the restrictive `TunnelBridgeIsFree` occupancy test for this
  conversion. Operation can occur while a train is in the bridge/tunnel.
  Equivalent-geometry conversion is not a destructive track-clear operation.
- The converted branch checks reservation bit 4 in that **initiating portal's**
  m5, then looks up the reservation holder on the portal's diagonal track.
  When both portals are selected, the initiating portal is the lower tile
  index. Selecting only the higher one makes it the initiating portal.
  There is not a second independent command-level reservation check on the
  remote portal. The real `GetTrainForReservation` can follow the path
  outward in both directions, inspect a remote end, and return no holder for
  a stray reservation. A portal bit is not itself an owner ID.
- A resolved holder loses its current path only if its physical engine
  railtype has no power on the target: for these two types, an unflagged
  electric train loses a reservation on downgrade, an ordinary engine
  keeps one in either direction. The command releases before writing the
  railtypes and tries to re-reserve after both writes. The retry can fail;
  never treat it as an automatic new path. A stray marked bit by itself
  isn't cleared by conversion.
- Both ends have their type written, then both are consulted for train
  power refresh and both are sent to YAPF's track-layout-change hook. A
  bridge is dirtied as a structure; a tunnel dirties the portal tiles.
  The GUI query path makes none of these changes.

`tests/rail_span_conversion_upstream.py` uses the existing pinned command
extractor with instrumented host shims plus the original span-length stock
function, portal direction/reservation getters and stock diagonal track
mapping. The differential covers both axes, both span classes, two
lengths, four reservation outcomes per portal (unmarked, stray, conventional,
electric), occupied and empty hosts, either end or both, ground-only selection,
foreign property, and hidden ELRL downgrade. It compares observed quotation
and execution with the detached Lua plan across 40,966 cases. The test
supplies the selection iterator's membership, physical vehicle occupancy and
resolved PBS owner lookup at the host boundary: it does not re-test wire art,
actual train motion or the full stock PBS path search.

```sh
python3 tests/rail_span_conversion_upstream.py /path/to/openttd-14.1 lua5.1
```

Source: `src/rail_cmd.cpp` (`CmdConvertRail`), `src/rail.h`,
`src/tunnelbridge.h`, `src/tunnelbridge_map.h`, `src/pbs.cpp`
(`GetTrainForReservation` and portal reservation operations). OpenTTD
contributors, GPL-2.0-only; see `COPYING.OpenTTD.md`.
