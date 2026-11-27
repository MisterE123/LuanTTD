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

## Recompute only a river component the viewport actually reads

A road or construction edit can advance the global topology number even
when waterways are unchanged. The observer used to scan the whole board
and trace every river before it could answer the first visible river tile.
It now starts with that tile's connected river component. Outlet seeds
still sort by tile ID; inland pools still use height and ID, and upstream
traversal still uses the same four ordered neighbors. A plain flood
outside a cached component's dependencies can still preserve it.

A native async test decoded a real generated 1024×1024 world with 20,359
river tiles. Every tile's direction, including calm tiles, matched the
old global routine. For 60 topology refreshes sampling three actual
32×32 sectors, direction lookup took 5.54–5.72 s before and 4.08–4.36 ms
after. This measures river-direction work only, not the full snapshot
or client FPS. Tests also cover a changed outlet, a river rejoining
two components, ignored distant tides and recovery from skipped revisions.

## Bound the large reference hash during checkpoint encoding

The wide encoder's reference hash used to grow past a million objects
as a single allocation and rehash. It now partitions references by
stable raw terrain shape and woodland type, with a general fallback
bucket. Buckets still compare the original table objects, including
when a tile or tree is first encountered through another alias. A
single first-encounter counter produces the same reference IDs and
wire bytes. The partition is transient and not part of the saved game.

Periodic checkpoints now also check for read-only viewport work while
emitting sparse registries, sweeping dense array metadata, and just
before joining the final string. Commands and simulation edits remain
blocked until the atomic save completes. The save prefix, Zstd level,
checksum and crash recovery path are unchanged.

The same generated 1,024×1,024 map was replayed with road, rail, ship
and air services at 4× on native Luanti. The longest gap between worker
view samples in two instrumented baseline runs was 389 and 597 ms,
versus 203 and 214 ms with the changes. The corresponding 90th
percentiles were roughly 116 ms and 114 ms. This is a small
replay comparison, not an FPS claim; allocation, compression and
file writes can still block individual samples. The codec also
matched the complete packed bytes of the same active fixture.

## Do not stage offscreen road actors

A viewport packet can request up to nine sectors. It now builds the
union of their 32-tile road bucket coordinates before staging actor
records. The worker still reads each road vehicle's actual horizontal
pose once, and uses the same exact bounds for every returned sector.
Actors outside the union need no staging row. Overlapping and
nonaligned windows, hidden state, and the simulation itself are
unchanged.

A native worker fixture bought and routed 960 buses. The unmodified
and scoped projections returned identical static scenes, live poses
and interpolated poses for single, overlapping, separated, and empty
windows. Temporary Lua allocation across 20 observations fell from
4,446 to about 1,700 KiB for a narrow populated sector, and from
6,514 to 4,098 KiB for overlapping sectors. The empty window fell
from 3,135 to about 50 KiB. CPU timings varied by view; these are
worker allocation results, not client FPS numbers.

```sh
tests/campaign_actor_interest_native.sh luantiserver 1bbd702 /tmp/actor-interest
```

## Index long rail consists once per multi-sector observation

When a busy rail fleet is projected into several windows, the worker
now indexes the actual sampled bodies once for the packet rather than
scanning every train from every sector. A visible tail is enough to
return the whole sampled consist, even if the locomotive is entirely
offscreen. The final rectangle tests still decide visibility; ordinary
clipped snapshots return just the body positions within their bounds.
No movement, collision rule, save, or interpolation timing changes.

A projection-only LuaJIT fixture with 384 trains of 24 bodies each
compared single, overlapping, split, and empty requests. Every actor
reply matched. Across four nine-window batches, median CPU was about
183 → 15 ms per 96 observations. This deliberate long-fleet fixture
measures the projection, not simulation throughput or FPS. Native
rail-farm service also verified ordinary consists and payments across
a restart.

```sh
mkdir -p /tmp/old-rail-interest
for f in campaign_actor_projection campaign_authority_endpoint; do
  git show 9e20f4d:mods/luanttd_core/$f.lua > /tmp/old-rail-interest/$f.lua
done
luajit tests/campaign_rail_interest.lua /tmp/old-rail-interest
```

## Reuse unaffected tile rows when a sector changes

A visible house, field, or road edit can invalidate a sector without
changing every tile in it. With identical shared corner heights, the
worker now detaches only genuinely changed rows and reuses unaffected
ones, including rows after the first mismatch. Registry data, signal
aspects, and neighbor-dependent geometry still use the live world.
The host still receives the same complete sector when its scene
changes; the network protocol is unchanged.

Native Luanti 5.15.2 async worker timings (9 × 32² sectors,
192 road actors): a workload changing one tile per sector per
observation had a median **23.55 → 4.36 ms** across three pairs.
Stationary no-edit observations overlapped (**4.38 → 4.61 ms** medians).
A separate Luanti-state replay from an active 1024² campaign compared
complete edited and acknowledged packets from both implementations;
all matched, including scene/actors, detached registry fields, and
terrain. These are worker observation times, not client FPS.

```sh
lua5.1 tests/campaign_snapshot_scene.lua
tests/campaign_snapshot_bench_native.sh luantiserver 8610b6e /tmp/luanttd-row-reuse
```
