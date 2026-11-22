# Tidewater Sawmill

Original editable Blender and native mesh collection for the ordinary
OpenTTD 14.1 temperate Sawmill, industry type 2, **layout 0**. Shape and
workyard cues come from the 1950 OpenGFX 7.1 game view: rows of small
tawny gabled bays with dark grey roofs, tall stacks of amber logs,
wet logs at intake and pale finished lumber by dispatch. All modeled
geometry, materials, ring patterns, lettering and stockyard equipment
are original LuanTTD work. No OpenTTD or OpenGFX bytes were imported.

Source footprint: [OpenTTD 14.1 `src/table/build_industry.h`](https://github.com/OpenTTD/OpenTTD/blob/14.1/src/table/build_industry.h),
`_tile_table_sawmill_0`.

| Offset | Stock gfx | Native art |
| --- | ---: | --- |
| `(0,0)` | 15 | Timber foreman's shop, working door and casements |
| `(0,1)` | 15 | Oak drying store with genuine interior |
| `(0,2)` | 12 | South loading bay and stack of strapped sawn bundles |
| `(1,0)` | 14 | Roundwood pile and first half of north roller infeed |
| `(1,1)` | 12 | Two open hall bays, cast sawing machine, visible toothed blade and real rollers |
| `(1,2)` | 11 | Finishing shed and cut timber racks |
| `(2,0)` | 14 | Standalone second tall stockpile of round logs |
| `(2,1)` | 13 | Dark receiving pile, parked intake gantry and flush east raw-log frontage |

There is no mesh on the stock hole `(2,2)`. Native renderer names are
`bl_sawmill_0_{x}_{z}.obj`, atlas `bl_sawmill_atlas.png`. Each tile's
anchor is the even native position `(2*x, base+1, 2*z)`, where `x,z`
are the **world** board tile coordinate. The ground datum is
`base+.5`; leave the normal terrain beneath the art. Use the local
footprint offsets as asset suffixes, not world coordinates. Rollers
share exact edges from (1,0) through (1,1) and from (1,1) to (1,2).

Stock gfx 13 identifies the wood intake; the eastern frontage leaves
an open grade-level apron. The southern finished-lumber edge similarly
keeps a low apron for adjacent road/stop access. Native industry,
ordering, stock processing, station catchment, construction states,
rolling gear and machinery animation are separate from the art.

## Regeneration and evidence

```sh
SAWMILL_ART_RENDER=/tmp/tidewater.png blender -b -t 4 --python-exit-code 1 --python tools/build_sawmill_art.py
python tests/sawmill_art.py --upstream-layout /tmp/bayline-ott-src/build_industry.h
BAYLINE_NATIVE_TOOLS=/tmp/bayline-run BAYLINE_NATIVE_TCP=1 bash tests/sawmill_art_native.sh
```

The structural regression compares the eight emitted files to pinned
stock offsets, exact split roller profiles, frame clearance and true
working-hall sightlines. Native graphical QA shows the entire layout,
the working interior, the log intake and the dispatched timber frontage
with an original Balogh Goods Truck on ordinary two-lane road.
