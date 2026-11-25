#!/usr/bin/env python3
"""Original ELRL crossing mesh; heights match the adjacent rail collectors.

The corner support leaves the perpendicular lane and the separate lower
tram contact network clear. The Lua adapter mounts it a node east of the
crossing so the independent native tram mesh can still occupy the center.
"""
from pathlib import Path
import sys

sys.path.insert(0,str(Path(__file__).resolve().parent))
import build_rail_catenary_art as wire

R=wire.R
review=[]
for bits in (1,2):
    for support in (0,1):
        name=f"bl_electric_crossing_wire_{bits}_{support}"
        path=R.TrackPath(wire.FLAT.index(bits))
        m=R.Mesh(R.terrain_height(0))
        wire.wire(m,path)
        if support:
            wire.mast(m,path,.90)
        review.append((name,m))
        f=R.MODELS/(name+".obj")
        R.export_obj(f,m,vertical_origin=1.5,generator=Path(__file__).name)
        lines=f.read_text().splitlines()
        # Exporter's X sign is reversed compared with the native scene.
        # A node east of tile anchor therefore needs +1 on OBJ X.
        for i,line in enumerate(lines):
            if line.startswith("v "):
                _,x,y,z=line.split()
                lines[i]=f"v {float(x)+1:.6f} {y} {z}"
        f.write_text("\n".join(lines)+"\n")
wire.author(review,"electric_crossing_wire.blend")
