# Temperate wildlife art

The packed `wildlife.blend` and `tools/build_wildlife_art.py` are the
original source. No upstream sprites, external meshes or photographs were
used. All animals are individually modeled and placed in named collections.
The Review studio normalizes their display sizes for side-by-side inspection;
the Workshop scene contains unscaled, individually editable geometry. The
source also keeps the alternate flight and stride collections.

| Export stem | Anatomy and pigments | Native extent |
| --- | --- | --- |
| `whale` | Humpback-inspired domed head with rostral tubercles, paired blowholes, dark back, pale tapered pectorals, lower throat pleats and a deeply notched tail. | 3.93 nodes from rostrum to fluke |
| `porpoise` | Harbor-porpoise-inspired blunt snout, triangular dorsal fin, short flippers with gray countershading and smaller split fluke. | 1.03 nodes long |
| `seagull` | A pale coastal gull with a yellow bill, dark wingtip chatter and individually modeled trailing feathers. | 0.71-node wingspan |
| `eagle` | A mature bald-eagle silhouette with a pale tail and neck, golden hooked bill and separately modeled broad primary feathers and talons. | 1.10-node wingspan |
| `fox` | Long red coat, pointed ears, tapered muzzle, low dark ankles and a pale-tipped brush. All four feet are separately modeled. | 0.82 nodes including the brush; 0.38-node trunk |

Engine assets are `bl_wildlife_<stem>.obj` with the shared external
`bl_wildlife_atlas.png`. Their OBJ coordinates are +Y upwards, +Z forward, at
10 units per engine node. For cetaceans, Y=0 is the nominal waterline; an
animation may smoothly submerge or breach from that reference. For birds, the
origin is the middle of the torso, shared across all wing positions. The fox
has Y=0 foot contact in both poses.

Bird `_wing_up` and `_wing_down` variants and the fox `_stride` variant
reuse the palette, body vertices and pivot. Each part is closed even at the
fin tips and tail notches. These visuals carry no collision or economy data.

Rebuild and check:

```sh
blender -b -t 3 --python-exit-code 1 --python tools/build_wildlife_art.py
python3 tests/wildlife_art.py
```

Set `LUANTTD_WILDLIFE_REVIEW` to an image path before rebuilding to render
the studio contact sheet as well. No Blender plug-ins are required.
