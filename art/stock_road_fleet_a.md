# Stock road fleet artwork: MkII, Uhl, Thomas and Foster

Four original editable Blender vehicles and their native Luanti exports. No stock sprites, logos, models, or reference images are shipped. Stock references were used for silhouette and period details. The exporters use a separate reconstructed geometry helper and the existing rail-mesh utilities.

| Vehicle | Blender and model stem | Native scale | Native W × H × L | Stock visual state |
| --- | --- | ---: | --- | --- |
| Foster MkII Superbus #119 | `stock_foster_mk2_bus` | .40 | .24840 × .29906 × .66640 | One exterior, image 34 (3476) with zero loaded adder |
| Uhl Livestock Van #136 | `stock_uhl_livestock_van` | .42 | .25998 × .29064 × .68441 | One exterior, image 21 (3124) with zero loaded adder |
| Thomas Grain Truck #142 | `stock_thomas_grain_truck` | .42 | .25956 × .28770 × .68782 | Image 23 (3148) +48 sprite offset at ≥12 stock units |
| Foster Wood Truck #145 | `stock_foster_wood_truck` | .42 | .25746 × .28807 × .68061 | Image 24 (3156) +48 sprite offset at ≥11 stock units |

All face **−Z** with actual four-wheel tread contact **Y=0**. Each filename is `bl_<stem>.obj` and `bl_<stem>_atlas.png`; only the timber and grain meshes have a `_loaded.obj`. The loaded mesh begins with the byte-identical base OBJ and adds only its separate modeled payload. The two visual states per vehicle have identical overall envelopes. OpenGFX used recolorable sprites; the 3D swatch atlases are fixed original liveries.

- **MkII**: single-deck crowned blue/aqua roof, curved laminated screens, a pair of low-floor plug-door sets and molded wheel and entrance relief. Two axles as in the stock silhouette; no speculative second deck.
- **Uhl**: blue-slate cab, cambered charcoal roof and physically open ventilation paths between 24 separately pitched side slats. Twin vented loader doors and a partitioned floor remain the same for all livestock loads.
- **Thomas**: cobalt pressure-stamped cab, open gray tapered hopper with tip ram and discharge hardware, and a separate closed grain mound with 482 distinct 3D kernels.
- **Foster Wood**: deep-blue cab with distinct swept glazing, six logging stakes, oak cradle and ratchets. Two secured groups of 12 tapered roundwood logs with independent endgrain and seed-defined splits.

## Pin and visual references

Source: [OpenTTD 16.0-RC1 stock engine tables](https://github.com/OpenTTD/OpenTTD/blob/16.0-RC1/src/table/engines.h) and [road sprite selection](https://github.com/OpenTTD/OpenTTD/blob/16.0-RC1/src/roadveh_cmd.cpp). Model data and in-service operations are implemented separately from these visual assets.

| Engine | Road row | Base introduction | Buy/running factors | Raw speed | Capacity | Weight/power fields | Climate |
| --- | ---: | --- | --- | ---: | --- | --- | --- |
| #119 | 3 | 2008-01-01 | 160 / 240 | 255 | 40 passengers | 100 / 25 | Temperate, Arctic, Subtropical |
| #136 | 20 | 1980-01-01 | 130 / 168 | 176 | 16 livestock | 48 / 22 | Temperate, Arctic |
| #142 | 26 | 1978-01-01 | 133 / 168 | 176 | 25 grain/wheat/maize | 48 / 22 | Temperate, Arctic, Subtropical |
| #145 | 29 | 1974-01-01 | 137 / 168 | 176 | 22 wood | 48 / 22 | Temperate, Arctic, Subtropical |

Visual-only references: [OpenGFX 7.1 roadvehicle heading sheet](https://github.com/OpenTTD/OpenGFX/blob/7.1/sprites/png/roadvehicles/vehiclesroad01.png) and [flatbeds heading sheet](https://github.com/OpenTTD/OpenGFX/blob/7.1/sprites/png/roadvehicles/flatbeds.png). OpenGFX sprites were neither scaled nor converted into asset maps.

## Rebuild and verify

From an integrated checkout, without needing a display:

```sh
for producer in foster_mkii foster_wood thomas_grain uhl_livestock; do
  blender -b -t 2 --python-exit-code 1 --python "tools/build_stock_${producer}_art.py"
done
python3 tests/recovered_road_stock_art.py --road-fixtures .
```

Set `LUANTTD_HELPERS` to the production tools directory if rebuilding from
an isolated stage. Optional original inspection renders can be made by
setting respectively `SUPERBUS_QA`, `FOSTER_WOOD_QA`, `THOMAS_GRAIN_QA`, or
`UHL_LIVESTOCK_QA` to an output directory. The studio is for Blender
inspection only and does not affect the mesh exports.

Restoration verified all eight previously recorded production hashes for
#136, #142, and #145; the MkII is rebuilt from its captured final geometry
with the original bounds, 3,054 earlier asphalt misses now fitting, and
all independently rerun checks. The batch passed 12,784 production stock
road poses per exported mesh with zero tire-contact misses, 17,424
crossing-fixture cases in aggregate, and exact real-versus-blocked vent
rays across all eight Uhl side bays. This is art clearance, not a native
gameplay dispatch playtest.
