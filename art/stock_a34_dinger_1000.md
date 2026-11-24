# AirTaxi A34-1000 and Dinger 1000

Exact original data: OpenTTD 16.0-RC1 `src/table/engines.h`;
MA #239 / AVI #24 and MA #247 / AVI #32. The original seeded calendar
controls public availability, not a forced year in the depot.

| Aircraft | Stock ID | Passengers | Mail | Airport class |
| --- | ---: | ---: | ---: | --- |
| AirTaxi A34-1000 | 239 | 75 | 10 | Country or City |
| Dinger 1000 | 247 | 130 | 45 | City |

The A34 is an original short-field twinjet with a compact fuselage,
curved tips and two true inlet recesses. The Dinger is a slender
original supersonic transport with no horizontal tailplane, a broad
delta wing and four underwing engine pods. Both have separate taxi and
gear-up meshes with the same equipment, cabin and exterior. These are
native render models; authentic stock aircraft speed, cost, runway
admission and economy remain in the shared engine.

The Dinger's native mesh is scaled to the largest sampled safe fit
(88% of its original Blender design) so its nose/wings clear the
stock City Airport layout. The clearance test uses the **exported**
geometries against every authored terminal tile, checking over 2,300
ground and eased turn poses, rather than relying on a hand-drawn box.

Editable sources: `stock_airtaxi_a34_1000.blend` and
`stock_dinger_1000.blend`. Exporter:
`tools/build_stock_a34_dinger_1000_art.py`. No stock sprite or
third-party texture/geometry is embedded.
