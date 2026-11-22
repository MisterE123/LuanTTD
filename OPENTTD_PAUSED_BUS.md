# Paused stock bus acceptance checkpoint

This is the next developer-only OpenTTD save interchange milestone. It
prepares an internally checked, **paused and non-resumable** LuanTTD
checkpoint from a narrow real stock 14.1 game. No campaign scripts are
loaded. No source data is modified and no playable game is exported.

## Accepted case

One manually paused v334 temperate 256×256 save under the supported standard
calendar, non-inflated economy and manual passenger-routing/YAPF settings;
no NewGRFs. It contains one stock MPS Regal passenger bus (engine 116) in
ordinary-road motion, one company, one depot and two one-tile bus stations.
The checkpoint checks the route ahead to the current bay from the exact
saved track direction on level ground. Other transport modes, multi-tile
stations, custom routes, unpaused or loading vehicles, breakdowns,
overtaking, special order flags and unsupported off-vehicle operations
are not accepted as resumable state.

```sh
python3 tools/openttd_save_bus_checkpoint.py /private/stock.sav \
  --output /private/new-checkpoint.json
```

The command reads the existing map and bus packet/table decoders, then
joins the same file's map and state in a new versioned document. The Lua
adapter `mods/bayline/import/openttd_bus_checkpoint.lua` validates this
document against the shared sparse map and existing OpenTTD slope,
road-motion and YAPF kernels. The accepted result has a read-only board
(view does not expose commit) and a `checkpoint()` method returning
detached paused data. It has no resume method. A SHA check ties the two
reports to the same original file when produced by the extractor;
this is structural validation, not a signature on arbitrarily edited JSON.

### Preserved and checked

- Each relevant source pool ID retains its real index, including zero.
  Original padded TileIDs, unpadded zero-based logical IDs and one-based
  coordinates are distinct. Stations are checked against actual map facilities and the
  serialized road stop pool; one depot and cited town anchors are retained.
- The active order index and destination, next links and their distinct
  null encoding, timetable fields and the recorded ordinary road search
  settings survive. The pinned YAPF search recomputes a reachable trace
  from the saved track heading to the already-selected stop; it does not
  infer a route from a line drawn between stops.
- Source X/Z positions remain in stock 16-pixel tile units and Y in
  stock 8-pixel height levels, alongside the matching Luanti position.
  The pinned frame table must corroborate the local pixels. Raw
  track direction/frame/heading, progress, speed/sub-speed, ground flags,
  choice cache and vehicle phase counters are retained.
- Calendar date/tick fraction, economy date/tick fraction, sub-fraction,
  RNG state, tile-loop cursor, pause mode, global tick and saved vehicle
  timers survive. Company cash/loan/fraction and vehicle profit, plus
  every onboard packet's origin, count, transit age, travel-vector state
  and feeder share, remain exact. Unsigned/signed 64-bit values cross
  JSON/Lua as decimal strings, avoiding silently rounded double values.

## Differential acceptance

```sh
python3 tests/openttd_bus_checkpoint_resume.py \
  --openttd /path/to/OpenTTD-14.1/openttd --share /path/to/stock-data \
  --save /private/stock.sav > /private/stock-reference.json

python3 tests/openttd_bus_checkpoint.py \
  --luanti /path/to/luantiserver --save /private/stock.sav \
  --reference-json /private/stock-reference.json
```

Use the test oracle in `tests/openttd_save_map.py` to create the private
loaded stock fixture (save with `--retain-fixture`). It is not distributed.
The stock reference harness runs the unmodified 14.1 engine, gives the AI
no further build or dispatch commands, verifies the paused load/resave
control, and observes the same bus completing its trip. The input SHA is
checked after both runs. Luanti verifies clocks, finances, cursor, stop
links and the path, rejecting deliberately inconsistent checkpoints. Its
pure fare kernel can also be compared with the **actual later stock fare**;
that comparison does not unpause Luanti.

For the current real fixture, saved tick 2541 begins with five passengers
(age 2), on source TileID 44389 towards bay TileID 44392. Native stock
delivery ages them to 3, counts five arrivals, and posts a £9 fare later
when the load/unload payment object settles; the next sample stays at one
settlement. Delivery and booked cash must not be conflated. This leg is
too short to make the integer fare change at every transit age. A longer
control is still needed to specifically catch an erroneous age reset via
money alone.

A playable next step must restore the motion/aging clocks and order state
into the existing runtime, then import station acceptance, waiting and
rating counters, the pending cargo-payment lifecycle, and exact company/
economy scheduling. Town/industry state, other vehicles/operations, save
migration and writing a new stock `.sav` remain outside this checkpoint.
