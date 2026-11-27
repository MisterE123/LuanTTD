# Profiling simulation stalls in the native worker

Use a copy of a generated worker-owned campaign saved with simulation
running. Larger maps make queueing distinguishable from the ordinary
host polling interval. The probe uses a 32×32 viewport at (120, 120).

```sh
tests/campaign_stall_profile_native.sh "$(command -v luantiserver)" \
  /path/to/fixture-world /path/to/luanti.conf /tmp/luanttd-stall-profile
```

The test copies the checkpoint into an unused output directory and
instruments only the scratch game. It runs the real worker and host,
alternates viewport scenery and actor requests, and uses the same
monotonic clock to classify each request by what the worker was doing
when it arrived. The report separates waiting for the worker to sample
from waiting for the host to receive the reply. It also breaks out
landscape processing, post-landscape tick work, and checkpoint phases.
It does not change the game or fixture, and it is not a rendering test.

## Example: one generated 1024×1024 Temperate campaign

Luanti 5.15.2 on Linux, 26 seconds of playback, 122 observations;
source baseline [6f4c8dd](https://github.com/MisterE123/LuanTTD/commit/6f4c8dd2c7b326fbe418cced9ce3eee4e9faba7e).
This isolated the large-map cost without a large transport network.

| Request arrival | Observations | Median send to host receipt | p90 | Worst |
| --- | ---: | ---: | ---: | ---: |
| Outside saves and simulation days | 87 | 25 ms | 29 ms | 197 ms |
| During a save | 14 | 76 ms | 178 ms | 278 ms |
| During a simulation day | 21 | 591 ms | 804 ms | 945 ms |

A second run had 137 observations. Its in-day median was 532 ms and its
worst was 885 ms; the median outside both phases was again 25 ms.

The first run simulated a day in 617 ms at the median. The stock landscape
loop took a median 94% of the combined timed landscape and after-tick
work. The worker still served read-only requests during checkpoint
encoding, so the saves (1.16–1.65 seconds each in this series) did not
cause the longest waits. The production worker can already reply to
a queued view before a new day begins; a request that arrives after
that point still waits for the whole synchronous day.

The next high-leverage change is to make complete stock ticks separately
observable (or execute them in bounded batches), without reordering
RNG, cargo, vehicles, signage, or edits. Verify that motion cannot rewind
between samples and that commands still commit against a coherent tick.
Speeding up the individual tile rules will still help, but will not
remove the full-day wait on its own. The times above are from this one
fixture, not FPS measurements or latency guarantees.

## Paced stock ticks

Ordinary generated campaigns now run on one owner, but the owner can
sample scenery and vehicle poses between completed source ticks. The
stock daily routine and original tick order remain the same. Road,
rail, tram, ship and aircraft presentation reads the current native
pose rather than replaying the previous day's timeline. Rendering
still interpolates between bounded worker replies, and does not
predict movement through a stop.

The owner schedules ticks against elapsed time and gives its mailbox
a turn between short batches. An individual expensive tick can still
exceed the batch target. Construction and other requests that can
change authoritative state settle the current day first, as do saves.
When the owner finishes a day early to answer a command, it charges
those future ticks to the playback clock instead of accelerating the
campaign. Authored scenario playback keeps its existing scheduler.

In a paired native run on the same 1024×1024 fixture, with active
viewport queries and one deliberate fixed-day state capture:

| Observation | Baseline p90 send to host receipt | Paced p90 |
| --- | ---: | ---: |
| Actor frames | 545 ms | 76 ms |
| Full viewport observations | 507 ms | 178 ms |

All 1,559,990 tables and shared references were equal at day 22,
including the 1,048,576 tiles. The comparison excludes only the
presentation clock fraction, not random or vehicle state. Large saves
still produce occasional delays; these figures aren't a frame-rate
measurement. The native motion test also builds, buys and runs a bus,
train, ferry and aircraft, verifies monotonic completed stock
samples, exercises a durable edit and a worker restart, and checks
the complete paid-service state against the unsliced clock. A separate
26-second measured run without the extra fixed-day write had 1,270
worker batches (median 8.9 ms; p90 17.7 ms); requests during simulation
had p90 81 ms to the host, compared with 804 and 633 ms before.
The native Linux client also passed Autorail preview and purchase,
train order edits, station picking, bus dispatch, and fresh join/reopen.

```sh
lua5.1 tests/campaign_tick_step.lua
tests/campaign_tick_motion_native.sh "$(command -v luantiserver)" /tmp/live-stock-motion
```
