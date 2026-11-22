# Vehicle turn direction: Luanti 5.10.0 source and mesh checks

There are two distinct angles: route heading (`atan2(dx,dz)`, +Z at zero),
and the server entity yaw that orients this particular vehicle mesh. Use
route heading or tangents for road lane offsets, and convert only when
submitting a mesh rotation.

## Why the older renderer turns the wrong way

- [Luanti client scene transform](https://github.com/luanti-org/luanti/blob/5.10.0/src/client/content_cao.cpp#L1001-L1015)
  applies the negative of the networked Euler angles to remote meshes.
  At zero pitch/roll its [matrix helper](https://github.com/luanti-org/luanti/blob/5.10.0/src/util/numeric.cpp#L175-L193)
  transforms local +Z to horizontal `(-sin(yaw), cos(yaw))`; local
  -Z therefore becomes `(sin(yaw), -cos(yaw))`.
- The bus mesh faces **local -Z**: all exported lamp-color face corners
  have OBJ Z between -7.935 and -7.725; all brake-color corners have Z
  between +7.710 and +7.930. These are palette positions 6 and 7
  (zero-based) in `bl_town_flyer.obj`. Truck headlamps are also at -Z.
- Therefore an entity using the raw route yaw mirrored the visible nose
  in world Z and reversed the visible direction of each turn. The proper
  road vehicle mesh yaw is `atan2(dx, -dz)`, equivalently
  `pi - route_yaw` modulo one revolution. Uphill pitch remains negative
  for a local -Z mesh.

## Interpolation and edge cases

[Received updates](https://github.com/luanti-org/luanti/blob/5.10.0/src/client/content_cao.cpp#L1682-L1711)
normalize the target angles, then the [client rotation translator](https://github.com/luanti-org/luanti/blob/5.10.0/src/client/content_cao.cpp#L103-L133)
uses wrapped angular distance. `set_yaw` and `set_rotation` both set the
server rotation in degrees after converting Lua's radians. Changing the
method name or sending multiple unwrapped revolutions is not a fix.
The movement interpolation flag does not suppress rotation interpolation.
The [wrap helper](https://github.com/luanti-org/luanti/blob/5.10.0/src/util/numeric.h#L441-L457)
normalizes positive overflow and chooses the negative direction at an
exact half-turn. Its intermediate negative yaw can fall below zero
before the target is reached, so rapid reversal at the seam is worth
checking in the real client.

For app-side smoothing choose the signed distance using
`(target - current + pi) % (2*pi) - pi` before taking a bounded step.
Do not linearly interpolate raw `atan2` values. An actual 180° reversal
should use an explicit sign or visible U-turn; a numeric half-turn tie
does not express a chosen turning side. On an ordinary corner, align
app-side samples with the same geometry/tangent as the bus position.
Preserve or recompute the proper heading on a stop and newly visible
spawn; avoid transient default yaw and make sure a departed vehicle is
not still inheriting a stale arriving heading.

Native checks: inspect the bus nose in all four travel directions, a
clockwise and counterclockwise 90° corner, a corner next to the wrap seam,
and a station reversal separately. A position trace alone cannot verify the
client mesh orientation.
