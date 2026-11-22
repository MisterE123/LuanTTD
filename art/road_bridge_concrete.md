# Short cast-concrete road bridge

The editable `road_bridge_concrete.blend` models OpenTTD 14.1's
**Concrete** bridge, stock catalog ID **1**, using original geometry
and colors. The warm oxide fascia is set into a shallow cast-concrete
haunch with real drainage relief. The concrete parapets have open
arched pockets rather than painted holes. Tapered concrete crossheads
and modular stone-faced columns carry the deck.

Stock catalog (`src/table/bridge_land.h`): available at year **0**,
**zero to two interior tiles** (two to four total), 112/256 construction
multiplier, speed field 48 (road-motion cap 96 internal half-km/h units).
The catalog does not set a separate terrain clearance: stock
`CmdBuildBridge` requires interior terrain max height at most the
portal foundation base, and deck level is that base plus one. This
art also leaves moving-road clearance in the native 3D model: the four
haunch legs flank both lower-road alignments, rather than projecting
into either asphalt/shoulder corridor on the lowest deck. Stock
operational permissions remain the simulation's responsibility.

## Asset/placement contract

Use `bl_road_bridge_concrete.png` with all
`bl_road_bridge_concrete_*.obj` models. Placement matches the
[timber](road_bridge_wood.md) and [steel girder](road_bridge_girder.md)
library. Each prefab is anchored at `(2*x, deck_level, 2*z)`
and uses the same exact road width, materials, stripe cadence, and
position: `(2*x+.5, deck_level+.5, 2*z+.5)` on a level deck.

- `span_0.obj` spans X; `span_1.obj` spans Z. Level running surface.
- `head_flat_{dir}.obj` has a level deck through the head. Use where the
  underlying post-foundation terrain falls into the bridge.
- `head_ramp_{dir}.obj` rises one node from outer local Y -.5 to inner
  local Y +.5. Use where post-foundation terrain is flat.
- Head direction points inward: 0=-X, 1=+Z, 2=+X, 3=-Z. Both head
  variants join directly or to the interior span.
- `pier_{0,1}.obj` stacks vertically at Y `deck_level-1`,
  `deck_level-2`, etc.; the footprints meet the cap at each joint.
  Leave terrain, water, and existing roads independent of the supports.

## Regeneration and QA

```sh
blender -b -t 3 --python-exit-code 1 --python tools/build_road_bridge_concrete_art.py
python tests/road_bridge_concrete_art.py
CONCRETE_BRIDGE_RENDER=/tmp/concrete.png blender -b -t 3 --python-exit-code 1 --python tools/build_road_bridge_concrete_art.py
BAYLINE_NATIVE_TOOLS=/tmp/bayline-run BAYLINE_NATIVE_TCP=1 bash tests/road_bridge_concrete_art_native.sh
```

The tests verify 144 seams across both axes, exact shared road
surfaces, support stacks, the open parapet pockets, and continuous
lower-road clearance at minimum deck elevation. The graphical fixture
uses the two-interior-tile legal maximum, with buses on the main deck
and a real-size bus between the supports on the lower road. This is
asset QA, not a test of the live player construction command.
