# Stock-assisted authoring with two moving buses

This private developer lab extends the two-bus [junction oracle](OPENTTD_ROAD_JUNCTION.md), not the user-facing game. It requires the **merging** fixture and its stock trace. Both MPS Regal buses must be moving on the same active destination at the export handoff. The lead carries five passengers; the second bus is closing from the south arm with a different heading.

At native stock tick **2545** in the verified run, both buses are committed to the east bay (station 0, tile 44392). LuanTTD advances both active actors independently against stock and produces a journal intent. It requests **only lead bus 4's future return order** (station 1, through-stop 44387) be changed to station 2, the already-connected south bay at tile 44644. The lead's current east-bay order survives, so it still delivers its passengers as planned. The follower (bus 5) keeps its own already-existing route and order list; it must still serve the east bay independently. Using a different station, not merely a timetable flag, makes a real later visit verifiable.

The stock process must separately reconstruct the exact paused draft. During authoring the decoded save differs in exactly one destination byte. The whole native vehicle pool (with both complete raw rows), clock, order lists, all untouched orders, cargo packets, payments, station pools and company finance pool are checked after the patch, an unmodified stock writer save, and an unmodified stock reader reopen. Six negative checks reject the wrong source or opening tick, another actor's pose change, a changed onboard packet, a changed checksum, or an attempt to replace the active order. The older moving-plus-parked-reserve path remains independently qualified.

The authored world resumes under actual OpenTTD 14.1. Both active legs reproduce the initial geometrical overlap, merge wait and release exactly. The same five passengers are delivered at the original east bay, yielding the original £9 once, with the staged stock CargoPayment observed before cash settlement. The follower completes the original visit; the lead's new future order becomes active and the lead actually arrives at southern bay 44644 under that order. This experiment claims no general `.sav` writing, no broad replay of a stock economy in Luanti, and no changes to production gameplay.

## Reproduce

Generate the private stock **merge** save and its proof JSON using the commands in [the junction oracle](OPENTTD_ROAD_JUNCTION.md). Use a unique private workspace `TMPDIR`. Keep both `.sav` inputs and outputs private. The lab exclusively creates its output only after the verified native reopen/playthrough; don't point it at a source or an existing filename.

```sh
python3 tests/openttd_dual_active_export.py \
  --openttd "$OPENTTD" --share "$STOCK_DATA" --luanti "$LUANTISERVER" \
  --source "$TMPDIR/merge.sav" --trace "$TMPDIR/merge-proof.json" \
  --output "$TMPDIR/merge-authored.sav" > "$TMPDIR/dual-active-export-proof.json"
```

The exact native tick gate is fail-closed. If a heavily loaded host causes the stock console to overshoot it, rerun from the unchanged source rather than relaxing the gate. Stop/arrival observation timestamps can vary with native pause sampling; the handoff and compared warm checkpoints cannot.
