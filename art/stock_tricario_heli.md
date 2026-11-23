# Tricario Helicopter (#253)

Original short offshore shuttle with rounded pressure hull, wraparound windshield, independent recessed cabin glazing, fixed wheel contacts and a built-from-scratch paint scheme. The 16.0-RC1 vehicle table supplies the stock stats, not art or textures. The three native meshes have a shared palette; the airframe has a real underbelly and wheels, the cambered main rotor and the smaller tail rotor turn on independent physical axes.

- Body nose is native −Z, wheel contact Y=0; scale 1 in a native mesh entity.
- Attachment pivots in native units are main (0, .407, −.016), tail (−.037, .256, .605); pass 10× offsets to the ObjectRef attachment API. Main rotor turns about native Y, tail rotor about native X.
- The wheel contact sweep and room for rotor overhang are validated against the original rig geometry across all eight headings, without changing the stock approach poses. Visual cantilever only extends outboards above navigable water, not the seabed or assigned industry area.
- Rebuild with `blender -b -t 4 --python-exit-code 1 --python tools/build_stock_tricario_art.py`. Set `TRICARIO_RENDER` for an inspection image.
- `python3 tests/stock_tricario_art.py /path/to/OpenTTD/src/table/engines.h lua5.1` checks stock #253, three actual ground wheels, rotor dimensions and 432 native contact probes. Private preview art only until its commercial operations pass the end-to-end worker gate.
