#!/usr/bin/env python3
"""Check final embedded rail/wire joints and portal/lane clearance in all orientations."""
from pathlib import Path
from math import isclose
import struct

ROOT=Path(__file__).resolve().parents[1]
MODELS=ROOT/"mods/bayline/models"
ORTHOGONAL=((-1,0),(0,1),(1,0),(0,-1))
EPS=2e-6
ROLLING=("Paved_rail_grooves","Road_flush_tram_rail","Live_overhead_contact_wire")


def parse(path,entity_scale=None):
    verts=[]
    groups={}
    group="untagged"
    for line in path.read_text().splitlines():
        if line.startswith("o "):
            group=line[2:]
        elif line.startswith("v "):
            x,y,z=map(float,line[2:].split())
            if entity_scale:
                k=entity_scale/10
                verts.append((-x*k,z*k,y*k))
            else:
                verts.append((-x-.5,z-.5,y+.5))
        elif line.startswith("f "):
            face=tuple(verts[int(r.split("/")[0])-1] for r in line[2:].split())
            groups.setdefault(group,[]).append(face)
    return verts,groups


def edge(groups,d,source=False):
    dx,dz=d
    selected={n for n in groups if n in ROLLING} if not source else {
        n for n in groups if n.startswith(("Embedded_grooved_rail","Contact_conductor"))}
    return {tuple(round(y,6) for y in (z if dx else x,h)) for n in selected for f in groups[n]
            for x,z,h in f if isclose(x*dx+z*dz,1,abs_tol=EPS)}


def intersects(groups,dx,dz,x0,y,z0,z1):
    for group,faces in groups.items():
        if group in ROLLING:
            continue  # wheels and pantograph are supposed to make contact here
        for face in faces:
            (a,b,c)=[(z*dx-x*dz,h,x*dx+z*dz) for x,z,h in face]
            u1,v1=b[0]-a[0],b[1]-a[1]
            u2,v2=c[0]-a[0],c[1]-a[1]
            ux,vx=x0-a[0],y-a[1]
            det=u1*v2-v1*u2
            if abs(det)<1e-12:
                continue
            u,v=(ux*v2-vx*u2)/det,(u1*vx-v1*ux)/det
            if min(u,v)>=-EPS and u+v<=1+EPS:
                z=a[2]+u*(b[2]-a[2])+v*(c[2]-a[2])
                if z0<=z<=z1:
                    return True
    return False


def main():
    atlas=ROOT/"mods/bayline/textures/bl_tram_facilities_atlas.png"
    assert struct.unpack(">II",atlas.read_bytes()[16:24])==(36*8,8)
    baseline=[]
    names=("bl_tram_rails_5.obj","bl_tram_wire_5.obj")
    for name in names:
        v,g=parse(MODELS/name)
        baseline.append(edge(g,(0,1),True))
    profile=baseline[0]|baseline[1]
    assert len(profile)==40 and {h for _,h in profile}=={.001,.006,.012,.500,.513}
    stock_widths=[]
    for asset,k in (("streetcar",.40),("leopard_bus",.40),("town_flyer",.42),("coach",.42),
                    ("mail_van",.43),("truck",.40)):
        v,_=parse(MODELS/f"bl_{asset}.obj",k)
        stock_widths.append(max(abs(x) for x,z,h in v))
    clearance=.155+max(stock_widths)
    assert clearance<.291
    for axis,dirs in ((0,{0,2}),(1,{1,3})):
        v,g=parse(MODELS/f"bl_tram_stop_{axis}.obj")
        assert len(v)>1600
        assert all(abs(x)<=1+EPS and abs(z)<=1+EPS for x,z,_ in v)
        for i,d in enumerate(ORTHOGONAL):
            assert edge(g,d)==(profile if i in dirs else set()),(axis,i)
        island=g["Taper-ended_boarding_islands"]
        assert isclose(max(h for f in island for _,_,h in f),.074,abs_tol=EPS)
        assert min(h for f in island for _,_,h in f if h>.01)<.039
        assert all(abs((z,x)[axis])>=.349-EPS or h>.501-EPS
                   for n,f in g.items() if n not in ROLLING for face in f for x,z,h in face)
    rays=0
    for dir,(dx,dz) in enumerate(ORTHOGONAL):
        v,g=parse(MODELS/f"bl_tram_depot_{dir}.obj")
        assert len(v)>2100
        assert all(abs(x)<=1+EPS and abs(z)<=1+EPS for x,z,_ in v)
        for i,d in enumerate(ORTHOGONAL):
            assert edge(g,d)==(profile if i==dir else set()),(dir,i)
        for lane in (-.155,.155):
            for x in (lane-.135,lane-.08,lane,lane+.08,lane+.135):
                for h in (.020,.09,.183,.29,.379,.482,.505):
                    assert not intersects(g,dx,dz,x,h,-.826,1.02),(dir,x,h)
                    rays+=1
                assert intersects(g,dx,dz,x,.288,-1.01,-.831),(dir,x)
    print(f"PASS: six tram facilities, stock-equivalent rail/wire seams, .059-node island margin, {rays} open depot lane rays and four closed backs")


if __name__=="__main__":
    main()
