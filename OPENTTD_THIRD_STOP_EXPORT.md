# Stock-assisted export: one changed next destination

This opt-in fixture extends the narrow experiment in
`OPENTTD_NEXT_ORDER_EXPORT.md`. It is not general import/export. It does
not change the original tick-2726 test, use anyone's original play save,
or write any stock engine, save or asset into the repo.

## What is proven

A fresh private stock 14.1 temperate map is generated with a bay stop
connected to the existing network, already owned by the bus's company,
and **not in either initial order**. The active trip still carries
five original passengers from the through stop (station 1) to the first
bay (station 0). Stock creates those three facilities through normal
construction commands.

Luanti actually plays the first trip and authors the alternate destination
from the played journal after delivery, not from the untouched input
save. The checkpoint retains both original orders and independently
finds the 12-tile route to the third bay using the existing stock YAPF
port. The tool refuses to substitute either old stop, a fabricated tile
or an unconnected alternate. This is a route and state proof, not a
claim that Luanti's live game drove the return leg.

The stock-assisted writer requires an independently recreated,
**exactly matching** paused handoff, including the outstanding payment
object. Only the not-yet-due v334 `ORDR` destination field changes:
source order 0 now points to station 2 rather than station 1. The
currently unloading station-0 order, its motion and its timetable
remain unchanged by the author, as do the future order's flags, list
links and timetable. Unmodified OpenTTD reopens the edited draft,
writes its normal native save, and opens that separate native save
again at the matching paused tick.

The native test then resumes the new file. It requires the original
five deliveries to remain accounted for once, exactly one transition
from zero to £9 income, and confirmation that the new order became the
active one **and that the bus began loading at the distinct third
station**. Merely changing an ID or seeing a route's destination is
not sufficient.

Observed reference for the private seeded fixture:

| Event | Stock/fixture value |
|---|---|
| Loaded source start | Tick 2549 |
| Exact paused handoff after delivery | Tick 2734 |
| Original arrivals | Five, age 3 |
| Pending original fare | £9 at export, £9 posted once after reopen |
| Activated next order observed by | Tick 2843 |
| Native third-station arrival | Tick 3407, station 2 at TileID 44642 |

The original and resulting hashes differ; the input hash stays
unchanged. The two-stop no-load regression still reopens at exactly
tick 2726 and retained its previously observed output hash. This test
does not establish general save compatibility or export for a new
world created entirely within Luanti.

## Reproduce without distributing private fixture files

Run stock OpenTTD with its 14.1 resources (including OpenGFX):

```sh
python3 tests/openttd_third_stop_fixture.py --openttd /path/to/14.1/openttd \
  --share /path/to/stock-data --output /private/new-three-stop.sav

python3 tests/openttd_bus_checkpoint_resume.py --openttd /path/to/14.1/openttd \
  --share /path/to/stock-data --save /private/new-three-stop.sav \
  > /private/three-stop-trajectory.json

python3 tests/openttd_bus_first_delivery.py --with-existing-third-station \
  --luanti /path/to/luantiserver --save /private/new-three-stop.sav \
  --reference /private/three-stop-trajectory.json \
  --emit-order-intent /private/three-stop-order-intent.json

python3 tools/openttd_export_order_experiment.py --openttd /path/to/14.1/openttd \
  --share /path/to/stock-data --source /private/new-three-stop.sav \
  --receipt /private/three-stop-order-intent.json --output /private/third-output.sav \
  > /private/third-proof.json

python3 tests/openttd_order_experiment.py --source /private/new-three-stop.sav \
  --receipt /private/three-stop-order-intent.json --output /private/third-output.sav \
  --native-proof /private/third-proof.json
```

If a busy test host overshoots the first handoff tick, no output is
published; rerun the exact stock capture rather than widening a gate.
