# Stock content timeline

**Target:** native OpenTTD **16.0-RC1**, commit
`07b339c0aaeb0a87be9490b2f1c3f17c6b00b837`. Close the fresh-game
content gate before adding later unlocks. A model or a catalogue row is not
a playable port.

## Order and verification

1. Start with an ordinary fresh **Temperate, January 1950** game, the
   reference release’s default. This includes stock content introduced
   earlier that the player can use immediately. Keep separate opening
   lists for earlier starts and the other original climates; they are
   required for the complete stock port, not omitted as variants.
2. Measure **what the company can build or buy**, not what happens to appear
   on one generated map. Track vehicles and cargos, airports, road/rail
   types, infrastructure, industries, houses, climate scenery, tools,
   economy and routes. Distinguish built-at-generation, player-funded, and
   later random openings. Content with per-company previews, optional
   licenses or retirements must be verified in the stock runtime as well.
3. If a feature cannot be used because its underlying system is partial, port
   that system from source first. Mount the opening-era content with complete
   native assets, menus and end-to-end use, and make it work together with
   the other opening systems. Test it on a default campaign without commands.
4. Close the opening ledger, then move forward by source date/cohort; do not
   use new late stock to postpone an opening-era blocker. [State of the Port](PORTING.md)
   continues to track source parity and remaining cross-cutting systems.

For each item record these separately: **source data verified**, **native
offer found**, **native play and restore verified**, and **complete**.
A transport offer is not complete until a player can build its infrastructure,
buy/order it, operate it, close and reopen using the same vehicle, and
get stock-appropriate results. Infrastructure must work at the stock
dates, permitted geometry, applicable modes and costs. No placeholder art.

## First reference pass

The live catalogue was read by a disposable, non-building script in the
actual stock release. See the [Temperate opening catalogue](../tests/fixtures/openttd-opening-1950-temperate.json).
Two new worlds with seeds 1751 and 42 agreed on these availability counts.

| Opening group | What stock OpenTTD offered | LuanTTD closure work |
| --- | --- | --- |
| Railway | 3 locomotives and 11 wagons, one conventional rail type | Each combination needs an ordinary depot, appropriate cargo/station pairing, real running and reload proof. Verify switching, signals, multi-train routing and default no-signal operation where applicable. |
| Road | 1 bus, 10 freight vehicles and one ordinary road type | Test the day-one native orders and paid service for the entire list, including native farm, wood, ore, steel and valuables routes. |
| Water | 3 vessels: the MPS ferry, MPS oil tanker and Yate cargo ship | Ordinary depot, dock and paid service for the ferry, tanker and Yate with default Goods or Coal, Grain, Livestock, Wood, Iron Ore, Steel or Valuables refits. Close remaining stock dry-cargo refits and common ship order/fleet gaps. |
| Air | Sampson U52, Coleman Count, Bakewell Cotswald LB-3; the 4×3 Country Airport | Close any remaining runway, loading, purchase offer, and save/restart gaps before 1955’s City Airport. |
| Bridges | **10 styles**, IDs 0–9 | The source rule table already has all 13 dated styles. All ten [opening styles](OPENING_BRIDGES.md) are usable with road and conventional rail, subject to the stock length, price and construction restrictions. |
| Cargo and industry | 11 cargo types. In seed 1751, 10 stock onshore industry types were generated. | Compare climate files and generation, all onshore supply chains, funding/openings/changes, rates and cargo handling; bank/city conditions vary. Oil rigs are not a generation-time industry and can open from 1960 onward. |

Additional live regression points: the 1930 Temperate opening had 17
buildable vehicles; the 1950 Arctic/Tropic/Toyland probes returned 29/31/28
respectively. In the 1955 Temperate probe City and Country were both
available. These are reference observations, not claims of port completion.

### Bridge system checkpoints

- OpenTTD's six ordered middle-span classes and its stock pillar-position
  masks are ported and matched against the release C++ across both axes,
  all 13 styles and lengths through the stock default limit. This is the
  structure layout rule, not a claim that the missing bridge art is mounted.
- The native road bridge picker can replace a same-route bridge in use.
  The occupied bus, vehicle orders and two ramp connections survived an
  upgrade and a server restart; the trip finished and paid. Replacement
  quote, ownership and clearance are checked separately from a new build.
  The native bulldozer quotes and charges the stock road demolition cost
  without disturbing an existing road below; construction and replacement
  also preserve existing plain rail beneath the span. Rail replacement
  preserves the active consist and both reservations. All ten normal opening bridge styles are
  available for roads and conventional rail, including [both short
  conventional rail bridges and all three cantilevers](OPENING_BRIDGES.md),
  [concrete suspension](CONCRETE_SUSPENSION.md),
  [both steel suspension finishes](STEEL_SUSPENSION.md), and the
  [high-speed steel girder](FAST_GIRDER.md). Native sessions verified
  paid service after restart and occupied-span replacement.
  Remaining: later tubular styles, other rail types and remaining
  native underlay handlers.

## Reproduce

- `python3 tests/openttd_content_timeline.py /path/to/16.0-RC1/source`:
  verifies the exact commit, then extracts all 256 vehicle base-date rows,
  13 bridge types and 9 buildable airport types from the release tables.
- `python3 tests/openttd_timeline_native.py /path/to/openttd --year 1950 --seed 1751`:
  checks the actual stock company catalogue in a disposable world. Repeat
  with `--climate arctic`, `tropic`, or `toyland` to keep separate baselines.
- `python3 tests/opening_stock_bridge_catalog.py /path/to/16.0-RC1/source`:
  compares dated length admission to the release source and asserts all
  ten stock opening styles were exposed in the native reference.
- `python3 tests/opening_stock_bridge_pieces.py /path/to/16.0-RC1/source`:
  compiles the original piece selector and pillar tables and checks each
  axis, length, style and middle position against the Lua implementation.
