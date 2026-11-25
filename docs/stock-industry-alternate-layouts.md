# Alternate Temperate coal, power and sawmill layouts

Ordinary 1950 worlds can now generate all four stock Coal Mine layouts, all three Power Station layouts, and both Sawmill layouts. The same media-backed geometry is available when the normal industry scheduler opens another facility during play. The source candidate ordering, type, relative coordinates, tile graphics ID, and occupied parts are taken from OpenTTD 16.0-RC1, not sampled from the appearance of the previous native layouts.

Some layouts do not occupy their northwest origin. Coal Mine layout 3 and Power Station layout 1 retain that hole, including unrelated terrain and access. The authoritative industry keeps the original origin; its native name marker anchors to the closest actually occupied tile. Cargo loading and delivery use the actual occupied industry cells.

The [Blender scene](../art/stock_industry_layout_parts.blend) includes original hoists, exhaust stacks, electrical yards, gates, log and lumber bundles, workers' cabins, and screened coal. The [builder](../tools/build_stock_industry_layout_parts.py) compiles each self-contained graphics role and separates the animated hoist wheels. Exhaust comes from the real boiler stacks. Farm, oil, iron, steel and other industry art are unchanged in this tranche.

Evidence:

- [Pinned catalog comparison](../tests/industry_layout_catalog_rc1.py) checks all 23 definitions in the shared ten-type Temperate catalogue against the exact RC1 header, not just footprint counts.
- [Placement regression](../tests/industry_alternate_layouts.lua) covers all six newly mounted variants, named site anchoring, no writes to footprint holes, genuine media, worker projection, and save round-trip.
- [Native Linux run](../tests/industry_alternate_native.sh) opens a normally generated worker world, finds all six variants, and checks the actual placed mesh on every occupied tile and the empty holes. The synchronous rendering assertion is on the server, and native client screenshots are captured separately.

This is not full industry parity. Alternative Factory, Farm, Oil Wells and Oil Refinery art and placement remain outside this tranche, as do some site-leveling and full funding mechanics.
