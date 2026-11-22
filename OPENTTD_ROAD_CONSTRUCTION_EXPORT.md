# One real stock road tile after a portable Luanti quote

This private developer lab builds a single flat, ordinary two-way road segment in a stock OpenTTD 14.1 world. Unlike the order-edit labs, it does not patch serialized data. The native stock command constructs and charges for the road, and the stock writer produces the output. The source is not modified, and this does not expose a general `.sav` editor or change production gameplay.

The seeded 256×256 fixture contains a company junction at source tile **44640**, unowned level grass at **44641**, and an existing isolated bus bay facing that gap at **44642**. There is one five-passenger bus already in service toward its original east bay, and one parked bus with an independent, already stored order to the isolated bay. Before construction there is no edge into that bay. The lab doesn't need to synthesize, replace, or edit orders.

1. Luanti quotes a straight stock two-endpoint command using its existing `road_oneway`, `road_slope`, track follower, and stock road-price kernels. The old junction is already complete, so the only edit is two reciprocating half-bits on tile 44641, mask **10** (+X/−X). The quote accounts for the native difficulty setting. At the fixture's low setting, bare grass costs £0 to clear and the two £71 half-pieces cost **£142**. Seven out-of-scope probes, including non-flat ground, foreign ownership, a one-way approach, and a longer edit, fail closed before reaching the command.
2. An authorized private stock AI uses `AITestMode` with `AIRoad.BuildRoadFull` and checks that query mode does not build. It then executes the exact same native [road command](https://github.com/OpenTTD/OpenTTD/blob/14.1/src/road_cmd.cpp#L993-L1029), captures the charged price with `AIAccounting`, verifies both reciprocal edges, and saves. An independent stock process opens the input without issuing a construction command and advances to the **same pause tick**. All native map planes are compared; only the target road tile can differ, with no change to the height plane. Fixed-point company cash and the construction expense bucket are checked exactly. The vehicle pool, native clocks, orders, stations, depots, incoming passengers and payment ledger must be identical between the edited and the unedited checkpoint.
3. A separate native reload verifies the paused road and ledger again. In that disposable process only, the parked bus is started on its unchanged pre-existing order. It physically crosses the new tile and services the newly connected bay. The unrelated original bus continues its original trip and the same five passengers generate the expected staged and settled £9 fare. This proof run does not rewrite the output checkpoint.

## Reproduce

Use a unique, private workspace `TMPDIR`. Both `--source` after generation and `--output` are private local saves and are not packaged. Proof JSON can be kept separately.

```sh
export TMPDIR="$(mktemp -d /private/qa_temp/stock-road-author.XXXXXX)"
python3 tests/openttd_road_construction_export.py --generate \
  --openttd "$OPENTTD" --share "$STOCK_DATA" --source "$TMPDIR/source.sav"
python3 tests/openttd_road_construction_export.py \
  --openttd "$OPENTTD" --share "$STOCK_DATA" --luanti "$LUANTISERVER" \
  --source "$TMPDIR/source.sav" --output "$TMPDIR/built.sav" > "$TMPDIR/proof.json"
```

The lab needs an actual OpenTTD 14.1 executable and matching stock data including OpenGFX, plus a native Luanti server. Ports can be overridden on both processes. It rejects a nonexclusive output; it creates a new file only after comparing against stock and verifying actual reopened gameplay. It does not handle slopes, custom NewGRFs, other owners, roadworks, arbitrary drag lengths, or additional tile modifications.
