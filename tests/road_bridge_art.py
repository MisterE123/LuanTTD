#!/usr/bin/env python3
"""Check the native bridge OBJ seam profiles, ramp plane and real timber piers."""
from collections import defaultdict
from itertools import product
from math import isclose
from pathlib import Path

from PIL import Image

ROOT=Path(__file__).resolve().parents[1]/"mods"/"luanttd_core"
P="bl_road_bridge_wood"
DIR=((-1,0),(0,1),(1,0),(0,-1))
SURFACE=("Running_asphalt","Shoulder_slab","Inlaid_centre_markings")
PROFILES={"Running_asphalt":[(-.3125,.3125)],"Shoulder_slab":[(-.375,-.3125),(.3125,.375)]}
COLORS={"Running_asphalt":(79,82,85),"Shoulder_slab":(154,147,126),
        "Inlaid_centre_markings":(239,227,182)}


def read(file):
    group,vertices,normals,uv = None,[],[],[]
    shapes=defaultdict(list)
    for line in file.read_text().splitlines():
        tag,_,data=line.partition(" ")
        if tag=="v":
            ox,y,z=map(float,data.split())
            v=(-ox-.5,z-.5,y)
            assert -.870001<=y<=.820001 and abs(v[0])<=1.000001 and abs(v[1])<=1.000001, (file,v)
            vertices.append(v)
        elif tag=="vt":
            uv.append(tuple(map(float,data.split())))
        elif tag=="vn":
            n=tuple(map(float,data.split()))
            assert abs(sum(el*el for el in n)-1)<.00001
            normals.append(n)
        elif tag=="o":
            group=data
        elif tag=="f":
            parsed=[tuple(int(n)-1 for n in s.split("/")) for s in data.split()]
            assert len(parsed)==3 and len({item[1] for item in parsed})==1
            assert len({item[2] for item in parsed})==1
            vs=[vertices[i[0]] for i in parsed]
            s, t=uv[parsed[0][1]]
            n=normals[parsed[0][2]]
            shapes[group].append((vs,(s,t),n))
    return shapes


def coords(p,direction):
    dx,dz=DIR[direction]
    x,z,y=p
    return dz*x-dx*z,dx*x+dz*z,y


def seam(shape,direction,far):
    target=1 if far else -1
    result=defaultdict(list)
    for name, tris in shape.items():
        if name not in (*SURFACE,"Continuous_railings","Continuous_timber_stringers"):
            continue
        for vs, _, _ in tris:
            pts=[(u,y) for u,v,y in [coords(p,direction) for p in vs] if v==target]
            if len(pts)==2:
                result[name].append(tuple(sorted(pts)))
    return result


def profile(seam):
    return {k:sorted({tuple(sorted(x for x,_ in edge)) for edge in all_edges
                      if edge[0][0]!=edge[1][0]}) for k,all_edges in seam.items() if k in SURFACE}


def main():
    tex=Image.open(ROOT/"textures"/f"{P}.png").convert("RGB")
    models=ROOT/"models"
    heads={}
    for kind,d in product(("flat","ramp"),range(4)):
        shapes=read(models/f"{P}_head_{kind}_{d}.obj")
        assert "Head_ashlar_abutment" in shapes and "Guardrail_posts" in shapes
        inner,outer=seam(shapes,d,True),seam(shapes,d,False)
        assert profile(inner)==profile(outer)==PROFILES
        assert all(y==.5 for f in SURFACE for edge in inner.get(f,[]) for _,y in edge)
        assert all(y==(-.5 if kind=="ramp" else .5) for f in SURFACE for edge in outer.get(f,[]) for _,y in edge)
        assert not outer.get("Continuous_railings")  # guardrails stop before the ordinary street
        def surface_area(tris):
            return sum(abs((b[0]-a[0])*(c[1]-a[1])-(c[0]-a[0])*(b[1]-a[1]))/2
                       for (a,b,c),_,_ in tris)
        assert surface_area(shapes["Shoulder_slab"])==.25
        assert surface_area(shapes["Inlaid_centre_markings"])==.078125
        assert surface_area(shapes["Running_asphalt"])==1.25-.078125
        for group in SURFACE:
            for vs, uv, n in shapes[group]:
                assert tex.getpixel((int(tex.width*uv[0]),int(tex.height*uv[1])))==COLORS[group]
                assert n[1]>.89, (kind,d,group,n)
                for point in vs:
                    u,v,y=coords(point,d)
                    assert abs(u)<=.375 and -1<=v<=1
                    assert isclose(y,.5+(v-1)/2 if kind=="ramp" else .5,abs_tol=1e-6)
        heads[kind,d]=inner
    comparisons=0
    for axis,d in ((0,2),(1,1)):
        shapes=read(models/f"{P}_span_{axis}.obj")
        left,right=seam(shapes,d,False),seam(shapes,d,True)
        assert profile(left)==profile(right)==PROFILES
        for k in (*PROFILES,"Continuous_railings","Continuous_timber_stringers"):
            # Winding of a face can triangulate differently at the opposite
            # edge. Its unique contact vertices must both exist at each seam.
            vertices=lambda s,k:{v for e in s[k] for v in e}
            assert vertices(left,k)==vertices(right,k)
            for head in ("ramp","flat"):
                assert vertices(heads[head,d],k)==vertices(left,k)
                other=(d+2)%4
                assert {(-u,y) for u,y in vertices(heads[head,other],k)}==vertices(right,k)
                comparisons+=2
        for head_a,head_b in product(("ramp","flat"),repeat=2):
            for k in (*PROFILES,"Continuous_railings","Continuous_timber_stringers"):
                assert vertices(heads[head_a,d],k)=={(-u,y) for u,y in vertices(heads[head_b,(d+2)%4],k)}
                comparisons+=1
        pier=read(models/f"{P}_pier_{axis}.obj")
        leg={p for vs,_,_ in pier["Trestle_legs"] for p in vs}
        cap_legs={p for vs,_,_ in shapes["Pier_cap_king_posts"] for p in vs}
        assert {(x,z) for x,z,y in leg if y==.5}=={(x,z) for x,z,y in cap_legs if y==-.5}
        assert {(x,z) for x,z,y in leg if y==.5}=={(x,z) for x,z,y in leg if y==-.5}
        assert {"Diagonal_sway_braces","Forged_pier_tie_bolts"} <= set(pier)
        road=Image.open(ROOT/"textures"/f"bl_road_surface_{10 if axis==0 else 5}.png").convert("RGB")
        for n in (0,31):
            edge=[road.getpixel((n,v) if axis==0 else (v,n)) for v in range(32)]
            assert edge[10:22]==[COLORS["Shoulder_slab"]]+[COLORS["Running_asphalt"]]*10+[COLORS["Shoulder_slab"]]
    print(f"PASS: 12 timber bridge meshes; {comparisons} head/span structural seam checks, "
          "two axial pier stacks, exact ramp planes and matching stock road edge colors.")


if __name__=="__main__":
    main()
