# Verified stock Raise on one shared terrain corner

This private fixture verifies a concrete terrain edit across Luanti and OpenTTD 14.1. It is not a general `.sav` writer, and it doesn't change production gameplay or rewrite the input. OpenTTD's own `AITile.RaiseTile` command creates the edit and OpenTTD's normal writer saves it. The scope is one qualified, flat, unowned temperate grass footprint.

The unchanged seeded 256×256 source from the [road construction lab](OPENTTD_ROAD_CONSTRUCTION_EXPORT.md) has a loaded bus already approaching its original stop and a second bus parked in the depot. This lab does **not** add the road from that experiment. Away from both vehicles, the north corner of tile **45159** rises from **1 to 2**. It is one physical vertex shared by four rendered tiles, not four independent height edits:

| Tile | Stock slope after edit | Encoded mask |
|---|---|---:|
| 44902 | Raised south corner | 2 |
| 44903 | Raised east corner | 4 |
| 45158 | Raised west corner | 1 |
| 45159 | Raised north corner | 8 |

Native Luanti reads the actual saved height lattice through the existing map adapter and uses the production `landscaping` and `terrain` rules to preview, price, and apply the corner to a disposable grid. It also verifies a stale plan cannot be applied twice. The fixture's low construction setting prices `PR_TERRAFORM` at **£187**, and its four mature grass surfaces cost **£15** each to auto-clear. The **£247** total must match both AITestMode and native execution; the native query must leave the corner unchanged. These are the stock [terraform command](https://github.com/OpenTTD/OpenTTD/blob/14.1/src/terraform_cmd.cpp#L178-L321) and [ground-clearing rules](https://github.com/OpenTTD/OpenTTD/blob/14.1/src/clear_cmd.cpp#L26-L43), not a handmade deformation of the save bytes.

An independent, untouched stock control pauses at the exact edited tick **2569**. Only one entry in `MAPH` and the four incident grass entries in `MAP5` may differ; road geometry and the other map planes may not. The company treasury and construction expense bucket must differ by exactly the quoted charge. The protected encoded stock chunks are compared byte for byte, including the complete vehicle pool, clock, packets, payments, orders, and facilities. The transient terraform quota may have replenished by the paused sample; the Luanti command plans a one-corner fixed-point deduction but this does not claim an intermediate stock quota observation after execution.

The independent native reopen verifies the same terrain and paused traffic state, then resumes the untouched loaded bus. It delivers all five original passengers, stages their £9 before settlement, and books that fare only once. The ordered reserve remains parked. Nine deliberately unsupported inputs, including a different corner/operator, a multi-corner mask, protected ground, insufficient funds/quota and an invalid height cap, fail closed.

## Reproduce

In a unique private `TMPDIR`, generate the unmodified `source.sav` using the generator in [the road construction lab](OPENTTD_ROAD_CONSTRUCTION_EXPORT.md), then run:

```sh
python3 tests/openttd_terraform_export.py \
  --openttd "$OPENTTD" --share "$STOCK_DATA" --luanti "$LUANTISERVER" \
  --source "$TMPDIR/source.sav" --output "$TMPDIR/raised.sav" > "$TMPDIR/raise-proof.json"
```

The script creates only a new, distinct output after comparing and reopening it. Keep `.sav` files private; the proof JSON contains the observed outcomes and digests. This lab does not qualify other terrain sites, lower, level, remove objects, or claim general save interchange.
