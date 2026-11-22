#!/usr/bin/env python3
"""Inspect the actual Luanti harbour OBJ files, not just Blender scene bounds."""
from math import isclose
from pathlib import Path
import struct

ROOT=Path(__file__).resolve().parents[1]
MODELS=ROOT/"mods/luanttd_core/models"
TEXTURES=ROOT/"mods/luanttd_core/textures"
DIRS=((-1,0),(0,1),(1,0),(0,-1))
EPS=2e-6


def read(name,entity=False):
    path=MODELS/f"bl_{name}.obj"
    vertices=[]
    faces={}
    vt=[]
    group=None
    for s in path.read_text().splitlines():
        kind,_,data=s.partition(" ")
        if kind=="v":
            x,h,z=map(float,data.split())
            vertices.append((-x/10,z/10,h/10) if entity else (-x-.5,z-.5,h+.5))
        if kind=="vt":
            a,b=map(float,data.split())
            vt.append((a,b))
        if kind=="o":
            group=faces.setdefault(data,[])
        if kind=="f":
            i=[];tex=[]
            for part in data.split():
                values=part.split("/")
                i.append(vertices[int(values[0])-1])
                tex.append(vt[int(values[1])-1])
            assert len(i)==3
            group.append((tuple(i),tex))
    return faces


def points(mesh,names=None):
    if names is None:names=mesh
    return {v for n in names for face,_ in mesh[n] for v in face}


def rim(mesh,names,along,direction):
    dx,dz=direction
    return {(round(z if dx else x,6),round(h,6)) for x,z,h in points(mesh,names)
            if abs(dx*x+dz*z-along)<EPS}


def ray(mesh,axis,x0,height,y0,y1):
    for g in mesh.values():
        for face,_ in g:
            (a,b,c)=[(z,h,x) if axis==0 else (x,h,z) for x,z,h in face]
            ux,vx=b[0]-a[0],b[1]-a[1]
            uy,vy=c[0]-a[0],c[1]-a[1]
            s,t=x0-a[0],height-a[1]
            det=ux*vy-uy*vx
            if abs(det)<1e-12:continue
            u,v=(s*vy-t*uy)/det,(ux*t-vx*s)/det
            if min(u,v)>=-EPS and u+v<=1+EPS:
                hit=a[2]+u*(b[2]-a[2])+v*(c[2]-a[2])
                if y0<=hit<=y1:return True
    return False


def main():
    assert struct.unpack(">II",(TEXTURES/"bl_ship_facilities_atlas.png").read_bytes()[16:24])==(512,64)
    shapes=(3,9,12,6)
    for d,vec in enumerate(DIRS):
        r=read(f"ship_dock_ramp_{d}")
        p=read(f"ship_dock_pier_{d}")
        ground=r["Shared_corner_ground"]
        land=read(f"land_{shapes[d]}")
        assert points(r,("Shared_corner_ground",))==points(land)
        expect_uv={(round((4.5+31*(x+1)/2)/512,7),round(1-(4.5+31*(z+1)/2)/64,7))
                   for x,z,h in points(land)}
        assert {v for _,uv in ground for v in uv}==expect_uv
        a=rim(r,("Staggered_non-slip_footway_boards",),1,vec)
        b=rim(p,("Individually_laid_harbour_planks",),-1,vec)
        assert {v for v in a if v[1]>.179}=={v for v in b if v[1]>.179}=={(-.335,.180),(.335,.180)}
        a=rim(r,("Timber_gangway_handrails",),1,vec)
        b=rim(p,("Joined_landing_handrails",),-1,vec)
        assert a==b and len(a)==16,(d,a,b)
        assert all(abs(x)<=1+EPS and abs(z)<=1+EPS for x,z,h in points(r))
        assert all(abs(x)<=1+EPS and abs(z)<=1+EPS for x,z,h in points(p))
        dx,dz=vec
        assert max(dx*x+dz*z for x,z,h in points(p))<.940
        assert min(h for x,z,h in points(p))<-.5
    hull=points(read("harbor_ferry",entity=True))
    assert max(abs(x) for x,z,h in hull)<.386 and max(abs(z) for x,z,h in hull)<.915
    assert min(h for x,z,h in hull)>-.195 and max(h for x,z,h in hull)<.913
    rays=0
    for axis,d in ((0,(1,0)),(1,(0,1))):
        a,b=(read(f"ship_depot_{axis}_{part}") for part in (0,1))
        for group in ("Two-piece_standing_seam_roof","Continuous_ridge_cap","Long_side_masonry",
                      "Covered_service_catwalk_and_joists","Marine_stone_piling_wall"):
            af=rim(a,(group,),1,d)
            bf=rim(b,(group,),-1,d)
            assert af and af==bf,(axis,group,af,bf)
        for m in (a,b):
            assert all(abs(x)<=1+EPS and abs(z)<=1+EPS for x,z,h in points(m))
            for x in (-.515,-.387,-.233,0,.233,.387,.515):
                for h in (-.218,-.182,-.109,.000,.129,.27,.509,.910,1.193):
                    assert not ray(m,axis,x,h,-1.005,1.005),(axis,x,h)
                    rays+=1
            assert ray(m,axis,0,1.255,-1.005,1.005),"portal architrave missing"
    print(f"PASS: four exact terrain/UV grades, four gangway/railing joins, matching depot roof/catwalk seams, {rays} unobstructed portal rays at real ferry gauge")


if __name__=="__main__":
    main()
