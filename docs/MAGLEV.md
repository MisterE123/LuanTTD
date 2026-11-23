# First stock Maglev service

The Lev1 Leviathan (#84), Passenger Carriage (#89), and Mail Van (#90)
have the original OpenTTD 16.0-RC1 introduction and powered-gauge rules.
The mixed set holds 47 passengers and 37 bags; the Leviathan has a
400 km/h design limit. Mixed service carries and pays the two cargos
separately. Each wagon retains its identity when the train reverses.

1. In a fresh world, use **Starting year → 2025** to try it without
   waiting for the stock introduction. If the starter cash is not enough,
   borrow through **Company → Finances** (about $30,000 for a short test line),
   or fund the line from an existing service.
2. Choose **Rail Construction → Rail Tools & Operations → Rail Engineering →
   Rail Types → Build maglev**. Return to Rail Construction to lay the
   magnetic trough, build a Maglev depot and two passenger platforms near homes.
3. Open the depot and buy **Lev1 Leviathan · Coach and Mail** or assemble
   the same three vehicles by buying the bodies independently. Give the
   train two station orders. This basic one-train service needs no signals.

As with Monorail, timber bridges leave the roadway unobstructed underneath
and tunnels are real bores in the terrain. A Maglev train can only run on
Maglev guideway. Conventional road crossings for this guideway are not
mounted; use a bridge instead.

## Origin and verification

- Mechanics, stock dates and pricing: OpenTTD 16.0-RC1
  `src/table/engines.h`, `src/table/railtypes.h`, `src/engine.cpp`, and
  existing direct ports of rail and station construction and train
  dispatch. Luanti-specific code chooses and positions the 3D mesh; it
  does not supply an alternate powered compatibility or price.
- Original Blender models in `art/rail_lev1.blend`,
  `art/rail_maglev_passenger.blend`, `art/rail_maglev_mail.blend`, and
  `art/maglev_spans.blend`; Blender generators remain in `tools/`.
  The wheel-less carriers pivot beneath each body and clear the copper
  motor shelf and guide walls. Bridge and tunnel art shares the magnetic
  trough instead of using a conventional wheelway.
- `tests/stock_lev1_art.py` verifies positive shelf, wall and curve
  clearance. `python3 tests/monorail_span_art.py maglev` verifies worked
  seams of both bridge ramps and true roof clearance.
- Run `BAYLINE_MIXED_FORM=maglev-spans bash tests/stock_mixed_town_rail_live_native.sh`
  for a real worker route with a depot-assembled train, actual bridge/bore,
  station loading and two reloads before crediting both fares once.
