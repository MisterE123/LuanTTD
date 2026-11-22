# Masonry road tunnel portal

`road_tunnel_portal.blend` contains an editable original masonry portal
for OpenTTD-style road tunnels. The visual design combines patterned
limestone wing walls, a chamfered cap, individually modeled fired-clay
voussoirs and keystone, and a dark vaulted brick bore. The approach is
a genuine cut in the terrain mesh. The bore is open at both ends of
the portal and continues to the inside tile edge; it is not a textured
wall or a black face with a model pasted over it. Original LuanTTD
art, with no upstream sprites, textures, or geometry reused.

## Runtime contract

- Use `bl_road_tunnel_portal_{dir}.obj` and `bl_road_tunnel_portal.png`.
  Direction points **uphill and into the tunnel** in stock 14.1
  `DiagDirection` order: 0=-X, 1=+Z, 2=+X, 3=-Z. The portal matches stock
  entrance inclines 12, 6, 3 and 9 respectively. See OpenTTD 14.1
  `src/tunnelbridge_cmd.cpp`, `CmdBuildTunnel` and
  `GetSlopePixelZ_TunnelBridge`.
- Place as the one inclined tile overlay at `(2*x, base+1, 2*z)`, where
  `base` is the low-edge terrain height and the tunnel floor level. Keep
  the solid ground layer at Y <= `base`, and **replace** the ordinary
  inclined terrain shell on the portal tile. The mesh itself supplies
  the grassy flanks and roof. Placing it on top of terrain leaves the
  uncut original hill inside the road.
- Both lanes keep logical Y `base+.5` throughout. The visible pavement
  has a .004-node depth bias to avoid flickering against the underlying
  ground cubes; it tapers to zero at both tile seams. Asphalt is .625
  node wide with .0625 shoulders; the
  road surface is centered at X/Z `(2*x+.5, 2*z+.5)`. Both road edges end
  exactly at the tile seam with ordinary materials and no dash crossing
  the seam. The original terrain's side and uphill edge elevations
  remain unchanged. Behind the tile, ground rendering and actual
  traversal/masking through the mountain are runtime responsibilities.
- The native passage is .844 node wide, with sixteenth-arch facets
  reaching .653 node of interior height at center. Actual shipped
  road vehicles fit both lanes at their current native visual scales.
  Separate tram clearance and overhead hardware are not included.

## Regeneration and QA

```sh
blender -b -t 3 --python-exit-code 1 --python tools/build_road_tunnel_art.py
python tests/road_tunnel_art.py
ROAD_TUNNEL_RENDER=/tmp/portal.png blender -b -t 3 --python-exit-code 1 --python tools/build_road_tunnel_art.py
BAYLINE_NATIVE_TOOLS=/tmp/bayline-run BAYLINE_NATIVE_TCP=1 bash tests/road_tunnel_art_native.sh
```

Structural regression uses the exported triangles in all four stock
directions, checking the asphalt and ground seams, the open rear end,
2,520 road-vehicle rays, and continuous bounding-prism clearance from
the actual bus, truck, coach, Leopard bus and mail van meshes. The
native fixture loads the actual node art next to ordinary roads and
slopes with two bus actors in the opposing lanes. It is graphical QA,
not a test of player construction or journey state.
