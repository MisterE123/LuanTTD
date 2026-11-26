# AutoRail

In a worker-owned campaign, the ghost and price come from the complete
board. Hold the end of a drag until its price appears. Releasing commits
only that footprint and charge; if the track or price changes, no money
is spent. The worker also provides seam context for existing diagonal
track and connected station canopies at the edge of a loaded map sector.

Open **Railworks** from Home, then select **Lay Track**.
Hold left-click on the starting tile, aim along the route, then release
to build the priced preview. Right-click while holding, or change tools,
to cancel without buying track. A click on one tile places one piece;
aim at the relevant part of the tile to select its shape. Choose
**Rail Operations → Engineering → Manual Pieces** to
place or remove a specific piece without snapping.

The crosshair snaps to OpenTTD 14.1's actual nearest stock alignment.
This includes the two-tile special cases and alternating half-tile
pieces for diagonal runs. The proposed 3D track uses the same mesh,
foundation and grade as the piece that will be built. The cost is
for new pieces, not track that's already there. Existing signals
and protected infrastructure are not silently removed.

Like OpenTTD's ordinary build drag, AutoRail skips obstructions at
the start. After it has added a piece, it stops at the first obstruction.
Matching track is left in place and doesn't interrupt the drag. The
preview shows what can be added and charges only for those pieces.
The Manual Pieces tools retain their existing construction guards.

Selection and path geometry are translated from OpenTTD 14.1
`src/viewport.cpp`, `src/table/autorail.h` and `src/rail_cmd.cpp`,
including the stock direction table and piece stepping. The pinned
source differential `tests/autorail_upstream.py` compares the exact
snapped point and full ordered track list with compiled C++.

## Through platforms on an owned shuttle

A supported single owned two-body shuttle can reserve track past a
platform in its direction of travel to a safe point on the next ordered
leg. It still stops and loads at the selected platform. It follows the
verified path through junctions and waits rather than reserving a
different branch. A dead-end platform still needs no exit signal. If
the train must reverse at a continuing platform, put a forward **Path
Signal** on the first tile beyond it.

This ports the forward look-ahead in OpenTTD 14.1
[`ChooseTrainTrack`](https://github.com/OpenTTD/OpenTTD/blob/14.1/src/train_cmd.cpp#L2746-L2840)
and the YAPF nearest-safe fallback. The approved forward prefix ends at
the first safe point, with no repeated tile, bridge or tunnel in that
extension. If the next route is found but cannot reserve, this attempt
does not leave the station or entry signal held. If there is no future
destination, nearest-safe is constrained to the same approved
powered path. This scope does not add conditional/depot orders,
multiple unsafe forward orders in sequence, or new reversal paths.

Fixture: `lua5.1 tests/rail_owned_service.lua platform_lookahead`
also accepts `platform_fallback` and `platform_claim_rollback`.
With the native tools installed,
`BAYLINE_NATIVE_PLATFORM_LOOKAHEAD=true bash tests/rail_owned_live_native.sh`
tests a real paid through station and its claims across server restart.
