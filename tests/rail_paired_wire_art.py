#!/usr/bin/env python3
"""Check every independent eased contact and rotated portal geometry."""
from pathlib import Path
from math import hypot

m=Path("mods/luanttd_core/models")
assert len(list(m.glob("bl_rail_pair_contact_*.obj")))==30
assert len(list(m.glob("bl_rail_pair_single_*.obj")))==12

# Endpoints from the canonical two-node TileTrack frame. Mode bits
# determine which tangent includes a true 45° straight approach.
ends={4:((-1,0),(0,-1)),8:((1,0),(0,1)),16:((1,0),(0,-1)),32:((-1,0),(0,1))}
for bit,(a,b) in ends.items():
    for mode in (1,2,3):
        p=m/f"bl_rail_pair_single_{bit}_{mode}.obj"
        s=p.read_text().splitlines()
        keep=False;row=[]
        for r in s:
            if r.startswith("# o "): keep=r.endswith("_contact_wire")
            if keep and r.startswith("v "):
                x,h,z=map(float,r.split()[1:])
                row.append((-x-.5,z-.5,h+1.5))
        assert row and all(.898-1e-7<=h<=.907+1e-7 for _,_,h in row)
        for k,(u,v) in enumerate((a,b)):
            endpoint=[(x-u,z-v) for x,z,_ in row if hypot(x-u,z-v)<.006001]
            assert len(endpoint)==4
            if mode&1<<k:
                assert all(abs(abs(x)-abs(z))<.000002 for x,z in endpoint), (bit,mode,k,endpoint)
            else:
                assert all(abs(x)<.000002 or abs(z)<.000002 for x,z in endpoint)
for mask in (12,48):
    for a in range(4):
        for b in range(4):
            if a+b:
                p=m/f"bl_rail_pair_contact_{mask}_{a}_{b}.obj"
                assert p.stat().st_size>16000
p=m/"bl_rail_pair_portal_12.obj"
foot=[];keep=False
for line in p.read_text().splitlines():
    if line.startswith("o "): keep=line=="o Cast_granite_portal_foundation"
    if keep and line.startswith("v "):
        x,y,z=map(float,line.split()[1:])
        foot.append((.5-x,.5+z,y))
assert foot and all(abs(x)>.77 and abs(z)>.77 and x*z<0 for x,z,y in foot)
assert Path("art/rail_paired_wire.blend").stat().st_size>50000
print("PASS original paired rail contact meshes keep the 45° exposed ports, voltage seams, and opposite clear-footing steelwork")
