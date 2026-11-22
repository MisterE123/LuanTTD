#!/usr/bin/env python3
"""Geometry/texture regression for the stock-2 steel bridge meshes."""
from itertools import product
from collections import defaultdict
from pathlib import Path
from PIL import Image

ROOT=Path(__file__).resolve().parents[1]/"mods"/"luanttd_core"
MODELS=ROOT/"models"
ASSEMBLY="bl_road_bridge_girder"
SURFACE=("Running_asphalt","Shoulder_slab","Inlaid_centre_markings")
CONTINUOUS=("Continuous_plate_girders","Continuous_angle_flanges","Continuous_steel_handrails",
            "Structural_floor_chords","Composite_deck_slab")
DIR=((-1,0),(0,1),(1,0),(0,-1))
ROAD_COLORS=((79,82,85),(154,147,126),(239,227,182))


def read(prefix,key):
    verts,normals,uv,groups=[],[],[],defaultdict(list)
    shapes=MODELS/f"{prefix}_{key}.obj"
    for line in shapes.read_text().splitlines():
        tag,_,data=line.partition(" ")
        if tag=="o":
            group=data
        elif tag=="v":
            x,y,z=map(float,data.split())
            x,z=-x-.5,z-.5
            assert abs(x)<=1.000001 and abs(z)<=1.000001 and -.882<=y<=.821,(x,y,z,shapes)
            verts.append((x,z,y))
        elif tag=="vn":
            n=tuple(map(float,data.split()))
            assert abs(sum(v*v for v in n)-1)<.00001
            normals.append(n)
        elif tag=="vt":
            uv.append(tuple(map(float,data.split())))
        elif tag=="f":
            xyz,tex,norm=zip(*(tuple(int(v)-1 for v in ref.split("/")) for ref in data.split()))
            assert len(xyz)==3 and len(set(xyz))==3 and len(set(tex))==len(set(norm))==1
            groups[group].append((tuple(verts[i] for i in xyz),uv[tex[0]],normals[norm[0]]))
    return groups


def coordinates(p,d):
    x,z,y=p
    dx,dz=DIR[d]
    return dz*x-dx*z, dx*x+dz*z, y


def plane(asset,names,d,edge):
    return {g:{(u,y) for pts,_,_ in asset[g] for u,v,y in (coordinates(p,d) for p in pts)
               if v==edge} for g in names}


def flip(profile):
    return {key:{(-u,y) for u,y in points} for key,points in profile.items()}


def area(tris):
    return sum(abs((b[0]-a[0])*(c[1]-a[1])-(c[0]-a[0])*(b[1]-a[1]))/2 for (a,b,c),_,_ in tris)


def main():
    atlas=Image.open(ROOT/"textures"/f"{ASSEMBLY}.png").convert("RGB")
    heads={}
    road_equivalents=0
    for kind,d in tuple(product(("head_flat","head_ramp"),range(4)))+(("span",0),("span",1)):
        key=f"{kind}_{d}"
        cur=read(ASSEMBLY,key)
        wood=read("bl_road_bridge_wood",key)
        assert all(len(cur[g])>200 for g in ("Raised_web_rivets",))
        assert all(cur[g] for g in ("Riveted_transverse_stiffeners","Steel_balusters","Hollow_web_pockets"))
        for g,color in zip(SURFACE,ROAD_COLORS):
            assert [t for t,_,_ in cur[g]]==[t for t,_,_ in wood[g]], (key,g,"changed the road mesh")
            for _,(u,v),n in cur[g]:
                assert atlas.getpixel((int(u*atlas.width),int(v*atlas.height)))==color
                assert n[1]>.89
            road_equivalents+=1
        assert tuple(area(cur[g]) for g in SURFACE)==(1.171875,.25,.078125)
        if kind!="span":
            heads[kind,d]=cur
            outside=plane(cur,SURFACE,d,-1)
            assert all(y==(-.5 if kind=="head_ramp" else .5) for p in outside.values() for _,y in p)
            assert not plane(cur,("Continuous_steel_handrails",),d,-1)["Continuous_steel_handrails"]

    comparisons=0
    for axis,d in ((0,2),(1,1)):
        span=read(ASSEMBLY,f"span_{axis}")
        other=(d+2)%4
        full=SURFACE+CONTINUOUS
        before,after=plane(span,full,d,-1),plane(span,full,d,1)
        assert before==after
        for head_kind in ("head_flat","head_ramp"):
            test=plane(heads[head_kind,d],full,d,1)
            rev=flip(plane(heads[head_kind,other],full,other,1))
            assert before==test and after==rev
            comparisons+=2*len(full)
        for hk1,hk2 in product(("head_flat","head_ramp"),repeat=2):
            assert plane(heads[hk1,d],full,d,1)==flip(plane(heads[hk2,other],full,other,1))
            comparisons+=len(full)
        pier=read(ASSEMBLY,f"pier_{axis}")
        top={(x,z) for pts,_,_ in pier["Octagonal_concrete_pier"] for x,z,y in pts if y==.5}
        lower={(x,z) for pts,_,_ in pier["Octagonal_concrete_pier"] for x,z,y in pts if y==-.5}
        cap={(x,z) for pts,_,_ in span["Pier_crown"] for x,z,y in pts if y==-.5}
        assert len(top)==8 and top==lower==cap and pier["Dressed_bolster_collars"]
    print(f"PASS: 12 steel girder meshes, {comparisons} seam checks, {road_equivalents} "
          "exact shared road-surface profiles and two stackable concrete pier axes.")


if __name__=="__main__":
    main()
