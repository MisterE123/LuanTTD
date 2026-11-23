# North Reach offshore oil rig (#5)

Original editable Blender geometry and six atlas-mapped meshes built for the stock Temperate Oil Rig footprint. The pinned OpenTTD 16.0-RC1 tables supply industry and airport data, not artwork. Each of the six occupied tiles gets its own mesh. A short flight-deck cantilever above the water adds no logical space or ownership; the 52 flat-water tests add no geometry or ownership. The stock berth tile remains in place even though the helicopter descends and parks partly over the neighbouring industry tile.

- Submerged jacket, renewable splash collars, transfer fenders and a parted crew-landing rail.
- Open derrick with a suspended travelling block and through-visible steel bracing.
- Raised helideck, pressure-control drums, shaft passage, flare and service crane. Only the helideck is allowed under the rotary flight path.
- The deck surface is 54 source vertical pixels (6.75 Luanti units) above flat water. Its exact travel points use source `(23, 9)`, `(28, 9)` and `(31, 9)`, with a checked 0.78-unit collision envelope above the swept deck. Rendering and physics models for new helicopters must pass this envelope before use.

Rebuild: `blender -b -t 4 --python-exit-code 1 --python tools/build_stock_oil_rig_art.py`. Optional `STOCK_OIL_RIG_RENDER=/path/to/survey.png` produces an art review image. `python3 tests/stock_oil_rig_art.py` checks source roles, local extents, indices, material atlas and deck clearance. `bash tests/stock_oil_rig_art_native.sh` loads the exported assets in an isolated Linux Luanti fixture for survey, water-level and heliport views. The fixture does not prove a commercial Oil Rig service.
