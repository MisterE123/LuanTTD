# Stock-assisted interchange: running bus and depot reserve

This opt-in developer fixture is one supported two-road-vehicle roster,
not general save import/export. A fresh private 256×256 OpenTTD 14.1
world contains a loaded in-service MPS Regal and a second empty,
manually stopped MPS Regal in the same company's road depot. They have
separate vehicle, order-list and order IDs. The reserve already has a
one-stop order to the original return stop, making it a useful
independent service asset rather than a second ignored pool row.

## Proof

- The loaded bus follows the same played Luanti first-trip checkpoint.
  The reserve must be in an actual mapped depot, empty, stopped and
  carrying a compatible independent order. The opt-in roster gate
  rejects hidden additional vehicles and does not widen the older
  one-bus gates.
- The journal and export receipt bind the real stock reserve records.
  The helper retains every decoded reserve vehicle/order-list/order
  field, including text bytes and wide integers, and gates exact
  stock position/order semantics. The native exact paused draft at
  tick **2742**, its authored copy, native save, and reopened native
  file all have identical full reserve records and fingerprint. The
  source hash remains unchanged.
- The primary is the only edited vehicle. Its not-yet-due order goes
  from station 1 to station 2; the first five arrivals and pending £9
  object survive intact. After reopen, stock books £9 once and the
  primary unloads/loads at the actual new bay, source tile 44642.
  The reserve stays parked throughout this proof, with unchanged
  ownership, physical position, current-order state and independent
  order. Its stock tick, age and order-time counters are checked at
  their exact expected values at each sampled tick.
- A **separate disposable reopen** of the same final file then
  dispatches only the verified reserve using the stock AI command.
  The reserve actually exits the depot, moves empty on its stored
  order, and begins loading at its original station 1 (source tile
  44387). That extra control does not edit or overwrite the exported
  file. It is not proof of Luanti simulating two interacting
  traffic-heavy vehicles.

Native observed run: primary visited station 2 at tick 3415;
reserve control departed at the observed tick 2815 and reached its
own station at tick 2952. Sampling/OS timings can shift observations,
but the exact initial native handoff is not relaxed. Negative tests
reject alternate owners, shared or replaced order lists, forged
reserve records/positions and parked-clock changes among 26 invalid
handoff variants.

## Reproduce

Use a new private scratch directory as TMPDIR. Keep all generated
fixture inputs, interim profiles and save outputs private. See
OPENTTD_THIRD_STOP_EXPORT.md for the corresponding one-bus variant.

```sh
python3 tests/openttd_two_bus_fixture.py --openttd /path/to/OpenTTD-14.1 \
  --share /path/to/stock-data --output /private/two-bus-source.sav

python3 tests/openttd_bus_checkpoint_resume.py --with-depot-reserve \
  --openttd /path/to/OpenTTD-14.1 --share /path/to/stock-data \
  --save /private/two-bus-source.sav > /private/two-bus-reference.json

python3 tests/openttd_bus_first_delivery.py --with-existing-third-station \
  --with-depot-reserve --luanti /path/to/luantiserver \
  --save /private/two-bus-source.sav --reference /private/two-bus-reference.json \
  --emit-order-intent /private/two-bus-played.json

python3 tools/openttd_export_order_experiment.py --openttd /path/to/OpenTTD-14.1 \
  --share /path/to/stock-data --source /private/two-bus-source.sav \
  --receipt /private/two-bus-played.json --output /private/two-bus-export.sav \
  > /private/two-bus-proof.json

python3 tests/openttd_order_experiment.py --source /private/two-bus-source.sav \
  --receipt /private/two-bus-played.json --output /private/two-bus-export.sav \
  --native-proof /private/two-bus-proof.json
```

Only the primary's future destination is authored. The reserve and
unsupported parts of the rest of the world remain under the stock
loader/writer's authority. No raw saves are committed or distributed.
