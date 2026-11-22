# SH '40': stock engine #24

Original native Class 87 variant of the shared image-20 electric locomotive,
with editable Blender source. [OpenTTD 14.1's engine table](https://github.com/OpenTTD/OpenTTD/blob/14.1/src/table/engines.h)
gives #24 the single-head electric row
`RVI(20, G, 30, 176, 5000, 82, 205, RC_E, 0, C, E)`
(176 km/h, 5,000 hp, 82 t); #23 and #24 deliberately share the same image
index. The [14.1 sprite index](https://github.com/OpenTTD/OpenTTD/blob/14.1/src/table/train_sprites.h)
maps that index to 2937; [OpenGFX 7.1](https://github.com/OpenTTD/OpenGFX/blob/7.1/sprites/base/base-2905-rail-vehicles-engines.pnml)
uses a temperate blue/grey body and yellow cab ends.

The [OpenTTD manual](https://wiki.openttd.org/en/Manual/Base%20Set/Trains/SH%20%2740%27)
identifies the British Rail Class 87. The [AC Locomotive Group's Class 87 history](https://aclocogroup.co.uk/index.php/history-introduction/ac-history-2nd-generation-locos/class-history-87)
documents the closely related Class 86 layout, original Rail Blue and yellow
ends, and absence of a front route-indicator box. This model deliberately keeps
the shared original [SH '30' body and running gear](rail_sh_30.md), uses its own
blue/yellow swatches and raised fictional SH40 lettering on each flank, and
leaves the yellow space between the cab lamps clear of the previous headcode
box. No historical or upstream graphics, survey data or photographed pixels
are shipped. Geometry and textured materials remain editable; game geometry
is rigid, not an animated pantograph or bogie rig.

## Build and mount

- `bl_rail_sh_40.obj`, `bl_rail_sh_40.png`, separate `rail_sh_40.blend`.
- Native scale 1, local −Z nose, .424 gauge, Y0 on the rail crown; standard
  coupling tips at Z≈±.499. At flat track base+.614, the shoe upper edge
  contacts the shared catenary underside at base+1.398. Shoe center Z=.031,
  width .166 and height .784 above the rails. Same SH '30' datum, with no
  change to support or contact surfaces.
- Regenerate:
  `blender -b -t 2 --python-exit-code 1 --python tools/build_sh_40_art.py`.
  `SH_40_REVIEW=/path/preview.png` also makes a Blender overview.
- `python3 tests/sh_30_art.py --variant 40` checks the actual meshes:
  independent SH40 ID on both sides, shared geometry exact, wheel tread,
  coupled stock cars, portal clearance and shoe contact. Optional
  `--upstream-engines`, `--upstream-train-sprites` and `--opengfx-trains`
  check the pinned tables from local files.
- `tests/sh_30_art_native.sh 40` uses the actual OBJ and flat catenary
  in an isolated Luanti client, with ground, survey, curve, wire and
  close-side lettering views. This asset fixture does not test buying,
  running costs, or shop/dispatch logic.
