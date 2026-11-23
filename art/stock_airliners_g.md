# Bakewell Luckett LB-8 and Darwin 300

Original editable Blender commercial jets matching the independently verified OpenTTD 16.0-RC1 stock identities. Both are large fast CTOL; they do not represent short-runway-compatible aircraft. No OpenGFX source pixels, branding or model assets are included. The stock external image switches by compass direction only; these exports use one fixed exterior each, not a fabricated per-flight-phase shell swap.

| Stock engine | AVI row / image / sprite | Passengers / mail | Native model dimensions (W × H × L) |
| --- | --- | --- | --- |
| #220 Bakewell Luckett LB-8 | 5 / 6 / 3741 | 200 / 30 | 1.8060 × 0.5995 × 2.0050 |
| #228 Darwin 300 | 13 / 7 / 3749 | 300 / 50 | 1.8960 × 0.6925 × 2.1680 |

- LB-8 has an original early low silver airframe with 4 long, narrow underwing engines, separate metal-colored pylons, low tailplane and undercarriage with six independent ground contacts.
- Darwin 300 has a visibly broader original powder-blue pressure shell with integrated two-level forward cabin, four large independently modeled open turbofan nacelles and articulated two-axle bogies, plus nose gear (18 individual tires). Its slightly foreshortened ogive keeps the full-size asset clear of City Airport's edge equipment during the stock runway turn. The wing and four-pod geometry are not rescaled.
- All eight engine intakes are real annular openings with recessed fan geometry. Gear and fuselage side material variation are editable geometry; there is no texture from the upstream vehicle art.

The Blender files are `art/stock_bakewell_luckett_lb8.blend` and `art/stock_darwin_300.blend`. Production models/atlases use matching `bl_stock_...` basenames under `mods/luanttd_core/{models,textures}`. Use visual scale **1.0**, local −Z nose and wheel treads Y=0.

## Build and check

```sh
blender -b -t 3 --python-exit-code 1 --python tools/build_stock_airliners_g_art.py
python tests/stock_airliners_g_art.py
```

Requires the repository's previously integrated `build_stock_airliners_e_art.py` and `build_stock_darwin_100_art.py` utility geometry. Set `AIR_G_REVIEW` to an existing output directory for optional Blender front/profile/ventral renders, or `AIR_G_STEM` to rebuild only one. For isolated builds set `LUANTTD_HELPERS` and `LUANTTD_BASE`. Tests may accept `--engines`, `--aircraft`, `--opengfx`, `--city-layout` and `--city-movement` to confirm raw upstream pins and runway.

Verification checked all four intake bores independently per airframe, authored road-free grounded tires and native pose. Each cleared 3,961 exact/interpolated City Airport ground poses. On the actual City runway-wearing course, 1,872 LB-8 and 5,640 Darwin 300 tire points all had support. Tightest margins were .33371 and .17557 nodes respectively. Aircraft-vs-aircraft clearance and world integration are separate concerns.

## Reference

- [OpenTTD 16.0-RC1 engines table](https://github.com/OpenTTD/OpenTTD/blob/16.0-RC1/src/table/engines.h), blob `1f71919c2399ebe7053cd78a306a96fb59e25def`, and [aircraft sprite dispatcher](https://github.com/OpenTTD/OpenTTD/blob/16.0-RC1/src/aircraft_cmd.cpp).
- [OpenGFX aircraft slot mapping](https://github.com/OpenTTD/OpenGFX/blob/master/sprites/base/base-3741-aircraft.pnml), blob `e6ebd63046de845a05dc481c88ab7f4d2fce0208`; [3741 silhouette sheet](https://github.com/OpenTTD/OpenGFX/blob/master/sprites/png/aircraft/BL-LB8-YateYAe46.png), blob `7691cb763a986211ebdb90df29b6933049709ff2`; [3749 silhouette sheet](https://github.com/OpenTTD/OpenGFX/blob/master/sprites/png/aircraft/Darwin300.png), blob `67e58cff2d0a1604a70ffaeed58ba22807a9773b`.
- OpenTTD's manual describes the real-life counterparts as the [DC-8 (LB-8)](https://wiki.openttd.org/en/Manual/Base%20Set/Aircraft/Bakewell%20Luckett%20LB-8) and the [747 (Darwin 300)](https://wiki.openttd.org/en/Manual/Base%20Set/Aircraft/Darwin%20300). These are shape cues; all model components and pigment selections are independent.
