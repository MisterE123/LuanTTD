# Road construction response

Road preview and placement use the async campaign owner. A moving cursor
shows a neutral outline while the current candidate is being checked.
Road-stop drags show their clamped strip or rectangle immediately;
the worker supplies the price and validates the terrain and occupancy.
A confirmed obstruction is still red. When the player places a road,
one authoritative request plans and applies it, checking the displayed
price and footprint if a completed preview was shown. The host never
paints an unconfirmed construction. It asks for the next scene update
right after the owner accepts the edit.

In a controlled Luanti 5.10 Linux replay, both versions placed eight
45-tile ordinary roads with durable checkpoints. Median release-to-receipt
time fell from **80.89 ms to 40.48 ms**. Release to the updated road being
present in the host's terrain projection fell from **163.49 ms to 82.47 ms**.
These measure one local scenario, not framerate, client network delay or
the maximum delay in a crowded large world. The preview coalescing still
limits speculative checks to one at a time.

Reproduce with `bash tests/road_placement_latency_native.sh`, and set
`LUANTTD_QA_BASELINE_REV=101804b` to run the old owner/client path in a
disposable environment. Focused tests verify that an outdated displayed
price cannot debit funds, repeated placement does not charge twice, and
a valid local drag triggers a prompt scene refresh.
