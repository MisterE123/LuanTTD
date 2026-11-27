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

## Don't rebuild an unused day's worth of vehicle poses

The paced owner already samples the current road, train, tram, ship
and aircraft state. It no longer builds a second parallel playback
history inside each stock day. Alternate daily playback still records
its original timeline. Route initialization, authoritative vehicle
and train ordering, and all loading, financial and sound events remain
on the same source tick.

In two alternating native 256×256 campaign measurements with 128 active
road vehicles and two stock freight trains, median temporary allocations
per simulated day fell from **2,788 → 2,455 KiB** and **2,802 → 2,443
KiB**. The same-day complete checkpoint and shared references matched,
including 65,536 map tiles. Ordinary uninstrumented CPU medians also
fell in the two series, but tail timings varied enough that this is
primarily evidence of less allocation, not a guaranteed FPS change.

Four-mode native motion and exact economic replay passed again. The
native Linux oil tanker was visible at the correct berth and delivered
220 kL for $1,970. Actual paid tram, rail-coal, ship-coal, and multi-ore
order/load/payment tests ran with the history disabled.

## Periodic saves give views another turn

The checkpoint's callback can serve an in-order, read-only request
after encoding and again after compression, before digesting and
atomically replacing the file. A pending edit still waits; it cannot
run from that callback. Periodic checkpoints use faster Zstd level 1.
Explicit command saves, manual checkpoints and shutdown keep level 3.
The unpacked graph, signature, SHA-256 verification and reader did not
change.

In two alternating pairs on the same 1024×1024 fixture, median reply
time for requests arriving during a save fell from **76 → 26 ms**
and **126 → 26 ms** (13–17 reads in each run). The respective p90s fell
from **207 → 187 ms** and **228 → 167 ms**. For one identical 21.1 MB
encoded graph, level 1 was about 5% larger than level 3 (4.21 vs 4.00
MB) and restored to identical bytes. Whole-day traffic and worst reply
times still varied. Native save/reopen and settlement tests cover the
new path independently from the timing observations.

### AutoRail ghost while the worker is busy

Native Luanti 5.15.2, generated 1024×1024 Temperate checkpoint, two stable
11-tile Autorail gestures, baseline/candidate/candidate/baseline. The preview
includes the actual priced footprint and mesh list. Before this change, even
a hover finished the rest of a partial simulation day; a hover also waited
for a full periodic save if it arrived during encoding.

| Sample | Baseline | Between ticks and save phases |
| --- | --- | --- |
| All running hovers, p90 | 585–632 ms | 76 ms |
| Hovers submitted during a save, median | 1,291–1,475 ms | 25–76 ms |
| Hovers answered during encoding | 0 | 12–13 per replay |

Medians for *all* running hovers remained about 25 ms. The slowest sampled
candidate took 279 ms; an individual compression/write phase still blocks.
Preview samples did not spend money, and explicit rail commits still finish
the day, recheck the visible ticket and save before acknowledging the edit.
These measurements describe construction feedback, not frame rate or
vehicle-pose animation.

Reproduce with:

```sh
LUANTTD_QA_AUTORAIL_HOVER=true tests/campaign_save_road_hover_native.sh \
  luantiserver 35ffba3 GENERATED_WORLD CONFIG NEW_OUTPUT_DIRECTORY
```
