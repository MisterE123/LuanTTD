# Road vehicles turning at ordinary dead ends

A vehicle leaving a drive-through stop keeps its approach direction.
If the road ends ahead, a normal road vehicle can now turn around on
the last usable tile and return to a stop behind it. This fixes routes
where the stock pathfinder already found a return path but the native
motion builder could not play its same-tile reversal.

The port follows OpenTTD 16.0-RC1
`src/roadveh_cmd.cpp` (`_road_reverse_table`, `RoadVehController`)
and `src/table/roadveh_movement.h`. The pathfinder's reversal edge
runs the stock turning row first and is consumed only after
`RDE_TURNED`. This does not permit reversals on signed one-way
pavement or allow a bus to turn while exiting a drive-through stop.
If stock YAPF routes a vehicle back through its own depot without a
depot order, it enters and hides at the source depot-stop frame. Once
the departure point is clear, it services and exits at the normal
outward frame, without changing its station orders. Foreign depots
are not admitted by the existing stock follower. The hidden checkpoint
and case with a depot at one end of the commute are tested separately
with `tests/road_transit_depot.lua` and `BAYLINE_FOCUS_DEAD_END=depot`.

`tests/road_dead_end_rc1.py` compares all eight source rows (four
headings on each side of the road), including exact motion coordinates
and flags. `tests/road_dead_end.lua` checks all four native headings,
continuous stock pixel steps, and signed-pavement rejection.
With `BAYLINE_FOCUS_DEAD_END=1`, the real Linux focus test runs an
actual paid bus between two stops on a road with ordinary dead ends.
It verifies an arrival after focus returns and keeps both the bus
and its fare after closing and reopening the game.
