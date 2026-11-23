# Bakewell Cargo Ship #212

An original mid-1970s coastal freighter in a dark blue boot and gray-blue hull, with two independently hinged steel weather hatches, open deck passagework, two orange knuckle-boom freight cranes, tiered aft bridge and low radar. The cranes have a physical rotating bed, two boom stages, visible hydraulic actuation and raised load blocks arranged separately over each hold. This is a newer dry-cargo ship, not a repaint of the older Yate and not an oil tanker. It has its own fully formed breakwater, low foredeck, rounded covered aft skiffs, guarded service ladders, bridge lookout windows, twin red diesel uptakes, true propeller and stern rudder. Hinges, vanes, crane gear and rudder are editable source geometry in their rest configuration, not animated in the exported mesh. No stock sprite pixels are included.

The actual native mesh spans **.70800 × .97400 × 1.83491** nodes (beam × full height × length). At unit scale the genuine static waterline is **Y = 0**, native neutral bow is **−Z**, high light **Y = .786**, deepest draft **Y = −.188**. Blender length is on Y with −Y forward and +Z up. No additional dock centering offset. Crane centers are native (0, waterline-relative deck base, −.589) and (0, waterline-relative deck base, +.199). The house sits above and aft of +.34 Z. The 320×8 RGB palette strip assigns uniform, padded color swatches to geometry rather than baking sprite imagery.

## Pinned upstream identities and source treatment

- [OpenTTD 16.0-RC1 engine data](https://github.com/OpenTTD/OpenTTD/blob/16.0-RC1/src/table/engines.h): global #212, local ship row 8, ship image 0, base design day 19,724 after 1920-01-01 (1974-01-01; not a universal player offer date), decay 5, vehicle life 30, base market life 98, Goods, temperate/arctic/tropical. The exact SVI has cost factor 144, acceleration 1, max speed field 80, capacity 190, running cost factor 113, cargo ship departure horn and a refittable flag. Artistic work here does not specify what refits the runtime can purchase or earn from.
- [OpenTTD 16.0-RC1 directional ship art selection](https://github.com/OpenTTD/OpenTTD/blob/16.0-RC1/src/ship_cmd.cpp) has image 0 select 3677 plus heading, with no cargo condition. A single closed exterior serves the empty, laden and refitted (where supported) ship.
- [OpenGFX 7.1 ship art mapping](https://github.com/OpenTTD/OpenGFX/blob/7.1/sprites/base/base-3668-ships.pnml) and [corresponding directional sheet](https://github.com/OpenTTD/OpenGFX/blob/7.1/sprites/png/ships/ships01.png): sprites 3677–3684 are the shared Yate/Bakewell source view. The eight outline cues are a long dark blue steel sheer, two dark hatches, orange freight equipment, white bridge aft and red exhaust. The hydraulic gear, house tiering, livery colors, panel layout and details are deliberately independent. The privately inspected reference PNG checksum is b44b41a37a174bfe6bbe247cd72ee1868bb470736e9dc96b2e29ff05688b8932; its pixels are not packaged.

## Reproduction

- Editable Blender: art/stock_bakewell_cargo_ship.blend, five independently organized semantic collections.
- Runtime: mods/luanttd_core/models/bl_stock_bakewell_cargo_ship.obj; mods/luanttd_core/textures/bl_stock_bakewell_cargo_ship_atlas.png.
- Rebuild and test:

      blender -b -t 2 --python-exit-code 1 --python tools/build_stock_bakewell_cargo_ship_art.py
      python3 tests/stock_bakewell_cargo_art.py

Use LUANTTD_HELPERS and LUANTTD_BASE if staging independently from the game. Set BAKEWELL_CARGO_REVIEW to an existing directory for the original Workbench bow, deck, broadside and ventral views. The test optionally accepts --engines, --ship-cmd, --opengfx and --sheet to recheck the pinned files.

Geometry QA found 14,748 triangles, two closed separate holds, a watertight pressure hull and 1,474 real depot, lock, and open-gate bore probes across both depot axes, all four lock directions and four water stages. The full turning hull has at least .08082 lateral clearance at the tested native berth; both orientations maintain .03543 longitudinal clearance inside the closed gate pair at chamber center. These are visual-fit checks, not proof of ship operation, orders or cargo simulation.

The native Linux render fixture places the actual OBJ and atlas beside the original short pier, half within a split stock depot, and between the two real closed gates at the exact 3/8 lift datum:

    bash tests/stock_bakewell_cargo_art_native.sh

Five isolated QA views cover full harbour, cabin, waterline, depot and lock. This fixture uses the real Luanti asset loader and color/shadow pipeline; it does not exercise paid simulation or drive the boat.
