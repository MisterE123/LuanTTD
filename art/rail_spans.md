# Original timber rail trestle and masonry rail tunnel

`rail_spans.blend` contains 16 editable collections and a 3D showcase.
The timber bridge is a standard-gauge open track deck on four
pitch-pine stringers, with inspection walkways, check rails, forged
fasteners, coursed ashlar abutments, and cross-braced repeating bents.
Approach wings lead into a limestone and fired-clay railway tunnel with
a genuinely open hollow vault. This is original LuanTTD art. No stock
OpenTTD meshes, sprites, or textures were used.

The dimensions refer to pinned OpenTTD 14.1 `src/tunnelbridge_cmd.cpp`
(`CheckBridgeSlope`, `CmdBuildTunnel`, and the bridge/tunnel height query)
and LuanTTD's existing shared track geometry. Actual construction,
under-bridge occupancy, catenary, availability, reservations and train
visibility are separately owned by the gameplay implementation.

## Rail deck, heads and supports

All bridge pieces use `bl_rail_bridge_wood.png`.
Mount straight span and either bridge head at the native even position
`(2*x, deck_level, 2*z)`. Tile center is offset `(+.5, 0, +.5)`.
`deck_level` means the stock bridge formation level; formed deck
surface on the bridge itself is at Y `deck_level+.5`.
Rails have the same .424-node gauge and vertical profiles as
ordinary rail; the actual wheel contact is Y `deck_level+.614`.

| OBJ suffix after `bl_rail_bridge_wood_` | Layout |
| --- | --- |
| `span_{axis}` | Interior tile repeated by planner, axis 0 = X, 1 = Z; crown Y +.614. Includes structural cap and upper timber ends. |
| `head_flat_{dir}` | Approach remains level over stock outward-rising slope; both rail crown edges +.614. Includes the founded outward-rising terrain shell, so don't also place the standard slope mesh at this anchor. |
| `head_ramp_{dir}` | Rises on flat land at the head; outside crown Y -.386, interior +.614. |
| `pier_{axis}` | Independent optional stackable bent directly below bridge deck. Place at Y `deck_level-1, deck_level-2, ...`; timber fits exactly between local -.5 and +.5. Not a solid tile collision envelope. |

Head direction points **toward the other head**:
0=-X, 1=+Z, 2=+X, 3=-Z. A zero-interior bridge can join two heads directly
without rail, fence, or check-rail gaps. Preserve separate landscape
layers on and underneath the bridge. To keep pilings out of an
underpassing road or navigation channel, choose support placement in the
scene builder; this geometry does not fence water or every terrain tile.

## Tunnel portals

- `bl_rail_tunnel_portal_{dir}.obj`, atlas `bl_rail_tunnel_portal.png`.
  Heading is **uphill and into the bore**: 0=-X slope 12, 1=+Z slope 6,
  2=+X slope 3, 3=-Z slope 9.
- Mount at native even `(2*x, base+1, 2*z)`. Keep underlying ground up
  through Y `base` but **replace** the usual inclined terrain mesh on
  this tile. The art has its own cut banks with exact outer terrain
  seams and an open rear. The .424-gauge track crown at both entrances
  is Y `base+.614`; its rails continue to the edge under the hill.
- The visible masonry face begins at +.633 in tile-center coordinates,
  .367 short of the high seam. The .974-node clear bore continues
  underneath the hill, with central vertical clearance 0.999 nodes
  above the formation, or .885 above rail crown. All existing locomotives
  and the two stock-length wagons clear the actual faces. The slight
  embankment immediately behind the front crown comes back to the stock
  incline at the tile seam. Interior engine/consist masking after entering
  the overburden is a runtime responsibility, not hidden box art.

## Rebuild and verify

```sh
RAIL_SPAN_RENDER=/tmp/rail-spans.png blender -b -t 4 --python-exit-code 1 --python tools/build_rail_span_art.py
python tests/rail_span_art.py
BAYLINE_NATIVE_TOOLS=/tmp/bayline-run BAYLINE_NATIVE_TCP=1 bash tests/rail_span_art_native.sh
```

The structural check compares actual exported vertices at ordinary-track,
head, span, direct and shaft seams; verifies graded perimeter continuity,
shoots clearance rays all the way down the physical bore, and checks the
actual rolling-stock envelopes under its arch, including the electric
pantograph. The isolated Luanti visual check loads the shipped assets next
to ordinary grass/track with original rolling stock placed on the rails
for river-survey, wheel/rail contact, and tunnel mouth inspection. This is
not a proof of gameplay construction, traversal, or reservations.
