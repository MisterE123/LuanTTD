# OpenTTD 14.1 rail roster and finance rules

`mods/luanttd_core/openttd/rail_roster.lua` is a pure stock-data and rules module. It does not purchase, assemble, dispatch, load or charge trains in a live world. Prices below are base purchase prices at medium cost/no inflation in OpenTTD's internal base currency. Speed uses the integer stock train cache units. Sold availability remains company- and date-dependent.

| Stock ID | Vehicle | Base price | Speed | Power (hp) | Empty mass (t) | Stock climate(s) | Default cargo |
|---|---|---:|---:|---:|---:|---|---|
| 0 | Kirby Paul Tank | 10,937 | 64 | 300 | 47 | Temperate | None |
| 1 | MJS 250 | 12,500 | 80 | 600 | 65 | Arctic, Tropic | None |
| 8 | Chaney 'Jubilee' | 20,312 | 112 | 1,000 | 131 | Temperate | None |
| 9 | Ginzu 'A4' | 29,687 | 128 | 1,200 | 162 | Temperate | None |
| 10 | SH '8P' | 34,375 | 144 | 1,600 | 170 | Temperate | None |
| 15 | Floss '47' | 28,125 | 160 | 2,580 | 112 | Temperate | None |
| 27 | Passenger Carriage | 1,929 | No independent limit | 0 | 25 | All | 40 passengers |
| 29 | Coal Truck | 1,375 | No independent limit | 0 | 18 | Temperate, Arctic | 30 coal |
| 30 | Oil Tanker (data only) | 1,562 | No independent limit | 0 | 24 | Temperate, Arctic, Tropic | 30,000 L oil |

## Host contract

- `catalog()` and `entry(id)` return copies of stock rows. `purchase_price(id, opts)` and `prices(opts)` implement the current price calculation, including stock inflation/difficulty and optional overrides from authoritative `_price` values.
- `stats(parts, opts)` accepts a dense ordered list of stock IDs or `{stock_id=..., cargo_count=...}`. It returns exact stock lengths (8 pixels per vehicle, 16 per tile), predecessor coupling distances and physical center offsets from the lead center, total length, front and rear overhang, tare/current/maximum weight, power, original acceleration, slope resistance, tractive effort, air drag, axle resistance, native vehicle and track cap speeds, annual running charge, and default cargo capacities. A last element in `coupling` is the stock trailing half-length offset, not distance to a nonexistent vehicle. The game freight multiplier must be passed as `freight_trains`; cargo weight is rounded separately at each vehicle, not at the whole-train level. Supply current occupied-track speed caps through `track_limits`. Running bridge/order caps are applied separately by `current_speed_cap(stats, order_limit, visible_bridge_limits)`.
- `quote(depot, owner, parts, opts)` checks ownership, standard/electric compatibility, selected stock climate, supplied company availability and optional cash/pool/unit-number limits. The host depot shape is `{kind="depot", id=..., owner=..., railtype=0}` (1 for electrified). In a real purchase, pass `opts.climate`, authoritative `opts.available(id, owner)` and company railtype flags, pool availability and free unit numbers, cash and train length setting. It is a combined quote for an explicit list, not the original separate build-and-move commands. No parts are added and no cash changes. `roster_preview=true` explicitly bypasses company/climate availability for controlled preview worlds; it is not stock purchase behavior. `introduction(id, start_year, generation_seed, startup_random)` ports the vanilla seeded startup date, not preview, retirement, or general availability.
- `load_slice(part, waiting, gradual)`, `unload_slice(part, gradual)`, and `loading_wait(length, platform_tiles, loaded, unloaded, opts)` implement default per-vehicle amounts, stock train pulse/idle waits, and optional short-platform penalty. The station layer must select destination-eligible packets and count actual loaded/unloaded amounts. This module does not create, age, transfer, or deliver packets.
- Locomotives consume stock annual running costs even if waiting on a signal or loading unless explicitly stopped and stationary. The host should increment `running_tick(counter, manually_stopped, speed)` once per OpenTTD tick, not once per movement pass. At the day boundary use `day_running_charge(annual_fp, running_ticks)` and reset the counter, then `debit_fraction(company_fraction, cost_fp)` to carry the company's existing shared 8-bit fraction and post the whole cost to train running expenses. The default Kirby costs 280,000 fractional units annually (integer display 1,093), the MJS 338,000 (1,320), the Jubilee 672,000 (2,625), the Ginzu A4 784,000 (3,062), and the SH '8P' and Floss 47 728,000 each (2,843); a standard wagon does not add annual running cost. The denominator is 365 days times 74 ticks per day. Do not replace it with a monthly flat charge.

The A4 is one stock length-8 single-headed steam locomotive (original image
index 1, native model selector `a4`), not independently articulated engine
and tender vehicles. With one stock Passenger Carriage it costs 31,616 before
inflation, weighs 187 t empty and 189 t full, and has original acceleration
24. In a standard 1950 Temperate world it has the unrandomized 1935-01-01
base introduction, a 20-year installed vehicle life, and a 30-year design
life parameter for the stock reliability phases. Earlier starts can draw
a different introduction and public sale date. Nothing here enables native
placement or dispatch before the matching 3D model and host mode are ready.

The SH '8P' is an original standard-gauge, stock length-8 single-headed
steam locomotive with image index 0, not a coupled locomotive/tender pair.
The newly authored `sh_8p` mesh includes the tender in the original one
logical head; the standard stock passenger carriage remains separate.
A carriage makes the total base price 36,304, mass 195 t empty/197 t
full and cached acceleration 32. The raw 1954-01-01 intro can be randomized
in earlier starts. Physical life is 23 years, and the stock design-life
parameter is 25. No 1950 sale bypass: later public availability follows
the actual seeded world clock. The owned standard passenger lane uses the
same physical track, signals, braking, consist timing and fare as before;
it mounts the engine only with its dedicated mesh and atlas available.

The Floss 47 is an ordinary stock length-8 single-head diesel, original
image index 4 (selector `floss47`). One stock Passenger Carriage yields
30,054 before inflation, 137 t empty and 139 t fully loaded, stock original
acceleration 72, and a full running day costs 1,994 fractional units.
Raw base introduction is 1962-01-01; a 1966 Temperate campaign starts with
this design publicly available at 48 design-age months. Physical vehicle
life is 22 years; the stock design-life parameter is 33 years. The exact
retirement date is determined by the scenario startup seeds and time
settings, not by a fixed year equal to introduction plus model life.

Oil Tanker #30 is neutral standard rail (stock image 36, length 8),
with no independent speed limit or running cost. Stock oil (slot 3) is
liquid freight; each simulation unit is 1,000 L. Its 30 units add 30 t
at the default freight multiplier or 150 t at 5×; loaded wagon mass is
54 t or 174 t respectively. The stock gradual pulse is 5 units (5,000 L).
The raw date is 1925-01-01 and stock wagon initialization replaces
table model life with 255 (never expire). This is **data only**:
`entry`, `stats`, `purchase_price`, and the stock calendar expose it, but
actual `quote` rejects it with `RAIL_VEHICLE_NOT_MOUNTED` even in preview.
No purchasing or oil rail service is enabled by this row.

The module does not implement depot autoattachment/front-chain mutations, reservations, timetable or orders, true simulation scheduling, stock availability state, servicing/reliability lifecycle, resale or autoreplace, dual-headed/articulated vehicles, powered wagons, refits, wagon swaps, or NewGRF behavior. Those require their own host state and source-backed ports.

## Source and verification

Stock rows and constants are from OpenTTD 14.1 `table/engines.h`, `table/pricebase.h`, `table/cargo_const.h` and `timer/timer_game_common.h`. Source routines are from `engine.cpp`, `train_cmd.cpp`, `train.h`, `ground_vehicle.cpp`, `economy.cpp` and `company_cmd.cpp`. Licensing: GPL-2.0-only; see [COPYING.OpenTTD.md](COPYING.OpenTTD.md).

```sh
lua5.1 tests/rail_roster.lua
PYTHONDONTWRITEBYTECODE=1 python3 tests/rail_roster_upstream.py /path/to/openttd-14.1 [lua5.1]
```

The differential harness verifies pinned hashes and compiles source routines with a restricted vanilla-stock shim. It exercises seeded introduction dates, purchase price bases, coupling offsets, per-part mass/maximum mass and speed, consist acceleration and resistance caches, loading/wait integers, daily charge, and the company cash carry. Its deterministic matrix covers 7,500 consists and 228,077 vehicle rows. The separately scripted Lua fixture covers explicit quote rejection/preview gates and runtime formulas not suitable for the compiled shim. It is not a native fleet/availability/playability test.
