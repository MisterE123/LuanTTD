# Rail waypoints

Open **Rail Construction → Rail Tools & Operations → Rail Waypoints**.
Choose **Place railway waypoint** and click an owned straight track tile.
The signposts are beside the existing rails, not a new platform. **Remove
waypoint, keep rail** takes the signs down without removing or converting
the track.

Inspect an owned rail depot and buy a passenger train. When ordering a
single shuttle, click its first platform, the waypoint, then its second
platform. The depot-to-first-platform leg stays direct. After that,
the shuttle passes through the selected waypoint on both trips. It
doesn't stop, load, or pay out there. To start without a waypoint, skip
that click. Right-click cancels the order selection before dispatch.

This preview supports one waypoint on the two-platform passenger
route. Both legs must connect from the waypoint to the next platform.
The ordinary safe path signal and terminal rules still apply. Waypoints
need an owned single-axis straight rail tile and a level rail bed.
Switches, signals, rails on an incline and facilities are not converted.
Paired passenger dispatch, freight waypoint lists, joining adjacent
waypoints, and NewGRF waypoints are not part of this preview.

Ported from OpenTTD 14.1's `waypoint_cmd.cpp` placement and keep-rail
removal, `table/pricebase.h` prices, the YAPF waypoint destination, and
the `CheckNextTrainTile` pass-through order in `train_cmd.cpp`.
The signboards and footings are original LuanTTD meshes.
