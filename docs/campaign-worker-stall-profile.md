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
