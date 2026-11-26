# Alternate Temperate coal, power and sawmill layouts

Ordinary 1950 worlds can now generate all four stock Coal Mine layouts, all three Power Station layouts, and both Sawmill layouts. The same media-backed geometry is available when the normal industry scheduler opens another facility during play. The source candidate ordering, type, relative coordinates, tile graphics ID, and occupied parts are taken from OpenTTD 16.0-RC1, not sampled from the appearance of the previous native layouts.

Some layouts do not occupy their northwest origin. Coal Mine layout 3 and Power Station layout 1 retain that hole, including unrelated terrain and access. The authoritative industry keeps the original origin; its native name marker anchors to the closest actually occupied tile. Cargo loading and delivery use the actual occupied industry cells.

The [Blender scene](../art/stock_industry_layout_parts.blend) includes original hoists, exhaust stacks, electrical yards, gates, log and lumber bundles, workers' cabins, and screened coal. The [builder](../tools/build_stock_industry_layout_parts.py) compiles each self-contained graphics role and separates the animated hoist wheels. Exhaust comes from the real boiler stacks. Farm, oil, iron, steel and other industry art are unchanged in this tranche.

Evidence:

- [Pinned catalog comparison](../tests/industry_layout_catalog_rc1.py) checks all 23 definitions in the shared ten-type Temperate catalogue against the exact RC1 header, not just footprint counts.
- [Placement regression](../tests/industry_alternate_layouts.lua) covers all six newly mounted variants, named site anchoring, no writes to footprint holes, genuine media, worker projection, and save round-trip.
- [Native Linux run](../tests/industry_alternate_native.sh) opens a normally generated worker world, finds all six variants, and checks the actual placed mesh on every occupied tile and the empty holes. The synchronous rendering assertion is on the server, and native client screenshots are captured separately.

This is not full industry parity. The later [Temperate footprint pass](stock-temperate-industry-layouts.md) covers the remaining variations. Some site-leveling and full funding mechanics are separate.


### Stock running machinery

OpenTTD 16.0-RC1 `TileLoop_Industry` selects mine towers, power yard
arcs and oil well motion after the tile's construction visit. The
worker preserves those rolls and the source absolute tick. Once live,
the mine and power visual pass runs before the increment, matching
`AnimateAnimatedTiles`. Coal hoist rotation follows the direction and
stopped windows; power particles originate at the authored transformer
bushings. Dynamic animation frames travel with the visible motion
packets and do not change the static model/collision receipt. The
original oil well model is still static visually, though the startup
state feeds its existing saved live animation registry.

`tests/industry_machinery_rc1.py` compiles the pinned source branches and
compares 18,240 animation phase, frame and RNG cases. In addition,
`tests/industry_machinery_world.lua` checks startup construction, handoff
to the live owner, registration, static scene separation and view scope.
