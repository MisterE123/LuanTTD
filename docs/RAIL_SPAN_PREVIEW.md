# Native rail spans preview

Rail Construction includes the rail bridge and tunnel tools.
The rail span configuration persists after the first opt-in. The construction
adapter supports timber rail bridges and ordinary straight rail tunnels.
It does not silently replace existing rails, make a grade mesh that is not
present, excavate a tunnel exit, or stack unsupported portal layers. Stock
quote limits/prices still apply. [RAIL_SPAN_PORT.md](RAIL_SPAN_PORT.md)
describes the wider pure planning API, including stock exit excavation.

The live dispatch pilot is **one-way and exclusive**: one MJS 250 and one
empty carriage travel from an owned depot to a real owned platform along a
unique route containing at least one span. It does not mix with the
two-train crossing pilot, the shuttle, or paid rail. Both span portals are
reserved before entry. The last wagon leaving the far portal releases both
parts of the reservation. A train in a tunnel uses real hidden stock
movement; it is not teleported. A bridge uses the stock physical ramp and
deck heights, and a wooden bridge's speed restriction also applies while
a wagon is in the visible bridge. The normal rail controller continues to
handle fixed-point original acceleration, track choices and station stops.

## Native integration

```lua
local W = api.rail_spans -- nil unless enabled
local quote = W.quote_bridge(S, owner, from, to) -- timber only
local quote_tunnel = W.quote_tunnel(S, owner, entrance)
local ok, note, dirty, deck = W.commit(S, owner, quote)
if ok then
  if deck then api.render.raise_bound(deck) end
  api.render.update(dirty)
  api.save()
end
local started, note = W.start(S, owner, depot, station_id)
```

`W.clear(S,owner,portal)` removes the complete owned span after the pilot
has been cleared, retains the terrain, and returns the analogous dirty set.
Other terrain/placement tools must protect all span portal, bridge-above and
tunnel-below indices. Tool guards are mounted separately from the geometry.

## Reproduction and verification

At z=10, set corner heights to 4 except x=7–8 at level 3 and x=14–18 at
level 5. Build an eastbound X-track depot at x=2, X track at x=3–4, a timber
bridge from x=5 to x=9 (deck level 5), X track x=10–12, a tunnel aimed into
the hill at x=13 (first valid exit x=18, bore level 4), X track x=19–21 and
an X platform x=22–24. The pilot should arrive without a reversal.

- `lua5.1 tests/rail_span_run.lua`: arithmetic/ownership, physical bridge
  frames at height 32–40, stock tunnel visibility frames, both paired
  portal claims held until the rear wagon, and reloads mid-bridge and
  underground. Also exercises refusal of stale/overwriting rail edits.
- `BAYLINE_NATIVE_TOOLS=/path/to/portable-tools tests/rail_span_live_native.sh`:
  isolated Linux Luanti world loading the actual game, registered mesh
  node IDs at the ramp, deck, pier and portals, and a completed mounted
  two-part run. Graphical mesh audit is a separate rail art fixture.
