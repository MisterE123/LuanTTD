# Stock conventional Iron Ore Hopper and Steel Truck

Two independent original editable Blender vehicles for the stock Temperate OpenTTD 16.0-RC1 railway. The Iron Ore Hopper is a deep dark-blue, thick-walled open vat with eight rolled braces per side, milled metal rim, end ladder, brake levers and real keeper linkage. Its load is an independently closed ore bed with 78 individual closed rust-colored 3D fragments, all below the lip. The Steel Truck is a lower reinforced wooden-plank wagon with permanent timber cradles, tie rings and coil stops. Its loaded form carries three individual hollow transverse 3D steel coils with actual through bores, raised concentric rolling marks and secured wrap bands. No company logos, mapped sprite pixels or third-party geometry are included.

## Exact data and stock art

[OpenTTD 16.0-RC1 engine table](https://github.com/OpenTTD/OpenTTD/blob/16.0-RC1/src/table/engines.h), [sprite lookup](https://github.com/OpenTTD/OpenTTD/blob/16.0-RC1/src/table/train_sprites.h) and [train image selection](https://github.com/OpenTTD/OpenTTD/blob/16.0-RC1/src/train_cmd.cpp). Scope is the conventional Rail versions; monorail and maglev are distinct roster entries.

| Stock conventional engine ID | Empty tare / capacity | Buy factor | Image | Stock empty → loaded directional base | Loaded art threshold |
| --- | --- | ---: | ---: | --- | --- |
| #35 Iron Ore Hopper | 19 t / 30 Iron Ore | 179 | 41 | 2773 → 2797 | ≥15 stored |
| #36 Steel Truck | 18 t / 20 Steel | 196 | 42 | 2769 → 2793 | ≥10 stored |

Both have image-and mask 3, zero direction adder, +24 load adder, no motive power or wagon speed cap, 8 nominal stock length units, base design day 1827 (1925-01-01, not a player-specific date), decay 20, vehicle life 20 years and 50-year base market life. Gameplay loading uses stored count greater than or equal to integer capacity divided by two. The playable integrations use the shared stock industry station, railway and payment simulation.

The [OpenGFX 7.1 four-heading mapping](https://github.com/OpenTTD/OpenGFX/blob/7.1/sprites/base/base-2733-rail-vehicles-wagons.pnml) and [stock visual sheet](https://github.com/OpenTTD/OpenGFX/blob/7.1/sprites/png/trains/temperate_railwagons_28px.png) were consulted for the tall blue ore hopper, recessed red-brown load, low wooden steel deck and three visible steel coils. Those sources and their pixels are not shipped.

## Mounting

- Assets: bl_rail_iron_ore_hopper_{empty,loaded}.obj and bl_rail_steel_truck_{empty,loaded}.obj, with matching bl_rail_*_atlas.png.
- Unit visual scale. Mesh Y=0 is the physical tread datum, located at surface base plus .614 on standard track. Blender local Y is longitudinal; in-game native nose is −Z and native Y is up. Center spacing 1.0 node; axle center lines Z=±.269; track gauge X ±.212. Both drawknuckles are located at Y=.157 with tips at Z=±.499, retaining .002 exact straight tip clearance. No visual offsets, animation or remount are required to swap the cargo.
- Hopper lip peaks at .485; coal-style seams, chutes and gate hardware are built as part-separated shapes. Steel loaded peak .435; permanent empty cradle peak .282. Each loaded OBJ begins with the complete byte-identical empty shell, followed only by load geometry. The RGB atlases are padded 512×8 strips. The three main Blender collections are independently editable.

## Build and verify

    blender -b -t 2 --python-exit-code 1 --python tools/build_stock_rail_metals_art.py
    python3 tests/stock_rail_metals_art.py
    bash tests/stock_rail_metals_art_native.sh

For isolated staging set LUANTTD_HELPERS to game tools and LUANTTD_BASE to checkout. Set METALS_REVIEW to an existing directory for original empty/loaded/side Workbench renders. The source QA optionally takes --engines, --sprites and --opengfx. Native graphics fixture shows both actual coupled vehicles on the stock platform and curve with a fixed-camera cargo-only swap. This is dry art verification, not a financial or routing simulation.

Both new wagon bodies clear all 4,000 reciprocal coupled corner/straight sweeps. An additional 4,000 mixed poses against the Kirby and SH '125' found no body or running-gear collisions or altered coupler reach; 208 tight-turn contacts are limited to the old Kirby spring-buffer pad grazing the new wagon knuckle. Those cosmetic contacts are explicitly counted rather than hidden by shortening the knuckle. Actual asset checks also covered 640 straight/curved gauge overlaps, 256 eased-diagonal tread probes, 13,242 portal vertices, and positive depot roof and station coping margin. Linux Luanti rendered both assets with their independently toggled cargo while coupled at a platform; the screenshot set also includes the same pair on existing turn artwork.
