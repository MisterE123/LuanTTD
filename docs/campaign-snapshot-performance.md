# Worker observation performance

A full worker observation covers up to nine 32×32 interest sectors. It
still observes the same tiles, vehicle state, passenger queues, signal
aspects, and window/receipt rules. Only allocation of unchanged terrain
rows is avoided. The worker compares the exact detached tile fields and
bounded nested values, packed corner bytes and computed river direction
against the acknowledged scene. It independently rebuilds and compares
registry projections, so an in-place station rename or a changed
industry record still sends its updated scene. On mismatch, stale receipt
or LRU eviction the worker sends a complete detached scene as before.

## Reproduction

```sh
lua5.1 tests/campaign_snapshot_scene.lua
lua5.1 tests/campaign_authority_endpoint.lua
tests/campaign_snapshot_bench_native.sh "$(command -v luantiserver)" \
  eaea797a4558d672f0065859747ec322da019d4f /tmp/luanttd-snapshot-bench
```

The benchmark runs both implementations in the same native Luanti
async Lua VM. It uses a 128×128 test world, a stationary 3×3-sector view
and 192 running road vehicles, with 115 visible. Three sets of 40 full
acknowledged observations each took **28.360 / 30.034 / 32.217 ms** on the
baseline and **2.645 / 3.108 / 3.222 ms** after the patch (median **30.0 →
3.1 ms**). These are worker observation times on the tested machine,
not end-to-end frame rate measurements; they exclude native renderer,
player input and IPC transfer.

## Native actor and machinery observations

The road observer now groups exact interpolated coordinates into 32×32
sectors once per reply. It only looks up slope/height and builds a pose
for a vehicle an actual requested window sees. Overlapping or nonaligned
windows still receive the same detached actor, even when its rendered
tile differs from its discrete simulation tile. Hidden depot records,
bore poses, vehicle order, cargo, and sound flags are unchanged.

The machinery observer indexes stock coal and oil footprint coordinates
by sector. It still reads live GFX, animation frames, clock phase, and
ground tile markers each time. A saved world starts with a fresh index;
funding and remounting can refresh it, while closed or cleared machinery
stops appearing immediately. Neither change reduces simulation work,
the number of observations, or their cadence.

```sh
lua5.1 tests/campaign_projected_actors.lua
lua5.1 tests/campaign_authority_endpoint.lua
lua5.1 tests/industry_machinery_world.lua
tests/campaign_actor_perf_native.sh "$(command -v luantiserver)" \
  2aeadf51a18433c8bd139b3aca53d5b90f1a1404 /tmp/luanttd-actor-bench
```

The native Luanti 5.15.2 async benchmark alternates the exact two
implementations. Median process CPU time per nine-sector batch:

| Work measured | Baseline | Indexed |
|---|---:|---:|
| Road actor replies, camera 1 (136 of 192 moving buses visible) | 0.772 ms | 0.532 ms |
| Road actor replies, camera 2 | 0.677 ms | 0.488 ms |
| Machinery only, 48 stock footprints | 0.055 ms | 0.018 ms |
| Machinery only, 1,024 stock footprints | 1.688 ms | 0.019 ms |

Camera 1 required 408 terrain lookups instead of 576. The benchmark
recursively checks complete road actor replies at 17 fractions across
four viewport shapes, including overlapping windows, and complete
machinery packets at eight tick boundaries. Machinery uses real stock
footprints at sparse positions in a 4,096×4,096 address space. The
measurements exclude initialization, world generation, native drawing,
network/IPC, and the first build of the persistent machinery index;
they are not frame-rate or overall tick-rate claims.
