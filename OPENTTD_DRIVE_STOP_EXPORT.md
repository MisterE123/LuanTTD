# Build and reopen one stock drive-through bus stop

This private save-interchange lab constructs a genuine OpenTTD 14.1 bus facility on one company-owned road tile that no vehicle is occupying. It neither patches compressed data nor uses LuanTTD's campaign stop pricing. The quote runs natively in Luanti using the existing stock map adapter, terrain geometry, and directed road connectivity, plus the pinned stock stop-construction rule for this one site. The test does not add a live game build option and is not a general `.sav` exporter.

The untouched [road-construction fixture source](OPENTTD_ROAD_CONSTRUCTION_EXPORT.md) has a running bus carrying five passengers and a separately ordered bus parked in a depot. The new stop goes on **tile 44385** (front direction toward **44386**) on flat company-0 road. The street's east/west mask **10** and both permitted directions remain exactly the same. The stock command allocates its own **station 3 and road-stop object 3**, independent of all pre-existing facilities. It adds neither pavement nor a foundation. The lab quotes **£150**, the native low-difficulty price of the base [stock bus-stop fee](https://github.com/OpenTTD/OpenTTD/blob/14.1/src/table/pricebase.h#L23); normal-difficulty base is £200.

`AITestMode` gives the same £150 without changing the tile. An actual qualifying `AIRoad.BuildDriveThroughRoadStation` uses [the stock construction path](https://github.com/OpenTTD/OpenTTD/blob/14.1/src/station_cmd.cpp#L1930-L2077), spends exactly £150, and writes a new save. At the same paused tick as an untouched control, only the selected map tile's station fields changed; no heights or adjacent tiles changed. Existing vehicles, orders, depots, packets and cargo payments are compared byte for byte. Existing station and stop records must also match, and station creation is allowed exactly the [single pinned RNG transition](https://github.com/OpenTTD/OpenTTD/blob/14.1/src/station.cpp#L224-L234) it requires, not arbitrary changes to the clock. Nine reject cases cover owner, wrong approach/axis, larger scope, occupied or obstructed site, merging, junction, one-way road and insufficient funds.

The independently reopened stock file continues the first bus's original trip: it delivers five passengers, stages their £9 fare, and books it once. The reserve stays parked with its own unchanged order. A **different disposable reopen** temporarily orders the reserve to the new facility and dispatches only it; the vehicle physically crosses the new tile and records a visit to station 3. That additional exercise never modifies the exported file or the original source.

## Reproduce

Use a unique private `TMPDIR`. Generate the *original* `source.sav` with the [road lab's fixture generator](OPENTTD_ROAD_CONSTRUCTION_EXPORT.md), not its constructed-road output. Use actual 14.1 stock and Luanti server binaries, with stock OpenGFX/data available. The lab creates an exclusive output only after both reopens are verified.

```sh
python3 tests/openttd_drive_stop_export.py \
  --openttd "$OPENTTD" --share "$STOCK_DATA" --luanti "$LUANTISERVER" \
  --source "$TMPDIR/source.sav" --output "$TMPDIR/drive-stop.sav" > "$TMPDIR/drive-stop-proof.json"
```

Keep both saves private. The proof JSON is sufficient for reviewing outcomes and digests. Custom NewGRFs, truck or multi-tile stops, loose/foreign/signed/branched approaches, stations requiring foundation or joining work, and arbitrary world edits are outside scope.
