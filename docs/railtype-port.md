# Ordinary rail to electrified rail

This is a detached **OpenTTD 14.1** source port, not a currently exposed building tool. The main standard-gauge game runs unchanged. Use `mods/bayline/openttd/rail_types.lua`.

## Three separate rail checks

- A tile's railtype is its own field, not the track-direction bitmask. `tile_type(m8)` / `set_tile_type(m8,type)` preserve the two high bits of the original map byte. Source IDs: `0 RAIL`, `1 ELRL`, `2 MONO`, `3 MGLV`.
- Ordinary rail and electrified rail are mutually **physically compatible**, but an electric locomotive is powered only on `ELRL`. Steam and diesel are powered on both. The checks are `is_compatible`, `has_power`, and `depot_accepts(kind,vehicle_type,tile_type)`; OpenTTD buys engines by power and wagons by physical compatibility.
- A routed consist accumulates the powered masks of its actual non-articulated powered units. An electric locomotive with an unpowered ordinary carriage cannot route over ordinary rail. A mixed consist can route there if it has a powered diesel/steam unit, but only bodies whose own current tiles supply power contribute HP. Use `consist(parts,disable_elrails).compatible` for the train route and `unit_power` per physical body. `flags(entry(type).compatible)` is a **railtype** physical-compatibility mask for board adapters, not the train route mask.

`company_types(engines,company_id,climate,calendar_day,disable_elrails)` reproduces the vanilla recalculation. Supply real runtime engine intro dates and each engine's company-availability bitmap. Climate and company IDs are zero-based. A wagon does not introduce a type; an accepted preview can introduce it to its company, and the type persists after qualifying public introduction (`intro_date+365`) even when a model retires. Use `available(type,company_mask,hidden_mask)` for the construction gate. Do not use the base model year as a live purchase check.

The 14.1 disable-electric setting remaps stock electric catalog requirements to ordinary rail, hides wires, and keeps existing electrified tiles' raw type. A conversion from hidden electrified rail back to ordinary is a no-op. A previously electric physical unit marked by `flag_existing(unit,true)` retains its legacy flag after re-enable; `ConsistChanged` accumulates the powered mask before applying that flag to a saved body. Do not replace type 1 everywhere. `catenary_drawn` ports the rendering predicate, not pylons or wires.

## Conversion contract

`quote_convert(board,ids,target,{owner,available,hidden?,disable_elrails?,prices?,cash?})` is read-only. Provide the board's actual stock iterator output (orthogonal or diagonal). `board.tile(id)` describes the tile kind, railtype, owner, bitmask or facility-specific fields. A rail bridge/tunnel pair must expose reciprocal `other` IDs and identical `length` (interior tiles, not heads). The ordinary-company command covers plain/signalled rail, depots, regular stations, waypoints, level crossings, and paired rail spans. Neutral/deity/NewGRF semantics and conversion into/between monorail or maglev are out of scope.

- On standard prices ordinary rail costs $100, electric $150. Conversion uses labour (one eighth of the new rail cost), plus any positive material difference, capped by removal/rebuild. Net prices: $68/old piece to electrify; $12/old piece to remove electrification. Supply the current price snapshot if prices inflate.
- Source conversion skips non-rail, already-target, hidden electric→ordinary, and foreign entries. If nothing can convert it returns a command error; an accepted subset is charged together. An optional insufficient-funds result does not change or trim it. With compatible standard-gauge types, train occupancy alone does not reject conversion.
- Plain and signalled tiles bill for actual track bits, but overlapping pieces count squared for infrastructure; two nonoverlapping parallel quarter-track pieces are not squared. Station/depot/crossing quotes bill one; blocked rail stations transfer no infrastructure; crossings transfer two. A span charges `length+2` once and moves `(length+2)*4` infrastructure even if only one head is selected.
- Plan outputs `updates`, `charged`, `errors`, `infra`, and candidate `free_reservations`. The host must revalidate topology, ownership and funds, apply type edits/debits together, release affected physical train reservations once, refresh track layout/depot/station/span/map graphics, and recompute power and routes. Exact order-sensitive post-conversion reservation retry, area geometry, and runtime changes are not implemented here.
- `add_piece_type(existing,requested)` is the successful existing-track branch of `CmdBuildSingleRail`. After occupancy/geometry/signal checks, adding a new electric piece to an ordinary shared tile first converts the existing pieces. Adding ordinary track onto already electrified rail leaves that tile electrified. The added bit is billed at the requested build price separately.

## Authentic electric vehicles

| Stock ID | Model | Base intro | Stock image | Bodies | Speed | Power | Bare mass |
|---:|---|---|---:|---:|---:|---:|---:|
| 23 | SH ‘30’ | 1965-01-01 | 20 | 1 | 160 km/h | 3,600 hp | 84 t |
| 24 | SH ‘40’ | 1973-01-01 | 20 | 1 | 176 km/h | 5,000 hp | 82 t |
| 25 | ‘T.I.M.’ | 1984-01-01 | 21 (+22 rear) | 2 | 240 km/h | 7,000 hp total | 90 t/body |
| 26 | ‘AsiaStar’ | 1992-01-01 | 23 (+24 rear) | 2 | 264 km/h | 8,000 hp total | 95 t/body |

Use the **SH ‘30’** first for original Blender art and validation. SH ‘40’ intentionally shares original stock image 20 (sprite base `0x0B79`, symmetric four-direction stock set). The fast pairs need reciprocal powered bodies. Do not expose conversion or purchase in a normal UI until there is catenary and vehicle art, typed physics/depot/reservations, and verified live gameplay.

`tests/rail_types.lua` covers explicit expected cases. `tests/rail_types_upstream.py /path/to/OpenTTD-14.1 [lua5.1]` compares hash-pinned C++ `CmdConvertRail` quote/exec with an isolated board/ownership shim, exact m8 and build/clear/convert formulas, company masks, elrail setting toggles and consist power, and the original electric rows.
