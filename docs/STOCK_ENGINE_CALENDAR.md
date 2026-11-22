# Original road engine public-release calendar

`mods/luanttd_core/openttd/stock_engine_calendar.lua` is a detached OpenTTD 14.1 port for original road engine designs. It does not install a live bus roster or change a company's depot. Its initial exact rows are the first three non-Toyland stock passenger buses:

| Global engine ID | Original model | Nominal source introduction | Vehicle service life | Design base life |
| --- | --- | --- | ---: | ---: |
| 116 | MPS Regal Bus | April 1, 1929 | 12 years | 40 years |
| 117 | Hereford Leopard Bus | January 1, 1964 | 15 years | 30 years |
| 118 | Foster Bus | January 1, 1986 | 15 years | 40 years |

Each stock row uses the original Temperate/Arctic/Tropic mask, decay speed 20 and zero early-retirement override. Service life is separate from the fitted reliability phases and from how long a new vehicle can be bought.

## Host API

```lua
local Engines = dofile(source.."/stock_engine_calendar.lua")
local calendar = {
  starting_year = 1950, generation_seed = generation_seed,
  startup_seed = original_startup_draw, climate = "temperate",
}
local foster = assert(Engines.prepare(118, calendar))
local offer = assert(Engines.snapshot(foster, Engines.date(1988, 1, 1)))
if offer.public then
  -- The depot still checks roadtype/company limits, assets, and funds.
end
```

- `date(year,month,day)` and `ymd(absolute_date)` use 1-based month/day and a stock day-zero origin of January 1, year 0. Do not read the old HUD's 30-day calendar as stock date. `stock(id)` returns a copy of the raw original row.
- `prepare(id, cfg)` returns a serializable design model; it does not touch world or RNG state. `cfg.starting_year` controls the startup two-year introduction exception. `cfg.startup_date` defaults to that year's January 1, but can represent an actual later activation date. `cfg.aging_stop_year` is the complete stock ruleset's cutoff (2050 by default for vanilla); `cfg.never_expire` is a fixed setting for this projection.
- The original startup roll depends on **two separately supplied quantities**: `generation_seed` and the global `startup_seed` draw passed to every original engine by `StartupEngines`. Equal original base date/type/grfid share intro entropy even when the vehicle IDs differ; design reliability uses the engine ID and its own two-draw seed. An authored game's deterministic seed or manufactured startup draw can produce deterministic dates, but is not evidence of matching an OpenTTD world's RNG stream. Use actual seed inputs for results claimed to match an imported historical OpenTTD run.
- `snapshot(model, at)` returns public sale eligibility, the separate global engine flag, signed age months, source introduction/public-release dates, current design reliability and its three phase durations, max and final reliability, speed-decay value, and nominal service life in days. `public_date` is the first public grant date for that design in this projection, not a promise that the engine stays on sale. `status` is `available`, `not_introduced`, `awaiting_public`, `retired`, or `wrong_climate`.
- A later model gets a randomized introduction (up to 511 days), except in the original start-year exception. In an already running world it becomes available on the first monthly engine loop at or after the introduction date plus 365 days. A model already introduced on initialization is considered for immediate public sale, subject to source reliability retirement. Calendars stop aging designs at the original aging cutoff. Phase 3 uses signed integer truncation rather than floor on a negative number.
- This is **public design eligibility**, not complete `IsEngineBuildable` or vehicle maintenance. No exclusive company previews/acceptance, NewGRF variant families, company permissions, dynamic never-expire setting changes, model hiding, vehicle aging/service/breakdowns, or economics are simulated here. `prepare_original(row, cfg)` accepts a plain original road design row where a separately verified catalog supplies those original fields; it rejects NewGRF/variant inputs. Preserve the fixed settings and seeds on saved worlds rather than resampling them.

For example only, starting in 1950 with generation seed 1751 and startup draw 97721 gives a publicly purchasable Regal on startup, a Hereford date of November 1, 1965 and a Foster date of December 1, 1987. These are not hardcoded dates.

## Verification

```sh
lua5.1 tests/stock_engine_calendar.lua
PYTHONDONTWRITEBYTECODE=1 python3 tests/stock_engine_calendar_upstream.py /path/to/OpenTTD-14.1 [lua5.1]
```

The pinned C++ differential compiles actual `StartupOneEngine`, `CalcEngineReliability`, `CalendarEnginesMonthlyLoop`, stock PRNG, and Gregorian year primitives. Public publishing is reduced to the two actual stock flag/company-mask assignments so it does not simulate unrelated GUI, GRF or private offer effects. The verification has 3,885 date cases up to the stock calendar maximum and 12,480 design cases across all three buses, climates, real partial-month activation, old/late starts, retirement and multiple independent seed pairs, plus a same-base-date sibling comparison.
