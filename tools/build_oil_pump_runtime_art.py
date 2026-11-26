#!/usr/bin/env python3
"""Export the original oil-well pad and 12 independent pump poses.

Run with Blender's Python. Use a separate output directory while testing:
OIL_RUNTIME_ART_OUT=/tmp/oil-motion blender -b -t 2 --python-exit-code 1 \
    --python tools/build_oil_pump_runtime_art.py
"""
from math import tau
import os
from pathlib import Path
import sys

sys.path.insert(0,str(Path(__file__).resolve().parent))
import build_stock_oil_well_art as Oil

A,R,S=Oil.A,Oil.R,Oil.S
target=Path(os.environ["OIL_RUNTIME_ART_OUT"])
target.mkdir(parents=True,exist_ok=True)

def dump(obj,name,origin=.5,entity=False):
    p=target/(name+".obj")
    R.export_obj(p,obj,origin,"build_oil_pump_runtime_art.py")
    if entity:
        # Luanti groups entity material buffers together to bind a
        # single authored atlas. Retain part comments for provenance.
        raw=p.read_text().splitlines()
        p.write_text("\n".join([raw[0],"g OilPump",*(("# "+l) if l.startswith("o ") else l for l in raw[1:])])+"\n")

# The alternate layout already reuses the five default visual roles.
# Match all five foundations and their labels exactly, not a generic box.
root=Oil.LAYOUTS[0]
static=A.mesh()
Oil.pads(static)
Oil.frames(static)
for x,z in root:
    dump(S.clip(static,x,z,root),f"bl_industry_oil_well_base_{x}_{z}")

# These are all exported from the same original four-bar relationship
# as the editable scene: horsehead, bridle rods, links and crank. No old
# complete pump model is emitted or overlaid by this exporter.
for phase in range(Oil.FRAME_COUNT):
    source=A.mesh()
    Oil.motion(source,0,0,0,.78+tau*phase/Oil.FRAME_COUNT)
    native=A.mesh()
    for part,items in source.parts.items():
        for inds,color in items:
            native.face(part,color,[(10*x-.5,10*z-.5,10*(h-.5)) for x,z,h in
                                   (source.vertices[part][i] for i in inds)])
    dump(native,f"bl_industry_oil_well_pose_{phase:02}",0,True)
