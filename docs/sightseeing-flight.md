# Sightseeing flight

In **Survey**, select **Fly Plane** and click a tile of a built Country or
City Airport. Aiming at the airport and typing `/plane` also works.
You sit behind the working view windows in a Sampson trimotor. It is a
local sightseeing vehicle; it does not join the airline, change its slots,
transport anyone, or charge the company.

- **W / S** increase / reduce power. It stays where you left it.
- **Space / Shift** pitch up / down. Hold **W + Space** for the takeoff roll.
- **A / D** bank left / right. Release to level.
- **E** resets to the departure runway if it is still visible to the
  server and safe. Otherwise it returns to the builder view.
- **Right-click** or **`/plane`** exits to your previous position, aim, tools
  and movement controls.

For a manual landing, line up with a visible runway, reduce power,
level the wings and descend shallowly at about **55–110 km/h**. Leave
enough runway ahead to stop. A fast, steep, sideways or off-pavement
approach is rejected rather than moving the plane through terrain.
Takeoff and landing use stock runway directions and elevations. All units
use the game's compressed scenic scale. The HUD points back toward your
departure airfield. Use the client's first-person camera to see out of the
cockpit if you have switched the engine to an external camera.

The private cockpit has a separate camera-origin mesh so the dash and
physical windshield pillars are visible without obstructing the scenery.
Fellow players see the original exterior instead. Propeller power layers
crossfade, wind grows with airspeed, and a gentle gear cue plays once on
touchdown. Original procedural assets can be rebuilt using
`tools/build_sightseeing_plane_cockpit.py` (Pillow) and
`tools/build_sightseeing_plane_audio.py` (ffmpeg).
