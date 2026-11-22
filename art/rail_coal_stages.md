# Cedar Coal and Riverbend rail transfer platforms

`rail_coal_stages.blend` holds eight editable full-size native stage
collections and an assembled 3D review scene. This is original LuanTTD
art for the coal loading and receiving roles of an ordinary rail
station. Neither OpenTTD sprite art nor imported geometry is used.
The two facilities are independent of the six-tile Cedar Coal mine
and four-by-two Riverbend Power Station assets. Stations may sit next
to those industries; they do not change or occlude industry footprints.

- **Loader:** A riveted open lattice tower holds a real four-wall surge
  hopper. Coal is visible on a trough belt and inside the open hopper;
  shaft bars, rounded belt idlers, ladder treads, gate actuator and a
  flanged telescoping chute are independently modeled. The chute stops
  high enough for the largest existing electric engine.
- **Receiver:** A pitched standing-seam roof on brick piers shades
  rotary cradle frames in their through position. Their shaped side
  tipping throat empties into a genuinely open receiving sump with
  individual grizzly bars and coal below them. A separate motor housing,
  drive linkage and relay panel identify the machine end. The normal
  rails stay fixed; tilting, belts and cargo discharge are not animated
  by these models.

## Mount contract

Use the shared `bl_rail_coal_stage_atlas.png` with each node mesh.
The prefix is `bl_rail_coal_stage_`, followed by `load` or `unload`,
an axis and the optional `_mirror` suffix. For example,
`bl_rail_coal_stage_load_1_mirror.obj`.

| Axis | Rails run | Normal service side | Mirrored service side |
| --- | --- | --- | --- |
| 0 | X | +Z | -Z |
| 1 | Z | +X | -X |

Mount as one complete mesh on the even corner node
`(2*x, base+1, 2*z)`, center `(2*x+.5, 2*z+.5)`. Keep the ordinary
terrain underneath. **Do not** also mount plain rail or a passenger
platform on that tile. The module already has the exact same rails,
sleepers, ballast, colors and end seams as ordinary stock straight track.

- Standard .424-node gauge and running crown `base+.614` throughout.
- Flat platform coping is .282 above formation, matching the existing
  passenger station coping, with nearest edge .358 from rail center.
- Every stage fits wholly in one two-node by two-node stock tile;
  continuous same-side platform coping meets adjacent tiles. Recessed
  stone ends avoid doubled faces at the join. Flush safety lines and
  contraction joints partition one deck surface.
- Rail corridor testing keeps .604 clear width through .940 above
  formation. The loading chute starts at +1.030; top of the kit is
  +1.746. The vehicles checked are the Kirby Paul Tank, electric engine,
  standard coach and open coal wagon.
- Both directions have legible enamel signs. Mirroring swaps the working
  side only; it does not change stock acceptance or catchment or alter
  direction of vehicle motion.

## Rebuild and check

```sh
RAIL_COAL_STAGE_RENDER=/tmp/coal-stages.png blender -b -t 4 --python-exit-code 1 --python tools/build_rail_coal_stage_art.py
python tests/rail_coal_stage_art.py
BAYLINE_NATIVE_TOOLS=/tmp/bayline-run BAYLINE_NATIVE_TCP=1 bash tests/rail_coal_stage_art_native.sh
```

The geometry check verifies all eight footprints, the standard rail and
ballast cross sections on each seam, checks the deck for overlapping
faces and that the receiving pit stays open, matches the shared rail material
palette, checks the clear vehicle corridor and probes the actual
receiving pit. The native Linux fixture shows both facilities connected
to ordinary track next to the original mine and power plant, with
standard-coupled Kirby and open-wagon sets. This is art and mounting
QA, not loading, acceptance, train movement, or payment simulation.
