# Oil freight on Monorail and Maglev

The stock Monorail Oil Tanker (#60) carries 35 kL, and the Maglev
Oil Tanker (#92) carries 37 kL. Both are bought at a depot of the
matching type, as a separate wagon or in the depot's locomotive
and tanker starter offer. They cannot mix gauges.

1. Build a line between an oil well and an oil refinery. Give both
   ends enough platform length for the locomotive and tanker.
2. In the Rail Freight tools, designate the station near wells as an
   **Oil wells loading stage** and the refinery station as an **Oil
   refinery unloading stage**.
3. Buy the matching Oil Tanker and locomotive. Select the well
   station first and refinery second, then start the service.

The wagon carries the RC1 stock quantity, changes actual consist mass,
and participates in the existing oil source, station rating, unloading
and cargo-payment logic. It does not create oil or independent industry
production. Only one guideway tanker can use the current rail Oil
service in a world; later freight types and mixed cargo are not
claimed. Conventional rail tankers still work normally.

## Art and verification

`art/rail_mono_oil_tanker.blend` and
`art/rail_maglev_oil_tanker.blend` are separate original editable
models with closed vessels, raised hatch covers, end ladders, drain
manifolds, and native gauge-specific running gear. They preserve an
exact-fit articulated body and a complete fallback mesh for bridges
and tunnels where the separate presentation samples are unavailable.

The native worker smoke test purchases both gauge variants through
the ordinary depot, uses actual well and refinery catchments, saves
after 5 kL, and restarts for one full, correctly paid refinery
delivery. The canonical OpenTTD 16.0-RC1 `engines.h` reference
identifies both wagons and their capacities.
