#!/usr/bin/env python3
"""Test the exported stock aqueduct mesh, seams and occupied clearance volumes."""
from collections import defaultdict
from itertools import product
from pathlib import Path
from PIL import Image

from road_tunnel_art import polygon_clip, vehicle_bounds

ROOT=Path(__file__).resolve().parents[1]/"mods"/"luanttd_core"
MODELS=ROOT/"models"
ATLAS=ROOT/"textures"/"bl_aqueduct.png"
STOCK_DIRS=((-1,0),(0,1),(1,0),(0,-1))
JOINS=("Continuous_level_water","Continuous_watertight_trough_lining",
       "Individually_laid_upper_coping","Continuously_profiled_masonry_band",
       "Continuous_submerged_reinforcing_band","Continuous_masonry_exterior_string",
       "Water-retaining_solid_floor","Restrain_course_beneath_wet_liner")
WATER=JOINS[0]


def read(key,d):
    file=MODELS/f"bl_aqueduct_{key}.obj"
    out=defaultdict(list);verts=[];uv=[];normals=[]
    dx,dz=STOCK_DIRS[d]
    for line in file.read_text().splitlines():
        tag,_,v=line.partition(" ")
        if tag=="v":
            ox,y,z=map(float,v.split())
            x,z=-ox-.5,z-.5
            u,s=dz*x-dx*z,dx*x+dz*z
            assert abs(u)<=1.000001 and abs(s)<=1.000001 and -.500001<=y<=1.115001,(key,u,s,y)
            verts.append(tuple(round(p,6) for p in (u,s,y)))
        if tag=="vt":
            uv.append(tuple(map(float,v.split())))
        if tag=="vn":
            n=tuple(map(float,v.split()))
            assert abs(sum(d*d for d in n)-1)<1e-5
            normals.append(n)
        if tag=="o":
            group=v
        if tag=="f":
            ids,tex,norm=zip(*(tuple(int(p)-1 for p in i.split("/")) for i in v.split()))
            assert len(ids)==len(set(ids))==3 and len(set(tex))==len(set(norm))==1
            out[group].append(([verts[i] for i in ids],uv[tex[0]],normals[norm[0]]))
    return out


def edge(data,names,v):
    return {g:{(u,y) for tri,_,_ in data[g] for u,s,y in tri if s==v} for g in names}


def danger(tri,axis,left,right,floor,roof):
    p=list(tri)
    for coord,bound,hi in ((axis,left,True),(axis,right,False),(2,floor,True),(2,roof,False)):
        p=polygon_clip(p,coord,bound,hi)
    return bool(p)


def vehicle(name):
    verts=[tuple(map(float,l[2:].split())) for l in (MODELS/f"bl_{name}.obj").read_text().splitlines()
           if l.startswith("v ")]
    return max(abs(p[0])/10 for p in verts),min(p[1]/10 for p in verts),max(p[1]/10 for p in verts)


def area(tri):
    a,b,c=tri
    return abs((b[0]-a[0])*(c[1]-a[1])-(c[0]-a[0])*(b[1]-a[1]))/2


def main():
    tex=Image.open(ATLAS).convert("RGB")
    regular=Image.open(ROOT/"textures"/"bl_water0.png").convert("RGB")
    assert regular.getpixel((0,0))==(42,97,126)
    boat,sole,mast=vehicle("harbor_ferry")
    assert .380<boat<.382 and .902<mast<.904
    ship_specs=[vehicle(n) for n in ("ferry","freighter","harbor_ferry")]
    _,road_specs,_=vehicle_bounds()
    road_roof=max(y for _,y in road_specs.values())-1+.02
    # Local floor of a rail at an adequate deck two levels higher.
    train_roof=max(vehicle(n)[2] for n in ("steam","diesel","electric"))+.614-2+.02
    heads={}
    cases=0
    for suffix,key,d in (*[(i,"head",i) for i in range(4)],(0,"span",2),(1,"span",1)):
        shapes=read(f"{key}_{suffix}",d)
        assert set(JOINS)<=set(shapes)
        for tri,uv,n in shapes[WATER]:
            assert all(h==.5 for _,_,h in tri) and n[1]==1
            color=tex.getpixel((int(tex.width*uv[0]),int(tex.height*uv[1])))
            assert color in ((42,97,126),(69,132,158))
            if any(abs(s)==1 for _,s,_ in tri):
                assert color==(42,97,126),"water seam color drifts"
        for v in (-1,1):
            expect=1 if v==-1 and key=="head" else .56
            points=edge(shapes,(WATER,),v)[WATER]
            assert points=={(-expect,.5),(expect,.5)},(key,d,v,points)
        actual=sum(area(tri) for tri,_,_ in shapes[WATER])
        assert abs(actual-(2.724 if key=="head" else 2.24))<1e-5

        for g,part in shapes.items():
            if g==WATER: continue  # regular ship waterline clips the drawn waves
            for tri,_,_ in part:
                for u,y,top in ship_specs:
                    # Belt includes a +/- .10 node centering margin and
                    # entire longitudinal extent, so it exercises the
                    # mast and hull continuously at approach, head and span.
                    assert not danger(tri,0,-u-.10,u+.10,.5+y-.015,.5+top+.015),(key,d,g,tri)
        if key=="head":
            heads[d]=shapes
            group=shapes["Natural_sloping_head_banks"]
            for tri,_,_ in group:
                for u,s,h in tri:
                    assert abs(h-(.5-(s+1)/2))<1e-6
        else:
            # Native lower roads can be one level below. A higher
            # locomotive needs two levels; no fictitious clearance at one.
            for part in shapes.values():
                for tri,_,_ in part:
                    for axis in (0,1):
                        assert not danger(tri,axis,-.55,.55,-.5,road_roof)
                        assert not danger(tri,axis,-.55,.55,-1.5,train_roof)

    for axis,d in ((0,2),(1,1)):
        span=read(f"span_{axis}",d)
        other=(d+2)%4
        first,last=edge(span,JOINS,-1),edge(span,JOINS,1)
        flip=lambda p:{name:{(-u,h) for u,h in q} for name,q in p.items()}
        assert first==last==edge(heads[d],JOINS,1)==flip(edge(heads[other],JOINS,1))
        cases+=len(JOINS)*4
        top=read(f"pier_head_{axis}",d)
        stack=read(f"pier_{axis}",d)
        low=lambda side,member,y:{(u,v) for faces,_,_ in side[member] for u,v,h in faces if h==y}
        assert len(low(top,"Raked_upper_pier_shaft",-.5))==8
        assert low(top,"Raked_upper_pier_shaft",-.5)==low(stack,"Repeating_lower_pier_shaft",.5)
        assert low(stack,"Repeating_lower_pier_shaft",-.5)==low(stack,"Repeating_lower_pier_shaft",.5)
        assert low(top,"Bearing_block_and_slab",1.115)
        assert {h for tri,_,_ in span["Water-retaining_solid_floor"] for _,_,h in tri}=={.115,.215}
    print(f"PASS: 10 native aqueduct parts, {cases} seams, water surface and terrain continuity, "
          "actual ferry and mast clearance, and unobstructed eligible road/rail underlays.")


if __name__=="__main__":
    main()
