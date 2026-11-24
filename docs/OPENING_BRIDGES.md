# The opening-era bridge roster

An ordinary January 1950 Temperate campaign now offers every stock bridge
style that OpenTTD 16.0-RC1 makes available, for both roads and
conventional rail. This is a roster milestone, not full infrastructure
parity. The normal Bridge tool still filters by date, geometry, compatible
surface and length, and quotes a price before construction.

| Stock ID | Style | First year | Interior tiles | Stock speed | Price multiplier |
| --- | --- | ---: | ---: | ---: | ---: |
| 1 | Concrete | 0 | 0–2 | 48 | 112 |
| 2 | Steel girder | 1930 | 0–5 | 64 | 144 |
| 6 | Steel cantilever | 1930 | 3–7 | 160 | 224 |
| 7 | Steel cantilever (brown) | 1930 | 3–8 | 208 | 232 |
| 8 | Steel cantilever (red) | 1930 | 3–9 | 240 | 248 |

The cantilever deck follows the release's pillar table: piece 0 has
no bearings, while pieces 1–5 use the canonical northeast/northwest
side. Dragging the endpoints in reverse doesn't move the bearings.
Road and rail have separate running surfaces but each shares its
geometry and UVs across the three finishes. The two short railway
styles retain the already shipped architectural families, widened
around a correctly gauged track bed, with guard rails, a drainage
trough and their own concrete/steel pier profiles.

[Cantilever](../art/steel_cantilever.blend), [short concrete rail](../art/rail_bridge_concrete.blend)
and [short girder rail](../art/rail_bridge_girder.blend) contain original
editable geometry and materials. No OpenTTD game sprites or meshes are
bundled. Generators are `tools/build_steel_cantilever_art.py` and
`tools/build_short_rail_bridge_art.py`.

The two art tests cover 484 native seams and verify underground
footings, pier footprints, palette/mesh reuse and road-clear variants.
Native replays use the worker's ordinary bridge picker and depot tools
to build a timber crossing, replace it with the specified type while
occupied, reopen the world, and finish a paying service. They verify
all three cantilever finishes for road and rail, and both new short
conventional railway styles. Native client replays check model
registration and render both banks, roadway, rails and under-deck
supports. These checks supplement, not replace, the compiled RC1
tests of date/length offers and piece/pillar masks.

Later tubular styles and additional rail/road technologies are
tracked separately in [the stock timeline](TIMELINE_PORT.md).
