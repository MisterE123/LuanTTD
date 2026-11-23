# Stock SH '125' and Mail Van

Two original Blender models for conventional railway stock, with actual wheels, bogie hardware, protected drawbars, separate vehicle shells, glazing and interior vestibule details. The SH '125' uses a low rounded high-speed driving nose, Continental-blue skirt, pale metallic waistline, yellow warning cab, dark ventilation banks, and independent roof grilles. The oxblood Mail Van is a sealed steel postal van with two double loading doors, actual external hinge pins and load handles, four guarded quarter lights, paired dark gangways, and original raised lettering. The liveries, details and models are original; no graphics from OpenTTD, OpenGFX, or real operators are distributed.

| Runtime vehicle | Asset stem | Pose and shape |
| --- | --- | --- |
| SH '125' #22 | bl_rail_sh_125 | One powered, asymmetric model. Yellow outward cab points −Z; the flat inboard vestibule is +Z. Place each powered end at its own stock pose; turn the rear unit 180° on straight track. Axle positions Z = −.271, −.177, .175, .269. Width .522 and maximum Y .556. |
| Mail Van #28 | bl_rail_mail_van | One separate closed conventional wagon; no load-state shape switch. Axle positions Z = −.286, −.191, .191, .286. Width .522 and maximum Y .551. |

Both at unit mesh scale with track centers X = ±.212 and tread contact **Y = 0**, mesh origin .614 above native terrain tile base; unpowered flange extends to Y = −.009 inside the railheads. Center spacing **1.0 Luanti node**, coupler tips located at local (0, .157, ±.499), giving .002 straight tip clearance. These are real 3D track/vehicle dimensions, not lengths inferred from the 2D graphic. Blender local X is lateral, Y is the longitudinal axis with −Y toward the cab and Z is up. The native materials use separate, padded palette strips.

## Upstream source and visual provenance

- [OpenTTD 16.0-RC1 engine data](https://github.com/OpenTTD/OpenTTD/blob/16.0-RC1/src/table/engines.h). #22 has engine image 6 and Multihead type, diesel, conventional rail, mail, 200 stock speed units, cost factor 20, 4,500 hp, 70 tonnes, running cost factor 190 and **4 bags of Mail per head**. Temperate only. Base design day 20,820 after 1920-01-01, 20-year vehicle life and 25-year base market life. #28 has wagon image 35, conventional rail, cost factor 228, 21 t empty, no own power, running cost or speed limit, 30 bags of Mail, all four climates. Base design day 1,827 after 1920-01-01 (the base day, not a promise about release availability), vehicle life 20 and market lifetime 50. Do not confuse it with the monorail/maglev stock Mail Vans #58/#90.
- [OpenTTD 16.0-RC1 stock sprite tables](https://github.com/OpenTTD/OpenTTD/blob/16.0-RC1/src/table/train_sprites.h) and [train logic](https://github.com/OpenTTD/OpenTTD/blob/16.0-RC1/src/train_cmd.cpp): front image 6 and rear image 7 share base 2941, mask 7, and offsets 0 and 4. Mail image 35 uses base 2741, mask 3, and offset 0. All use wagon-full adder 0, so neither image set needs a variant after loading. The stock shortening fallback is 0, giving the full nominal eight train length units per body.
- [OpenTTD SH '125' manual](https://wiki.openttd.org/en/Manual/Base%20Set/Trains/SH%20%27125%27) identifies the real analogue as the British InterCity 125. The original model is a stylized interpretation of that outline and the corresponding [OpenGFX 7.1 engine sprite reference](https://github.com/OpenTTD/OpenGFX/blob/7.1/sprites/png/trains/temperate_engines_28px.png), used only as private shape reference, SHA-256 0fa6d9ba1f93ae2bdd864ad65a25e8ad980bb97f02112beb8b4fed4831a36260. The [OpenGFX 7.1 conventional wagon sheet](https://github.com/OpenTTD/OpenGFX/blob/7.1/sprites/png/trains/temperate_railwagons_28px.png), SHA-256 494b6362d976943cc42dace9995e5904b04814849fa5ca3872ea45ac4b835487, provides the closed, small-window wagon art direction. Neither reference is included.

## Rebuild and QA

    blender -b -t 2 --python-exit-code 1 --python tools/build_stock_rail_f_art.py
    python3 tests/stock_rail_f_art.py

Set LUANTTD_HELPERS and LUANTTD_BASE to the game tools directory and game checkout respectively when building/testing an isolated staging tree. Optionally pass RAIL_F_REVIEW to save original three-angle Blender Workbench renders per model. Each editable .blend has independent shell, doors/roof gear, end assemblies, underframe and four wheel pivots with one review camera/apron collection. The geometric QA can verify the pinned header blobs via --engines and --sprites.

Both tested stock geometries achieved 4,000 total mixed/reciprocal adjacent-body sweeps, 1,392 tread overlaps against the real straight and curved rails, 512 eased-diagonal tread overlaps, 10,452 portal package samples and positive clearance against the existing native depot and platform fixtures. Mesh closure, physical postal door hinge details, both extant mount envelopes and single-mesh stock directions are separately asserted. These are art-only tests; they do not claim that the Mail Van is purchasable or earns mail revenue until railway Mail service is mounted in the game.

The Linux Luanti visual fixture also loaded both actual release-style meshes and atlases together, with reciprocal SH '125' heads and the Mail Van between them on straight/platform track, plus both body types coupled on the turnout. It produced four reviewed screenshots without mesh/texture load errors:

    bash tests/stock_rail_f_art_native.sh

The fixture uses a private temporary world. It proves native loading, orientation and geometry presence, not company operations.
