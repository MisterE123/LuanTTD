# Temperate company headquarters

Open **Company → Build or move HQ**, aim at the first corner of a 2×2 plot, and click. The four terrain pieces must finish at the same foundation height. The ledger quotes site clearance and any foundations before building. An existing HQ may overlap the new footprint, but relocating it costs 1% of company value plus the new site work. In **Company → Finances**, **View headquarters** takes you to the current building.

The [stock object command](https://github.com/OpenTTD/OpenTTD/blob/16.0-RC1/src/object_cmd.cpp#L213-L389) and [stage thresholds](https://github.com/OpenTTD/OpenTTD/blob/16.0-RC1/src/object_cmd.cpp#L168-L181) govern the structure. It grows on quarterly company performance and does not shrink in place. An HQ produces passengers and mail on the existing landscape clock; each quarter of the building contributes stock acceptance. A flat sea-level HQ can flood, clearing the whole site and detaching existing cargo packets from the lost office without deleting the cargo.

- The five original stages are a regional office, brick offices, civic campus, modern campus, and glass tower. Each has four modeled parcels, including the paved southern court; no upstream sprites or textures are included.
- Editable [Blender source](stock_company_hq.blend). Rebuild the meshes, palette and icon with `python3 tools/build_company_hq_art.py`, and the editable assembly with `blender -b --python tools/save_company_hq_blend.py`.
- [Native Luanti replay](../tests/company_hq_native.lua): mouse-driven build and overlapping relocation in a generated world, checking actual parcel meshes and both payments.
- [Compiled original comparison](../tests/company_hq_rc1_upstream.py): all score/stage combinations and every passenger/mail random-byte pair for each phase.
- [Authority/cargo test](../tests/company_hq_cargo.lua): authenticated placement, real landscape-tick production, overlapping station catchment, company quarter upgrade, correct acceptance, saved ledger and whole-building flood cleanup.
- Remaining parity work: company-color variants and broader vehicle/station accounting edge cases (especially mergers and unsupported legacy vehicles). This is not a claim that the rest of the finance economy is fully matched.
