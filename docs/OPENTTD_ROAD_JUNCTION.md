# Two real OpenTTD road vehicles at one junction

This optional lab answers a narrow traffic question: **Does OpenTTD 14.1 prevent all geometric overlap between road vehicles? No.** It reads paused captures from private stock saves after the dedicated server has advanced, then independently runs the existing motion, speed, proximity, and overtake kernels in a disposable native Luanti server.

Both MPS Regal buses are built and dispatched by ordinary stock AI commands from the same depot in a seeded 256×256 temperate world. They have independent order lists and actual station destinations. The T uses normal +X/−X roads and a +Y branch at source tile **44388**. The approach has a drive-through stop at **44387**, the south arm ends at bay **44644**, and the straight arm leads to bay **44392**. The road masks, flat corners, right-hand side, realistic acceleration, engine, cargo, order lists, owner and absence of custom NewGRFs are gated. Neither original save is edited. These are developer fixtures, not new playable save-import cases.

## Observed native behavior

| Case | Stock result | Independent Luanti differential |
|---|---|---|
| Following, then turning south | At ticks 1599 and 1603 the follower holds behind the leader and copies its speed. Both occupy the T at ticks 1611–1635, then take different arms. Their stock viewport boxes do not overlap in the captured interval. | 45 simultaneous checkpoints from ticks 1581–1669, exact for both actors; 3 blocked movement attempts. |
| Merging northward from the south bay onto the same +X lane | The five-passenger leader advances straight while the empty second bus arcs in. At ticks 2545/2549/2553, both advance, their world XY viewport sort boxes overlap, both `blocked_ctr` values are zero and the headings differ (5 versus 6). By tick 2557, stock holds the merging bus at the same pose and copies the leader's speed. | 15 simultaneous checkpoints from ticks 2525–2581. The merger is blocked on 11 individual attempts when its **proposed** heading is 5 even though its current heading is still 6. It resumes as the gap opens. |

The extent check reconstructs full-length stock world-axis **viewport sort** boxes from [the road vehicle's bounding-box math](https://github.com/OpenTTD/OpenTTD/blob/14.1/src/roadveh_cmd.cpp#L411-L434), [vehicle sprite submission](https://github.com/OpenTTD/OpenTTD/blob/14.1/src/vehicle.cpp#L1134-L1142), and [the viewport’s inclusive extents](https://github.com/OpenTTD/OpenTTD/blob/14.1/src/viewport.cpp#L673-L689). Those boxes are not physical hulls or the path-controller test. The latter uses the proposed pose/heading, distinct vehicle, Z gap less than six, stock directional distances and the candidate tile hash rectangle. It does not guard all different-heading paths against physical intersection. A visually generous 3D mesh can clip more than the stock sorting boxes predict; model changes and a generic collision rule are not equivalent.

Each continuation starts from its first exact native paused snapshot, advances the two actors in stock vehicle-ID order at every tick, and compares their independent future samples to the saved oracle. Comparisons include X/Y/Z, heading, tile, subframe, exact speed/subspeed/progress, blocked counter, bounded next-segment cache, per-actor clock and order timer, and passenger counts/packet IDs/source/age. The test uses the verified route edges, **not** future snapshots as motion inputs. It ends before the next station operation and does not emulate unrelated towns/finances. It does not prove traffic behavior in every junction, map or 3D player campaign.

## Running the lab

Use a new private workspace `TMPDIR`. `--generate` creates an exclusive private `.sav`; omit it to reopen the stock file and take checkpoints. Both the native OpenTTD dedicated binary and its stock data directory are required. Luanti is required only for the independent differential; use its actual server executable. Exact observed ticks can vary by pause sampling or native map-start timing, so classification asserts the actual encounter rather than fixed wall-clock waits.

```sh
export TMPDIR="$(mktemp -d /private/qa_temp/stock-junction.XXXXXX)"
base="tests/openttd_road_junction_fixture.py"
python3 "$base" --openttd "$OPENTTD" --share "$STOCK_DATA" \
  --generate --source "$TMPDIR/follower.sav"
python3 "$base" --openttd "$OPENTTD" --share "$STOCK_DATA" \
  --source "$TMPDIR/follower.sav" --limit 120 --expect follower \
  --luanti "$LUANTISERVER" > "$TMPDIR/follower-proof.json"

python3 "$base" --openttd "$OPENTTD" --share "$STOCK_DATA" \
  --generate --dispatch-delay 174 --source "$TMPDIR/merge.sav"
python3 "$base" --openttd "$OPENTTD" --share "$STOCK_DATA" \
  --source "$TMPDIR/merge.sav" --limit 130 --pulse .085 --expect merge \
  --luanti "$LUANTISERVER" > "$TMPDIR/merge-proof.json"
```

For iterative testing, `--from-trace` skips another stock acquisition and rechecks the private save's content and opening pause before replaying a previously produced JSON. Run concurrently only with independent `--port` and `--luanti-port`. No stock saves, binaries or graphics are distributed.
