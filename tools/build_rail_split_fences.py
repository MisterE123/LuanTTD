#!/usr/bin/env python3
"""Export stock fence designs on correctly elevated carriageway borders."""
from argparse import ArgumentParser
from pathlib import Path
import subprocess

from build_stock_rail_ground_fence_art import (
    ATLAS_W, H, POST_FOOT, POST_TOP, WIRE_BOTTOM, WIRE_TOP, Fence, serialize,
)

p=ArgumentParser(description=__doc__)
p.add_argument("--check",action="store_true")
p.add_argument("--lua",default="lua5.1")
a=p.parse_args()
root=Path(__file__).resolve().parents[1]
raw=subprocess.check_output([a.lua,"tools/dump_rail_split_fence_designs.lua"],cwd=root,text=True)
known=set()
for line in raw.splitlines():
    key,boundary,units,quant=line.split("\t")
    x,z,u,v=map(float,boundary.split(","))
    profile=[float(q)/int(quant)-.5 for q in units.split(",")]
    mesh=Fence()
    def pos(i,dy):
        t=i/4
        return (x+(u-x)*t,profile[i]+dy,z+(v-z)*t-1)
    for i in range(5):
        xx,y,zz=pos(i,0)
        mesh.box("Steel posts and galvanized caps",xx,zz,y+POST_FOOT,y+POST_TOP,.015,.015)
    for i in range(4):
        mesh.rail("Pressed coping and low cable",pos(i,.397),pos(i+1,.397),.012,.012)
        mesh.rail("Pressed coping and low cable",pos(i,.048),pos(i+1,.048),.008,.009,4,4)
        points=tuple(pos(j,height) for j,height in
                     ((i,WIRE_BOTTOM),(i+1,WIRE_BOTTOM),(i+1,WIRE_TOP),(i,WIRE_TOP)))
        a0=(.5+(87*i/4))/ATLAS_W
        a1=(.5+(87*(i+1)/4))/ATLAS_W
        texture=((a0,1.5/H),(a1,1.5/H),(a1,30.5/H),(a0,30.5/H))
        mesh.face("Welded wire lattice",None,points,texture)
        mesh.face("Welded wire lattice",None,points[::-1],texture[::-1])
    path=root/"mods/luanttd_core/models"/f"bl_rail_split_fence_{key}.obj"
    data=serialize(mesh).replace(b"Original RC1-ground stock railway fence; tools/build_stock_rail_ground_fence_art.py",
          b"Original RC1 cut-slope railway fence; tools/build_rail_split_fences.py",1)
    if a.check: assert path.read_bytes()==data,path
    else: path.write_bytes(data)
    known.add(path.name)
assert known=={f.name for f in (root/"mods/luanttd_core/models").glob("bl_rail_split_fence_*.obj")}
print(f"PASS {len(known)} reusable split-fence meshes and deterministic fit")
