# Stock Temperate Bank

This original two-cell native model uses [OpenTTD 16.0-RC1's Temperate Bank layout](https://github.com/OpenTTD/OpenTTD/blob/07b339c0aaeb0a87be9490b2f1c3f17c6b00b837/src/table/build_industry.h#L489-L496), industry type **12**. Offset **(0,0)** is GFX **58**, and **(1,0)** is GFX **59**. There are no other Temperate Bank layouts. This is not type 16, the Sub-Arctic/Sub-Tropical Bank that uses GFX 89/90. It includes no stock sprite pixels.

The two pieces make one urban limestone bank. The public banking hall has carved arches, a raised bronze crest, a Classical portico, separate bronze doors, and a front staircase. The vault annex has a ribbed copper clerestory and a physically open paved receiving approach before its recessed shutter, with curb details, clearance markings and bollards. This is original presentation geometry, not a new station or a routable road.

`stock_temperate_bank.blend` is the editable whole building. Runtime clips both parts at their shared edge and places them over the logical 2×2-native-node grid. Mount the two `bl_industry_temperate_bank_<dx>_<dz>.obj` pieces using `bl_industry_temperate_bank_atlas.png` and the standard NW overlay at native grade + 1, after validating a shared level foundation.

## Stock placement and cargo notes for gameplay integration

- [The industry spec](https://github.com/OpenTTD/OpenTTD/blob/07b339c0aaeb0a87be9490b2f1c3f17c6b00b837/src/table/build_industry.h#L1256-L1264) uses `Town1200More`. The town authority must have at least **1,200** inhabitants. Both footprint cells must already be Houses; rejecting one non-house tile must leave the old properties intact. The stock land checks test LandscapeClear as `OWNER_TOWN` for protected buildings without charging a company or changing reputation. A host should maintain coherent town growth records and avoid counting a multipart-house removal twice.
- [The two tile specs](https://github.com/OpenTTD/OpenTTD/blob/07b339c0aaeb0a87be9490b2f1c3f17c6b00b837/src/table/build_industry.h#L1591-L1593) each accept 1/8 Passenger and 8/8 Valuables. Their per-tile refused slope masks are `SLOPE_E` and `SLOPE_S` respectively; the source applies these to complementary slopes. The mesh is flat and cannot itself supply the slope checks or terrain leveling.
- The Temperate industry consumes and produces Valuables. The distinct cold and tropical banks are not shipped as part of this model. This artwork does not implement the cargo, bank generation or armored truck service.

## Build and verify

```sh
blender -b -t 2 --python-exit-code 1 --python tools/build_stock_temperate_bank_art.py
python3 tests/stock_temperate_bank_art.py
blender -b -t 2 --python-exit-code 1 --python tests/stock_temperate_bank_art.py
```

The normal test checks the asset IDs, anchor, atlas, native triangle references, the crossing plinth and coping, and the receiving clearance. The Blender run also compares the sum of exported piece areas with the saved editable whole building. For source verification, append `--upstream-layout /path/to/build_industry.h` to the Python command.
