# Original English town names

`mods/luanttd_core/openttd/stock_town_name.lua` ports the Original English spelling
function, the original six arrays (including the duplicate weighted spelling),
and the stock world-generation uniqueness loop in OpenTTD 14.1. Original
English is `game_creation.town_name = 0`, the stock setting default. This
module does not port other stock languages or NewGRF name generators.

- `display(nameparts)` maps an unsigned 32-bit value to its original English
  name. Persist the exact `nameparts` rather than taking a new random draw on
  reload. Identical names can and do arise from different encoded values.
- `generate(used, random32)` returns `nameparts, display_name` and inserts an
  accepted display name into the supplied set `used` (string keys, `true`
  values, omitted for unused). A candidate must have fewer than 32 characters
  and an unused displayed spelling. This table is entirely ASCII. The function
  consumes exactly one caller-provided random word per attempt and stops at
  the first acceptance, or returns `nil, nil` after 1,000 unsuccessful draws.
  It does not seed or advance a separate stream.
- For `GenerateTowns`, initialize the set with names of actual existing towns,
  including their custom names. The attempt reserves the name **before**
  location search, even if no town can be placed. For the final all-zero
  fallback use a fresh set seeded only from actual existing towns; historical
  failed attempts must not exclude names from that final search. It need not
  be kept after the fallback.

Porting source: `src/townname.cpp` (`VerifyTownName`, `GenerateTownName`,
`SeedChance`, `SeedChanceBias`, `ReplaceEnglishWords`,
`MakeEnglishOriginalTownName`), `src/table/townname.h`, `src/town_type.h`
and the call sites in `src/town_cmd.cpp`. OpenTTD contributors, GPL-2.0-only;
see `COPYING.OpenTTD.md`.

Run:

```sh
lua5.1 tests/stock_town_name.lua
python3 tests/stock_town_name_upstream.py /path/to/openttd-14.1/src
```

The differential builds the actual 14.1 functions and tables after verifying
the input file hashes. It compares 131,077 spelling inputs and 983 stateful
set operations (collision on identical display with distinct parts, existing
custom name, prior failed placement, fallback, and the exact last-draw and
exhaustion boundaries). The test provides the same raw RNG stream on both
sides. It proves spelling and retry semantics, not complete world generator
RNG parity, which depends on how all calling subsystems share and consume it.
