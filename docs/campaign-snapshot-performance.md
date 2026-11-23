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
