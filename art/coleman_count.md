# Coleman Count

OpenTTD 14.1 standard temperate Coleman Count, global engine **#216**,
aircraft row **#1**, sprite **0**, subtype **P** (small propeller airliner),
introduced in 1947. Stock default capacity is **65 passengers and 8 bags
of mail**. In a January 1950 game with OpenGFX it appears between the
Sampson U52 and Bakewell Cotswald LB-3. Bakewell Luckett LB-8 (#220) is
not an equivalent small 1950 plane: its source date is 13,695 days after
1920 (~1957), and the subtype is J, a large jet. See
[OpenTTD 14.1 engine tables](https://github.com/OpenTTD/OpenTTD/blob/14.1/src/table/engines.h).

Original 3D mesh art follows the basic white crown, blue company
cheatline and tail, bright silver wing set and dark prow of the observed
OpenGFX 7.1 aircraft without bundling any upstream pixels or cutouts.
Viscount-style four turboprop pods, individually pitched blade meshes,
flap and elevator foil, airfoils with dihedral, oval recessed side
glazing, windscreens conformed to the underlying pressure shell, and
tricycle gear were authored independently. Livery is fixed for these
models. Propellers are static display blades, not animated.

## Authoring and mount

- Editable part-separated `coleman_count.blend` includes common airframe,
  extended gear, and retracted gear in separate named collections.
  Toggle the two gear collections to inspect each version.
- `bl_coleman_count.obj` has real undercarriage and all six tire contacts.
  `bl_coleman_count_flight.obj` swaps only the undercarriage for physically
  closed bay door geometry. Both use `bl_coleman_count_atlas.png`.
- Native nose is local **−Z**, up is +Y, one Luanti node is 10 OBJ units,
  and the model uses uniform entity scale **1**. The origin is the tire
  contact ground plane for both models. The flight model keeps that same
  origin so exchanging gear state does not move the airframe.
- Span 1.914 native nodes; length 1.663; fin top .681 above the tire datum.
  The lowest gear-up vertex is .123 above that datum (inner prop blade).
  No visual origin remapping or added positional offset is needed.
- Native 4×3 Country Airport geometry clears both real source stands,
  the taxi paths, take-off/arrival, and hangar park/back-out points.
  Geometry QA uses the stock travel trace with Coleman acceleration and
  checks the swept conservative full hull at both stands and the hangar.
- Does not change the active fleet, schedule, camera, stock motion,
  loading or airport UI. Gear timing/asset selection are runtime choices.

## Regenerate and verify

```bash
blender -b -t 3 --python-exit-code 1 --python tools/build_coleman_count_art.py
LUA=/path/to/lua python3 tests/coleman_count_art.py /path/to/OpenTTD-14.1
BAYLINE_NATIVE_TOOLS=/path/to/native/tools tests/coleman_count_art_native.sh
```

Set `COLEMAN_REVIEW=/path/coleman.png` on the Blender command to produce
an original posed apron render. The OpenTTD source argument is optional for
the standalone geometry test; the initial stock trace uses the repository's
existing source-port Lua modules. The native fixture independently renders
both plane gear forms using the actual game OBJ and atlas, with ground
contact at a real stand, a survey next to Sampson, and the real hangar slot.
