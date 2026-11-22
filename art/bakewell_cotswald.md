# Bakewell Cotswald LB-3

Original LuanTTD visual art for stock OpenTTD 14.1 engine **219**. In the
[14.1 engine table](https://github.com/OpenTTD/OpenTTD/blob/14.1/src/table/engines.h),
the aircraft is data row **4**, sprite reference **5**, subtype **P** (small
propeller aircraft), with a base introduction date 4,929 days after 1920
and stock capacity of **30 passengers and 6 bags of mail**. These numerical
references identify the aircraft only. No proprietary or OpenGFX image,
mesh, licensed asset, or pixel data was reproduced, sampled, or bundled.

The original design uses a period rounded DC-3-style transport silhouette:
a narrow cream cabin, brushed gray wings, burgundy waist and rudder band,
tapered low-mounted wing and twin radial nacelles, with two physical
three-blade props. The front quarter glass conforms to the actual curved
nose. The ground variant has a paired axle main undercarriage and a small
rear wheel, and the flight variant replaces those wheels and struts with
closed bay doors. Props are static parts of these exports.

## Authoring and scale

- Editable **`bakewell_cotswald.blend`** contains named, part-separated
  original mesh geometry. Switch the two gear collections to compare ground
  and flight. No linked asset dependencies or external textures.
- Native files: `bl_bakewell_cotswald.obj`, `bl_bakewell_cotswald_flight.obj`,
  and the single `bl_bakewell_cotswald_atlas.png` palette.
- At entity scale **1**, the model spans **1.8806** Luanti nodes, measures
  **1.416** nose to tail, and reaches **.628** above tire datum. Engine OBJ
  nose is local −Z, up is +Y, and **10 OBJ units = 1 Luanti node**. Each
  tire touches world/local Y=0 exactly; minimum gear-up Y is **.0787**.
  Gear exchange uses the same origin and hull positions.
- The two runtime variants and atlas compress to approximately **84 KB**.
  Meshes retain convex original polygon strips and shared compact normals.

## Reproduction and checks

```bash
blender -b -t 3 --python-exit-code 1 --python tools/build_bakewell_cotswald_art.py
LUA=/path/to/lua python3 tests/bakewell_cotswald_art.py /path/to/OpenTTD-14.1
BAYLINE_NATIVE_TOOLS=/path/to/native/tools tests/bakewell_cotswald_art_native.sh
```

Set `BAKEWELL_REVIEW=/path/to/portrait.png` to create an original Blender
review image. The runtime test uses the actual OBJ and atlas in Linux
Luanti, with static specimens at a Country Airport stand, the original
hangar pose, and above the airport gear-up. Separate geometry tests replay
1,231 stock ground poses from both stands and the hangar; the conservative
hull clears all obstacles. Neither test changes a player's world.
