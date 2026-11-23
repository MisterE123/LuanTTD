# FFP Dart and Yate Aerospace YAC 1-11

Two independent period-native 3D interpretations of the rear-engined twinjets. The FFP Dart uses a drawn-out ogive, wide swept aluminum wings and lower stabilizer in brick-red and old gold. The YAC 1-11 has a fuller radome, tight swept wings, high T-tail, under-tail folding stair housing, and mid-century jade/gold livery. Both have hull-conforming individual glazed windows, inlaid doors, physical pitched intake vanes, annular exhausts, mounted tricycle gear, and original fin striping. The shared Blender helpers are geometric construction and file-format helpers; these are new bodies, wings, gear positions and lips rather than reskins of the Darwin.

| Native unit-scale envelope (span × height × length) | Nose twin wheel center | Main twin wheel centers | Twin engine inlet centers |
| --- | --- | --- | --- |
| FFP Dart – 1.56800 × .53954 × 1.70200 | (0, .037, −.554) | (±.182, .053, .130) | (±.172, .237, .438) |
| YAC 1-11 – 1.53400 × .59954 × 1.74000 | (0, .039, −.543) | (±.202, .052, .162) | (±.184, .259, .475) |

Tuples are native (X, Y, Z); nose −Z, literal Y=0 tire tread. Blender source is +Y forward and +Z up. No wheel animation, gear retraction, proprietary fonts or logos are included. Each .blend retains four separate, named editable art collections; the apron and front/rear/ventral review cameras are excluded from the game-facing OBJ. The material atlas is opaque 256×8 using padded color swatches; the original decals are mesh details.

## Pinned source

- [OpenTTD 16.0-RC1 engine table](https://github.com/OpenTTD/OpenTTD/blob/16.0-RC1/src/table/engines.h). #217 FFP Dart has local aircraft row 2, base design day 12,659 (1954-08-29), decay 20, vehicle life 18, market base life 20, price factors 16/130, acceleration 35, maximum speed field 74, 10 mail, 90 passengers. #225 Yate Aerospace YAC 1-11 has local row 10, base design day 15,371 (1962-01-31), decay 20, vehicle life 22, market base life 25, price factors 16/135, acceleration 35, speed field 74, 10 mail, 95 passengers. Both temperate/arctic/tropical and J = AIR_CTOL | AIR_FAST. These are stock design dates, not individual game offer dates.
- [OpenTTD 16.0-RC1 aircraft rendering](https://github.com/OpenTTD/OpenTTD/blob/16.0-RC1/src/aircraft_cmd.cpp). Both stock airliners are image group 2, which is base sprite 3781 plus heading. There is no alternate stock image for gear, payload, phase of flight or height; each model therefore has one exterior. No Country/short-strip safety claim is made.
- [OpenGFX 7.1 rear-jet directional sheet](https://github.com/OpenTTD/OpenGFX/blob/7.1/sprites/png/aircraft/FFPDart.png), ref SHA-256 abab8168bacebd2d78802815badf23ea6598b4b6e31cc15be085a5f7ad639b8b: the sheet itself identifies both names and shows the shared swept rear-jet silhouette. It was inspected for the broad silhouette only. It is not included or sampled into any mesh or atlas. The different tail heights and liveries are authored choices, not assertions about two distinct OpenGFX silhouettes.
- Airport layout and movement checks use [16.0-RC1 airport defaults](https://github.com/OpenTTD/OpenTTD/blob/16.0-RC1/src/table/airport_defaults.h) and [16.0-RC1 FTA movement](https://github.com/OpenTTD/OpenTTD/blob/16.0-RC1/src/table/airport_movement.h).

## Reproduce

    blender -b -t 2 --python-exit-code 1 --python tools/build_stock_airliners_e_art.py
    python3 tests/stock_airliners_e_art.py --city

For an isolated checkout, set LUANTTD_HELPERS to the game's tools directory and LUANTTD_BASE to the game checkout. Set AIR_E_REVIEW to an absolute directory for six original workbench JPEGs. The test can also audit upstream blobs with --engines, --aircraft, --city-layout, and --city-movement.

At actual game scale both cleared 3,973 sampled/eased structural ground poses each, through all three stands and depot moves against all 36 rendered City tiles. 1,876 runway wheel samples per model sit on the actual wearing course, minimum lateral clearances .37962 and .36220 nodes. These are static structure and gear tests, not a proof for every simultaneous aircraft arrangement, flight behavior or company dispatch.
