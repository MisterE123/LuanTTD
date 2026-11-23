# Stock AsiaStar electric power head (#26)

Original two-direction stock express design. Each physical head has its own swept teal visor, brushed lamp housings, sculpted yellow pilot, pale shell, vent slats, and independently editable wheelsets. Uses the conventional full-length gauge and configurable pantograph clearance of LuanTTD. The complete model and split body match the shared collector geometry and atlas exactly. No original sprite is shipped.

OpenTTD 16.0-RC1 `src/table/engines.h` specifies calendar day 26298, vehicle life 25, model availability 50, twin conventional electric heads, 264 km/h, 8,000 hp combined, 95 t per head, purchase factor 43, electric running factor 250, and no seats in either head. The physical heads face out around a separately bought 40-seat Passenger Carriage in a paid train.

Rebuild from the repository root: `blender -b -t 3 --python-exit-code 1 --python tools/build_stock_asiastar_art.py`. To inspect the renders set `ASIASTAR_REVIEW` to a directory. Compare wheel contacts, 800 twin poses, 3,864 portal ray checks, exact source data and the split collector with `python3 tests/stock_tim_art.py --variant asiastar --upstream-engines /path/to/OpenTTD-16.0-RC1/src/table/engines.h`.

In ordinary play, the model appears by its stock date in a powered conventional rail depot. The paired powerheads cost $67,187 at the base medium settings; the one-coach set costs $69,116. Both heads are powered and neither carries passengers. The Linux worker and the native dedicated game tested purchase, refusal at an unwired gap, a raised bridge with both moving pantographs, reversal, restoration by SQLite, and paid passenger delivery. Run the same worker probe with `LUANTTD_NATIVE_ASIASTAR=true bash tests/stock_tim_worker_native.sh`.
