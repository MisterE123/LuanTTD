# Stock MPS, Uhl and Chippy Iron Ore Trucks

Original visual fleet for the three temperate OpenTTD 16.0-RC1 iron ore tippers, from a pre-war conventional bonnet through a square cabover to a late streamlined tandem. Each is a one-lane original native Luanti model, with an independent working-shaped hydraulic hoist, load-bearing pins, suspension, headlamps, rolling frame, a realistic closed-thickness open hopper and separately modeled ore.

| Asset | Appearance | Native W/H/L | Original individual rust ore stones | Axles, Z at model coordinate (multiply by .42 for game) |
| --- | --- | --- | ---: | --- |
| #147 MPS | Slate blue and stone roof; long separate rounded bonnet, upright narrow nickel grille, round lamps, six broad hot-rolled rib brackets | .25788/.26838/.68161 | 78 | −.536, +.425 |
| #148 Uhl | Coastal blue square cab, broad grille, cream belt, arched roof corner and eight cold-formed side ribs | .25788/.26964/.68077 | 98 | −.528, +.437 |
| #149 Chippy | Blue-violet aero cab, steep curved glazing, broad low intake, modern rear tandem axles, ten sweep ribs and longitudinal reinforcement rails | .25788/.28182/.69001 | 120 | −.533, +.329, +.584 |

All meshes use actual tire contact at **Y = 0**, neutral nose **−Z**, and established dry freight visual scale **.42**. Example Chippy runtime mesh resource is bl_stock_chippy_iron_ore_truck.obj; loaded exterior appends _loaded and the palette texture appends _atlas.png. Replace chippy with mps and uhl to select the earlier models. Source Blender uses −Y nose and +Z up; the ore collection can be toggled independently of the three vehicle collections. Every loaded OBJ contains the exact empty shell as a byte-identical prefix. Typical turn poses were checked rather than relying only on the static widths. The palette is opaque 1024×16 with flat, padded materials. No real maker badges, sprite pixels, or proprietary text/branding are shipped. Hoists and latches are editable Blender parts in their stationary stow poses, not animations.

## Exact pinned source and load transition

[OpenTTD 16.0-RC1 engine table](https://github.com/OpenTTD/OpenTTD/blob/16.0-RC1/src/table/engines.h) and [road vehicle directional sprite selection](https://github.com/OpenTTD/OpenTTD/blob/16.0-RC1/src/roadveh_cmd.cpp).

| Engine | Base design date | Local row and image | Capacity | Speed field | Buy / running factors | Weight / power raw fields | Directional empty → loaded base; loaded threshold |
| --- | --- | --- | ---: | ---: | --- | --- | --- |
| #147 MPS Iron Ore Truck | 1935-01-01 (5,479 days) | row31/image8 | 22 | 96 | 121 / 90 | 38 / 12 | 3364 → 3412; **11/22** |
| #148 Uhl Iron Ore Truck | 1977-01-01 (20,820 days) | row32/image25 | 25 | 176 | 140 / 168 | 48 / 22 | 3172 → 3220; **12/25** |
| #149 Chippy Iron Ore Truck | 2011-01-01 (33,238 days) | row33/image42 | 27 | 224 | 150 / 240 | 69 / 45 | 3556 → 3604; **13/27** |

All three stock engines are climate Temperate, 15-year vehicle life, decay 20, with base market life 55/55/85 years and the stock early-departure road sound. Table dates are the design days, not a guarantee of a particular game seed’s release date. The stock drawing switches to the loaded art when StoredCount is greater than or equal to the integer floor of capacity divided by 2, exactly matching the +48 adder even with odd capacities. Do not use load-positive, rounded half or full-only as a substitute.

The [OpenGFX road art slot mapping](https://github.com/OpenTTD/OpenGFX/blob/master/sprites/base/base-3092-road-vehicles.pnml), pinned blob ff7de7f3ea587fc554fc9331399bc35333607364, and its [sprite sheet](https://github.com/OpenTTD/OpenGFX/blob/master/sprites/png/roadvehicles/vehiclesroad01.png), pinned blob 115510b811f8b475abac68df299c17369dfd1706, were consulted privately. These motivate the common blue body, ribbed tipper structure and dark red-brown open cargo; modified wheel spacing, iron fragments, cabin shapes, body folds and period fittings are independently designed. Neither reference is packaged.

## Reproduce

    blender -b -t 2 --python-exit-code 1 --python tools/build_stock_iron_ore_road_art.py
    python3 tests/stock_iron_ore_road_art.py --road

Use LUANTTD_HELPERS for the game’s tools directory, LUANTTD_BASE for its checkout, optional IRON_ORE_ONLY with maker names to build a subset, and IRON_ORE_REVIEW to save authored loaded bow/rear and empty rear inspections. The source verification can be enabled with --engines and --road-source. All six variants passed 12,784 real stock surface-tire poses each with zero misses, plus 17,424 stock level-crossing/construction fixture checks. Tests also check watertight independent cargo, shape-specific geometry, tread contact, positive opposing-lane clearance, and identical hull between empty and laden. No simulation or field tender claims are made by art QA.

The native Linux render fixture also showed the actual MPS and Uhl on opposing lanes and the Chippy on the imported stock turn at the same position with empty and filled hoppers. The only changed pixels at the Chippy switch were confined to the ore region. Run with:

    bash tests/stock_iron_ore_road_art_native.sh

The four screenshots use native Luanti OBJ/atlas loading and existing road textures. The fixture is an art render, not a server gameplay replay of an iron ore delivery.
