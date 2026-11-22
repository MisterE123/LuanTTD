# Cut-limestone aqueduct

The editable `aqueduct.blend` is an original stone waterway library
for the OpenTTD 14.1 aqueduct construction and stock canal class. Under
the water are an actual retaining floor and lined sides.
The raised water does not tilt over the natural slopes: the channel stays
level from the outside canal edge through both heads and the entire
crossing. Its staged flares widen into the adjoining canal before the
stone parapets rise.

The original mesh includes air above the open channel, sloped grassy
abutments, rusticated external courses with staggered inset blocks,
moist inner masonry, weep details, and separate masonry bearings and
stacked piers. No stock artwork was reused.

## Runtime contract

All models use `bl_aqueduct.png` and the normal even logical-tile
X/Z anchor `(2*x, 2*z)`, giving world lane center
`(2*x+.5,2*z+.5)`.

| Prefab | Node Y | Notes |
| --- | --- | --- |
| `bl_aqueduct_head_{dir}.obj` | `deck` | Widened outside basin and retaining side slopes; heading points toward the other head, stock order `0=-X, 1=+Z, 2=+X, 3=-Z`. |
| `bl_aqueduct_span_{axis}.obj` | `deck` | Repeated interior, axis `0=X, 1=Z`. No full-height support is baked in. |
| `bl_aqueduct_pier_head_{axis}.obj` | `deck-1` | Optional upper pier/capital reaches the underside at mesh Y +1.115. |
| `bl_aqueduct_pier_{axis}.obj` | `deck-2`, then lower | Optional matching stacked shaft, endpoints at mesh Y ±.5. |

The water plane is mesh Y +.5 on both head and span. It is **1.12
nodes wide** throughout the trough. At the outside edge of a head the
opening is the full two-node width, matching an external canal at the
same water level. Both interfaces use the same stock native water
palette and no wave crosses the outer tile edge. The head side
slope in the mesh rises to the outside and falls one unit toward the
span, in the same orientation as the raw stock bridgehead terrain.
Keep underlay terrain/infrastructure in its own layer and show
optional support only where no active transport layer would be
obstructed.

The Bellhaven ferry's shipped mesh is 0.762 node across with the mast
0.903 node above its origin. Its full hull and mast sweep clear the
opening with a ±.10-node centering margin. Where the underlying route
is preserved, the no-pier span clears normal road vehicles one native
level below, and the current locomotives two levels below. This is
mesh clearance, not a simulation restriction or a claim that all
possible native underlays are safe at one level.

## Regeneration and proof

```sh
blender -b -t 3 --python-exit-code 1 --python tools/build_aqueduct_art.py
python tests/aqueduct_art.py
AQUEDUCT_RENDER=/tmp/aqueduct.png blender -b -t 3 --python-exit-code 1 --python tools/build_aqueduct_art.py
BAYLINE_NATIVE_TOOLS=/tmp/bayline-run BAYLINE_NATIVE_TCP=1 bash tests/aqueduct_art_native.sh
```

The structural test verifies all ten exports and 64 seams in four
stock directions, positive clear width through the full loft, the
open mast sweep, assembled pier bearing, and continuous safe underlay
volumes triangulated from the exported meshes. The isolated graphical
fixture shows the real Bellhaven in a connected channel, with a bus
and locomotive below, in three native Linux camera views. It does
not alter a campaign or test player construction and trip logic.
