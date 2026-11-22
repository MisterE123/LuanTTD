# Manley–Morel DMU, #11

Original 3D powered-car asset for the paired stock Manley–Morel DMU.
The pinned [OpenTTD 14.1 engine table](https://github.com/OpenTTD/OpenTTD/blob/14.1/src/table/engines.h)
defines temperate #11 as `RVI(8, M, 11, 112, 600, 32, 85, RC_D, 38, R, D)`,
where `M` is multiheaded and the capacity is **38 passengers per
head**. [The train implementation](https://github.com/OpenTTD/OpenTTD/blob/14.1/src/train_cmd.cpp)
uses image 8 for its front stock part and the next index for the rear.
OpenGFX maps base 2949 to (111,151) in its
`temperate_engines_28px.png`; no palette or sprite extraction is used
in this model.

The [OpenTTD manual](https://wiki.openttd.org/en/Manual/Base%20Set/Trains/Train%20Comparison)
identifies the real equivalent as a Metro-Cammell DMU, and the
[OpenTTD archived graphics reference](https://wiki.openttd.org/en/Archive/Old%2032bpp/Rail%20Vehicles%20%28New%20Graphics%29)
specifies Class 101. The original model refers visually to kitmasterbloke's
[*Metro-Cammell Class 101 DMU*](https://commons.wikimedia.org/wiki/File:Metro-Cammell_Class_101_DMU.jpg),
1 June 2013, Midland Railway Centre, [CC BY 2.0](https://creativecommons.org/licenses/by/2.0/).
The reference helped inform the three-pane driving ends, period roof,
doors and two-car connection. No photographic pixels, stock
sprites, or trademarks are included.

## Mount

- Model files `bl_rail_manley_morel.obj` and `bl_rail_manley_morel.png`
  in the mod's native model/texture directories are one *physical*
  powered car, not a complete two-car unit. Render each of the two
  parts at its own stock pose. At neutral yaw the three-pane,
  mustard-panel driving end is at **−Z** and the dark fitted inner
  vestibule at **+Z**. The two driving ends must face outward.
  Both use the same asymmetric geometry, so one part is rotated by
  180° relative to the other on straight track.
- Unit scale on .424 rail centers, Y=0 local tire contact
  (+.614 above base zero on flat track), one native node center to
  center, coupler tips ±.499 at Y=.157. Real passenger-window
  layering, two two-axle bogies per powered half, and underfloor
  power/radiator detail. Each shell uses native one-model lighting.
- `art/rail_manley_morel.blend` has independent editable wheel pivots
  and named components. Regenerate via
  `blender -b -t 3 --python-exit-code 1 --python tools/build_manley_morel_art.py`.
  Optional `MANLEY_MOREL_REVIEW=/path/to/preview.png` gives a studio
  view of the opposed driving and inner ends.

## QA

`python3 tests/manley_morel_art.py` verifies wheel contacts, paired
unit-radius poses, and physical portal clearance. Optional
`--upstream-engines`, `--upstream-train-sprites` and `--opengfx-trains`
check the data against pinned upstream tables. The graphical fixture
`tests/manley_morel_art_native.sh` inspects two actual cabs on native
stock tracks, including a close view of the two distinct coupled
gangway ends. This is art verification, not a claim of paid operation.
