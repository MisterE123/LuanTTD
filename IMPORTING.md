# OpenTTD save compatibility goal

The long-term interoperability test is **OpenTTD → Luanti → OpenTTD**:
open a supported save in Luanti, play it, then export a new save that opens
in OpenTTD. A supported game should resume at the same paused tick with
the same transport network and company state. Separately, export a world
created and played in Luanti so passing does not depend on retaining the
original save bytes. A heightmap-only preview is not an import.

Interchange is a feature-completion test, not the whole project. Native 3D
controls, a world built for 3D and a polished, enjoyable game need their
own playtests. Do not block a polished earlier release on save interchange
or claim that a successful round trip proves game feel.

## Order of implementation

1. **Preflight (available for development).** Run
   `python3 tools/openttd_save_inspect.py path/to/game.sav`. This reads
   versions 333 and 334, validates map dimensions and map plane lengths,
   reports corner heights, terrain fingerprint and tile counts, and indexes chunks. It is read-only
   and cannot open a playable Luanti world. Use OpenTTD 14.1's
   `openttd -q path/to/game.sav` for native revision/NewGRF diagnostics.
   The inspector does not interpret NewGRF metadata. A successful `-q`
   process exit is not a validity check: even a missing save can print
   a failure and exit zero, and metadata inspection does not resolve the
   world’s object references.
2. **First import target.** One vanilla 14.1 temperate save with a running
   bus. Decode under the pinned GPL upstream schema or export a canonical
   snapshot via a small patch to the pinned native loader; do not guess
   serialized IDs or rewrite the original file. Map source coordinates and
   IDs, and consume the same shared-corner grid, road bits and model state as
   normal LuanTTD gameplay. Map towns, industries, stations/depots, stock,
   company/cash/loans, engine, current order, location, cargo and transit age.
3. **Parity proof.** Use a deliberately saved in-flight service. At tick zero
   compare the terrain and state to official OpenTTD. Resume both and check
   destination, passengers delivered and fare, then save/reload in Luanti
   and repeat. Write a second supported OpenTTD-format save from the live
   Luanti state, including a newly built connection or edited order and a
   later tick. Open it in stock OpenTTD and verify those changes persist,
   then continue the service. Repeat with a world created in Luanti.
   For the first running-bus fixture, start with passengers old enough
   for fare decay to make a difference. Keep a stock OpenTTD load-and-resave
   control. Edit the next order in Luanti to visit a distinct third stop,
   without changing the currently due stop. Prove the reopened export pays
   exactly once for the original passengers and later visits the new stop;
   compare revenue to the control at matching economy time. Include the
   first pool entries (null reference is 0, index 0 is encoded as 1) and
   reject dangling references. Compare normalized state, not file bytes.
   Test a 256×256 map and avoid the current demo's fixed dimensions; chunk
   or stream terrain so bigger saves stay usable.
4. **Broader support.** Test freight, rail/signals/consists and other modes,
   add upstream version migrations deliberately, and treat NewGRFs, scripts,
   forks and unsupported vehicles as explicit compatibility issues.
   A playable importer must refuse unsupported behavior with a report,
   not erase it. If offering map-only conversion, require a distinct choice.

Always make a new Luanti world, never modify the source save. Validate
references and dependency versions before committing the converted world.
Keep the save paused until validation succeeds. The original OpenTTD
version remains the reference for ports and test fixtures.

## First evidence

Inspected two real local files: a new 256×256 world created by the official
14.1 executable (save version 334; corner heights 0–7) and its bundled
title save (version 333; 256×256; heights 0–18) without modifying either.
The synthetic tests cover the supported compression formats and malformed
inputs; example saves and OpenTTD graphics are not distributed here.

Sources: [OpenTTD 14.1 save/load code](https://github.com/OpenTTD/OpenTTD/tree/14.1/src/saveload)
and [official command-line documentation](https://wiki.openttd.org/en/Manual/Command%20line).

## Terrain and road snapshot (developer-only)

`python3 tools/openttd_save_map.py input.sav new-output.json` decodes the
terrain corner lattice and a supported subset of road, bus stop and depot
tile metadata from stock 14.1 saves. It refuses existing output paths and
never modifies the input. Use a separate output file, not a world folder.
The Lua consumer builds a validated shared-corner lattice; it does not
mount the result in a running campaign. Towns, depots as service objects,
orders, vehicles, company accounts, game clocks and export are not supported.
The fixture in `tests/openttd_save_map.py` creates a real stock save, compares
its source terrain and road data with OpenTTD's API, and can exercise the
snapshot reader in Luanti. It is not a playable importer.

The companion `python3 tools/openttd_save_bus_state.py input.sav` emits a
read-only normalized bus-state report for the validated narrow stock schema:
pool IDs including zero, depots, stops, a running bus's current and listed
orders, onboard cargo and age, the saved game clock and company balances.
The differential fixture now pauses a real bus mid-leg with nonzero-aged
cargo, then checks the report against stock observations and tests that
invalid references and order cycles are rejected. LuanTTD does not yet use
this state to start, resume, or export a game.
