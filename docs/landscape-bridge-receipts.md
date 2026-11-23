# Typed authority receipts for native timber road bridges

Detached proof for building and removing **one ordinary native timber
road bridge**, with no changes to the live scheduler, hotbar, native
renderer, or saves. Receipts identify which original ground records
changed and which protected overhead locations changed. A renderer dirty
tile has neither of those meanings on its own.

## Native command paths

- Build calls the real `Sim.road_bridge` quote branch (style **0**, wood),
  then the same real command to write. Normal OpenTTD 14.1 geometry,
  ramp height, and price go through the existing source-shaped bridge
  planner. Both ends must be clear dry ground in this limited wrapper.
  Ordinary owned roads or other reviewed land/water underlays do not
  become part of the bridge and remain untouched.
- Removal now has an optional **third command argument** after company
  and head: `Sim.remove_wood_bridge(state, company, head, true)` (fourth
  Lua parameter). It returns `true, price, projected_span` only *after* the
  native ownership, affordability and active `v.route` guards. The fee
  includes the structure and both road bits on each tile, including both
  ramps, as in RC1. The projected span cannot rewrite the registry. The
  host's route guard is still more conservative than OpenTTD's
  vehicle-presence test.
- The narrow wrapper refuses overlapping overhead or protected lower
  layers (including any pre-existing `bridge_above` entry on a ramp or
  interior); otherwise the host could need more than one record per
  physical tile. Replacements, electric/rail spans, aqueduct and tunnel
  commands, public-road underlays, facilities, and unknown tile data
  or side providers are out of scope. Pass a pure `side_guard()` to
  veto unreviewed state/ephemeral actors in a foreign host; this proof
  cannot discover arbitrary private tables by name.

```lua
local receipts = Factory(Sim, Authority)
local R = receipts.bind(state, world_name, existing_company, owner)
local forecast, reason, mode = R.quote("build", first_head, last_head)
local ok, receipt, mode = R.run("build", first_head, last_head)
-- R.quote("remove", either_head); R.run("remove", either_head)
```

The forecast uses the actual native plan checked against the physical
straight span, bounded to the stock maximum 64 middle cells plus two
heads. It stages **`tile`** entries for two head records and **`layer`**
entries for middle indices with explicit `layer="bridge_above"`. The
footprint is converted to stock indices by the authority; this adapter's
native IDs and messages remain physical and one-based.

Once the owner reserves its affected cells, the writer takes a bounded
snapshot of the involved head/middle tile and overhead records. Its
attestation is derived independently from actual native dirty IDs and
before/after records: exactly one write class per physical ID; three
expected head fields (build/owner/bridge ID) or precisely the assigned
or cleared bridge key on the underlay; actual finance delta, deck,
topology revision, unchanged corner revision and checked registry.
Comparing the expected typed effect set to this receipt prevents
treating a pure overhead update as ground demolition. Bounds and active
membership are inherited from the authority; no full map scan or
copy occurs in the adapter. The test's exhaustive reference scan is QA,
not production.

Preflight denials (ownership, overlap, funds or route use) leave native
state untouched. An authority pre-write `dense` decision is only valid
at a tick boundary after discarding the sparse owner. After any attempted
write, an incomplete or unexpected receipt **aborts and poisons** that
owner. No post-write rollback or mid-tick dense replay is supported.
This also cannot detect a dishonest mutator's writes outside the
native command's proven bounded return contract.

## Verified host geometry

The controlled 128×128 fixture has timber bridgeheads at physical
**542 and 1054** (stock IDs 541/1053). The **`bridge_above`** map gets
exactly **670, 798 and 926** (stock 669/797/925). An unchanged foreign
ordinary road remains underneath 670. Build costs **$1,551**; native
removal is **$0**, with both endpoints and all three overhead records
recovered.

The existing coastal candidate at 797 cannot flood native tile 798
while protected. Sparse and dense source walks agree at tick **255**:
798 stays dry despite the valid old sea. Removing the bridge at that
boundary re-admits the source; at tick **256**, source slots **1** and
**40** flood native IDs **798** and **799** successively. The final
stored world and landscape cursor match the dense reference, including
the existing arbitrary render dirties. Scope includes ownership,
budget, protected-layer overlap, active road-route denial, and rejection
of the deliberately truncated receipt from a genuinely executed writer.

```sh
lua5.1 tests/landscape_bridge_receipts.lua
lua5.1 tests/road_bridge.lua
lua5.1 tests/road_bridge_service.lua
python3 tests/road_bridge_upstream.py /path/to/pinned/openttd-14.1 lua5.1
```

The existing paid-bus service still traverses all of an actual timber
span and refuses in-use removal. The pinned C++ differential covers
25,553 geometry, pricing, and catalog cases; the receipt/tide test is
a Lua native-host differential, not a stock C++ demolition oracle or
visual/SQLite qualification.
