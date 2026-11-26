#!/usr/bin/env python3
"""Verify native contact endpoints/track bits and off-track foundations."""
from pathlib import Path
import math
import re

models = Path("mods/luanttd_core/models")
side = ((-1.,0.), (0.,1.), (1.,0.), (0.,-1.))
tracks = ((0,2), (3,1), (0,3), (2,1), (2,3), (0,1))
rendered = 0
for bits in range(1,64):
    p = models/f"bl_rail_compound_contact_{bits}.obj"
    raw = p.read_text().splitlines()
    groups = {}
    rendered += p.stat().st_size
    assert raw[1]=="g CompoundContact"
    for text in raw:
        if text.startswith("# o "):
            group=text[4:]
            groups[group]=[]
        if text.startswith("v "):
            u,y,z=map(float,text.split()[1:])
            groups[group].append((-u-.5,z-.5,y+1.5))
    have = {int(m[1]) for name in groups if (m := re.fullmatch(r"Track_(\d)_contact_wire",name))}
    assert have=={i for i in range(6) if bits&1<<i},bits
    for track in have:
        row=groups[f"Track_{track}_contact_wire"]
        assert min(h for _,_,h in row)==.898
        assert abs(max(h for _,_,h in row)-.907)<1e-7
        assert not any("foundation" in n.lower() for n in groups)
        for d in tracks[track]:
            x,z=side[d]
            assert sum(1 for a,b,_ in row if math.hypot(x-a,z-b)<.006001)==4,(bits,track,d)
        if bits&3==3 and track==1:
            assert not any(abs(z)<.005 for _,z,_ in row),"Independent crossing wire must not stack coincident faces"
assert rendered<2900000,rendered
raw=(models/"bl_rail_compound_portal.obj").read_text().splitlines()
foot=[]
all_y=[]
keep=False
for line in raw:
    if line.startswith("o "): keep=line=="o Cast_granite_portal_foundation"
    if line.startswith("v "):
        u,y,z=map(float,line.split()[1:])
        x,z,y=.5-u,.5+z,1.5+y
        all_y.append(y)
        if keep: foot.append((x,z,y))
assert abs(min(all_y))<1e-8 and max(all_y)<1.35
assert foot and {math.copysign(1,x) for x,_,_ in foot}=={-1,1}
for x,z,y in foot:
    assert abs(x)>.77 and abs(z)>.77 and x*z>0
    assert 0<=y<=.09
source=Path("art/rail_compound_wire.blend")
assert source.stat().st_size>50000
print(f"PASS 63 original compact steel wire meshes, exact contact ends and isolated grounded portal")
