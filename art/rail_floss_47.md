# Floss '47'

Original model for [OpenTTD 14.1](https://github.com/OpenTTD/OpenTTD/blob/14.1/src/table/engines.h)
temperate engine **#15**, standard-rail diesel, stock image index 4 and one
full-length head. The pinned catalog entry is
`RVI(4, G, 18, 160, 2580, 112, 140, RC_D, 0, R, D)`.
This is the single-catalog-vehicle body, not a permanently paired engine.

Its proportions reference a full-size Brush Type 4. The dual cabs have
shaped yellow ends, individually installed black glazing, bead lines and
wipers. It has two distinct three-axle bogies with real wheel discs and
inner flanges, reservoirs, separately stamped radiator grille slats and
two actual recessed roof apertures with shaped nine-blade fans below
crossed guards. The livery is an original green-and-sage fleet design,
not a BR logo, decal or pixel-art transfer.

## Reference and authoring

- Muchclag at English Wikipedia, [47851 Traction Magazine](https://commons.wikimedia.org/wiki/File:47851_Traction_Magazine.JPG),
  May 2005, [CC BY-SA 3.0](https://creativecommons.org/licenses/by-sa/3.0/);
  a photograph of the preserved Class 47 in two-tone green, visually
  consulted for end glazing, cab-to-roof profile and side cooler recesses.
  No image crop, vector trace, texture, mesh or branding from the
  photograph or either upstream sprite set is included.
- The editable `art/rail_floss_47.blend` has two swiveling bogie pivots,
  each of their three moving axle pivots, separate working fan rotors and
  individually named permanent assemblies. Frames 1–49 expose the
  wheel and rotor motion; no runtime Blender animation is exported.
- `mods/luanttd_core/models/bl_rail_floss_47.obj` and
  `mods/luanttd_core/textures/bl_rail_floss_47.png`: static mesh and original
  flat swatch texture atlas. Use unit scale, native nose -Z and zero
  tire-crown datum at world +.614 on flat base-0 track. Rail spacing is
  .424; centered coupling tips at ±.499 with Y=.157. The doors and buffers
  are set inward to fit the radius-one stock curve without clipping
  stock car bodies, not drawn at literal British Rail scale.
- Regenerate with `blender -b -t 3 --python-exit-code 1 --python tools/build_floss_47_art.py`.
  Optionally set `FLOSS_47_REVIEW=/path/to/preview.png`.

## Verification

- `python3 tests/floss_47_art.py --upstream-engines /path/to/OpenTTD/src/table/engines.h`
  verifies the pinned stock entry, round fan recesses, 12 tread contacts
  on real railheads, both axes and both curve hands, clearance to
  passenger, open freight and loaded coal stock, and the native tunnel
  portal. As with other stock heads, a few extremes can graze fixed
  coupler/buffer hardware; no frame or car body intersections are allowed.
- `blender -b art/rail_floss_47.blend -t 2 --python-exit-code 1 --python tests/floss_47_blender.py`
  verifies all six rolling axle pivots, that each three-axle set swivels
  as one bogie, and that the two fan rotors evaluate independently.
- `tests/floss_47_art_native.sh` mounts the shipped assets in Linux Luanti.
  It examines street, front, rear, broadside, survey, curve, and close
  overhead views on the real straight and radius-one stock track meshes.
