# Temperate company land

OpenTTD 16.0-RC1's [company-owned land specification](https://github.com/OpenTTD/OpenTTD/blob/16.0-RC1/src/table/object_land.h#L120-L125) uses a single stake on a bare 1×1 plot. LuanTTD's original timber post and enamel marker use an independently authored shape, palette, soil texture, and hotbar icon. Flat ground and all shared-corner slopes use the same stake at the appropriate ground lift, without adding a retaining wall or a flattened foundation.

- Editable palette-packed Blender file: [stock_owned_land.blend](stock_owned_land.blend).
- Rebuild the mesh, texture and icon with `python3 tools/build_owned_land_art.py`. Reassemble the editable palette gallery with `blender -b --python tools/save_owned_land_blend.py`.
- In an ordinary generated company use **Landscaping → Buy land**. A click purchases one plot; drag for an area (Aux1 for a diagonal area). Bulldoze a company stake to sell it. Another company cannot sell it or build plain road or rail over it.
- The pinned source comparison compiles purchase and resale prices. The hosted unit test checks purchase, ownership, quotes, slopes, replacement and save state. Native Linux Luanti clicks both buttons, verifies the actual stake is painted then removed, and sees the company balance move from $100,000 to $99,580 then $99,660.
- Not full object parity: buying over complex buildings/scenery and every automatic removal case is not yet mounted. Land purchases currently use the bounded terrain-tool selection, and the marker is a fixed blue palette, not per-company colors.
