# Timber railway bridge overhead line

Original 3D contact copper, messenger, dropper cables and bridge-mounted
steel consoles complement the original [wooden rail decks](rail_spans.md).
Each mast sits on a bolted exterior saddle at the real cross-bearer
end. The load path is through the transverse timber, not an invented
foundation on the river below. The external column clears the original
inspection fence and upright hardware by at least .05 native units.
The cantilever keeps the running way and inspection deck visually open.

[OpenTTD 14.1's bridge wire routine](https://github.com/OpenTTD/OpenTTD/blob/14.1/src/elrail.cpp#L502)
is the reference for continuous bridge-length wiring and alternate mast
cadence. Native masts sit over a structural cross-bearer instead of a
sprite's exact tile boundary; there are end-head masts and a final
middle mast at the far end. This is artwork, not PPP choice, power,
train movement, or clearance logic. No upstream images or meshes used.

## Integrator contract

```lua
local Art = dofile(mod.."/rail_bridge_catenary_art.lua")
local head = Art.overlay(is_flat and "head_flat" or "head_ramp", inside_dir)
local mid = Art.overlay("span", axis, middle_ordinal, count_middle)
-- Only after authoritatively determining that the existing timber bridge
-- is electrified. Both calls return node name, mesh, texture, offset,
-- pole and rigid_contact_qualified, or nil if the request doesn't fit.
```

- All wire pieces mount at **(2*x, deck+1, 2*z)**, immediately above
  the unchanged timber deck node at deck. Never mount them as piers;
  preserve the water/ground nodes below the bridge.
- Interior axis 0 = X, 1 = Z. Count middle positions from the minimum
  coordinate along that axis starting at one. Every odd and final
  middle tile has a mast. Two directly joined heads need no middle.
- Head directions 0=-X, 1=+Z, 2=+X, 3=-Z point into the bridge.
  Same native field as the structural asset, **not** travel direction.
- OBJ basenames: `bl_rail_bridge_catenary_span_<axis>_<0|1>`,
  `bl_rail_bridge_catenary_head_flat_<dir>`,
  `bl_rail_bridge_catenary_head_ramp_<dir>`. All use the existing
  `bl_rail_catenary_atlas.png`; no new textures or dependent stock art.
- Flat contact wire underside is **deck+1.398**; running rail is
  **deck+.614**. The ramp head reaches the same inside edge but the
  outside edge is **deck+.398**, joining exactly one level lower
  ordinary catenary. Messenger has the same exact seam profile.
  `Art.wire_edge(kind, direction_or_axis, edge, deck)` queries that
  edge, not slope or rail compatibility.
- coastal rail test fixture seed 1751, **(21,15)–(27,15)**, is stock Wooden type 0,
  deck 2 with five middle tiles and **two real 1-in-2 ramp heads**.
  Look for an outer wire underside of 2.398 and flat deck contact of
  3.398. The regular SH '30'/'40' rigid shoe touches flat wire only.
  A rigid raised pantograph pitched 1-in-2 extends .09254 world units
  too far on the incline. The ramp wire geometry is qualified, but
  moving ramp collector contact remains unqualified. Do not infer a
  fully qualified bridge route from a flat-pole or static vehicle view.

## Rebuild and tests

- Editable `art/rail_bridge_catenary.blend`, twelve separately named
  collections. `blender -b -t 2 --python-exit-code 1 --python tools/build_rail_bridge_wire_art.py`.
- `python3 tests/rail_bridge_catenary_art.py`: exact contact and
  messenger edge profiles in both axes/all heads and alternate deck
  elevations, real load-bearing bracket overlap, structure clearance,
  and tested flat SH '30'/'40' contact against exported model geometry.
- `lua5.1 tests/rail_bridge_catenary_selector.lua`: quotes the real
  generated coastal rail test fixture bridge and cross-checks the absolute height
  values and native selector. This does not dispatch rolling stock.
- `tests/rail_bridge_catenary_native.sh`: compact Linux visual fixture,
  recreating the exact source-checked coastal rail test fixture bridge span and
  both head grades, plus a separate orthogonal span with both types
  of heads. Luanti frames include both axes, sightline from water,
  physical clamped support and stationary shoe contact on the deck.
