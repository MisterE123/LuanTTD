#!/usr/bin/env python3
"""Verify the complete six-cell mesh and clear swept flight surfaces."""
# SPDX-License-Identifier: GPL-2.0-only
from pathlib import Path
from collections import Counter
from math import hypot
import struct

root=Path(__file__).resolve().parents[1]
models=root/"mods/luanttd_core/models"
atlas=root/"mods/luanttd_core/textures/bl_industry_oil_rig_atlas.png"
layout={(0,0):24,(0,1):24,(0,2):25,(1,0):26,(1,1):27,(1,2):28}
seen=set(models.glob("bl_industry_oil_rig_?_?.obj"))
expected={models/f"bl_industry_oil_rig_{x}_{z}.obj" for x,z in layout}
assert seen==expected
w,h=struct.unpack_from(">II",atlas.read_bytes(),16)
assert w%8==0 and h==8
nmat=w//8
group_count=Counter()
points=[]
zones=[]
for (x,z),gfx in layout.items():
    p=models/f"bl_industry_oil_rig_{x}_{z}.obj"
    lines=p.read_text().splitlines()
    assert f"GFX {gfx}; original Blender art" in lines[0]
    vv,nt,norm,faces=[],0,0,0
    for line in lines[1:]:
        t,*f=line.split()
        if t=="o":
            g=f[0]
        elif t=="v":
            a,b,c=map(float,f)
            assert -.500001<=c<=1.500001 and a<=.500001
            if a<-1.500001:
                assert (x,z)==(1,0) and a>=-1.725 and b+.5>6.56
                assert g.startswith(("Cantilevered","Clear_green","Flush_green","Under-edge"))
            else:
                assert a>=-1.500001
            v=(x*2-a,z*2+c,b+.5)
            vv.append(v)
            points.append(v)
        elif t=="vt":
            nt+=1
            assert abs(float(f[0])-(nt-.5)/nmat)<6e-7
        elif t=="vn":
            norm+=1
            assert abs(sum(float(c)**2 for c in f)-1)<3e-5
        elif t=="f":
            tri=[tuple(map(int,q.split("/"))) for q in f]
            assert all(0<a<=len(vv) and 0<b<=nt and 0<c<=norm for a,b,c in tri)
            verts=[vv[a-1] for a,_,_ in tri]
            lo,hi=zip(*[(min(k),max(k)) for k in zip(*verts)])
            zones.append((g,lo,hi))
            faces+=1
            group_count[g]+=1
    assert faces>=210 and nt==nmat,(p,faces)
assert all(any(t in g for g in group_count) for t in [
    "Submerged_battered_steel_piles","Chevron_primary_bracing","Crew_access_ladder",
    "Boat_transfer_landing","Hard_loading_line","Derrick_tapered","Hanging_drill",
    "Process_separation","Raised_crane_boom","Inset_broad_wheelhouse_glazing","Helipad_white_H",
])
assert min(y for _,_,y in points)<=-4.15
assert max(y for _,_,y in points)>8.45
# Under heliport path: load-bearing deck covers every stock ground
# movement datum and remains flat where the wheels/skids park.
surf=[(lo,hi) for g,lo,hi in zones if g.startswith("Clear_green_") and lo[2]==hi[2]==6.75]
for x,z in ((23,9),(28,9),(31,9)):
    a,b=x/8-.5,z/8-.5
    assert any(lo[0]<=a<=hi[0] and lo[1]<=b<=hi[1] for lo,hi in surf),(x,z)
    for g,lo,hi in zones:
        if hi[2]<=6.77:
            continue # flush paint, rescue nets, green lights
        dx=max(lo[0]-a,a-hi[0],0)
        dz=max(lo[1]-b,b-hi[1],0)
        # rotor-disc keepout while on deck and throughout direct descent.
        assert hypot(dx,dz)>.78,(g,(x,z),lo,hi)
# Hull/fenders physically do not extend into the navigable adjacent area.
assert min(a for a,_,_ in points)>=-.5-1e-6
assert max(a for a,_,y in points if y<6.55)<=3.5+1e-6
assert min(z for _,z,_ in points)>=-.5-1e-6
assert max(z for _,z,_ in points)<=5.5+1e-6
blend=root/"art/stock_oil_rig.blend"
assert blend.stat().st_size>120_000
print(f"PASS original Oil Rig art: six exact cells, {sum(group_count.values()):,} faces, submerged jacket, clear swept helideck")
