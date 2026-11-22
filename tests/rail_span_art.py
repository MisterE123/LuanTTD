#!/usr/bin/env python3
"""Check stock-compatible rail span artwork in exported engine geometry."""
import math
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
MODELS=ROOT/"mods/bayline/models"
DIRS=((-1,0),(0,1),(1,0),(0,-1))
EPS=3e-6

def load(name):
    lines=(MODELS/(name+".obj")).read_text().splitlines()
    vertices=[]; faces=[]; group=""
    for line in lines:
        a=line.split()
        if not a:continue
        if a[0]=="v":
            x,h,z=map(float,a[1:]);vertices.append((-x-.5,z-.5,h))
        if a[0]=="o":group=a[1]
        if a[0]=="f":
            p=tuple(vertices[int(i.split("/")[0])-1] for i in a[1:])
            assert len(p)==3,(name,group)
            faces.append((group,p))
    return faces

def physical(groups,*names):
    return [p for group,vs in groups for p in vs if group in names]

def basis(d,p):
    dx,dz=DIRS[d]
    x,z,h=p
    return dz*x-dx*z,dx*x+dz*z,h

def profile(mesh,dir,v,group,shift):
    return {(round(u,5),round(h+shift,5)) for u,axis,h in
            (basis(dir,p) for p in physical(mesh,group)) if abs(axis-v)<EPS}

def vehicle(name):
    for line in (MODELS/(name+".obj")).read_text().splitlines():
        a=line.split()
        if a and a[0]=="v":
            x,y,z=map(float,a[1:])
            yield -x/10,z/10,y/10

def bary(uv,tri,axes):
    x,y=uv;i,j=axes
    ax,ay=tri[0][i],tri[0][j]
    bx,by=tri[1][i],tri[1][j]
    cx,cy=tri[2][i],tri[2][j]
    d=(by-cy)*(ax-cx)+(cx-bx)*(ay-cy)
    if abs(d)<1.e-9:return None
    w=((by-cy)*(x-cx)+(cx-bx)*(y-cy))/d
    t=((cy-ay)*(x-cx)+(ax-cx)*(y-cy))/d
    a=(w,t,1-w-t)
    return a if min(a)>=-EPS and max(a)<=1+EPS else None

def along_ray(triangles,axis,u,v):
    other=tuple(i for i in range(3) if i!=axis)
    for tri in triangles:
        a=bary((u,v),tri,other)
        if a is not None:yield sum(x*p[axis] for x,p in zip(a,tri))

def main():
    bridge="bl_rail_bridge_wood";tunnel="bl_rail_tunnel_portal"
    stock=[load(f"bl_rail_track_{bit}") for bit in (1,2)]
    profiles=0;rays=0
    grouped=("Polished_railhead","Rail_web","Rail_foot")
    for d in range(4):
        span=load(f"{bridge}_span_{d%2}")
        portal=load(f"{tunnel}_{d}")
        for label,shift in (("flat",-1),("ramp",0)):
            head=load(f"{bridge}_head_{label}_{d}")
            other=load(f"{bridge}_head_{label}_{(d+2)%4}")
            for group in grouped:
                a=profile(head,d,1,group,0)
                b=profile(span,d,1,group,0)
                c=profile(span,d,-1,group,0)
                e=profile(other,(d+2)%4,1,group,0)
                assert a and a==b==c==e,(d,label,group,a,b,c,e)
                a=profile(head,d,-1,group,shift)
                b=profile(stock[d%2],d,1,group,0)
                assert a==b,(d,label,group,a,b)
                profiles+=5
            for u,z,h in (basis(d,p) for p in physical(head,"Polished_railhead")):
                assert min(abs(u-.212),abs(u+.212))<=.030+EPS
                base=.5 if label=="flat" else z/2
                assert any(abs(h-(base+off))<EPS for off in (.099,.114))
            if label=="flat":
                ground=[tuple(basis(d,p) for p in face) for name,face in head
                        if name=="Exact_outward-rising_founded_land"]
                for u in (-1,-.7,0,.79,1):
                    for v in (-1,-.7,0,.71,1):
                        heights=list(along_ray(ground,2,u,v))
                        assert heights and all(abs(h+v/2)<EPS for h in heights),(d,u,v,heights)
            for group in ("Bridge_inspection_fence","Renewable_inner_check_steel","Continuous_laminated_pitch-pine_stringers"):
                seam=profile(head,d,1,group,0)
                assert seam==profile(span,d,-1,group,0),(label,d,group,seam)
                profiles+=1
        for group in grouped:
            a=profile(portal,d,-1,group,0)
            b=profile(portal,d,1,group,0)
            c=profile(stock[d%2],d,1,group,0)
            assert a and a==b==c,(d,group,a,b,c)
            profiles+=2
        pier=load(f"{bridge}_pier_{d%2}")
        for u in (-.376,-.254,.254,.376):
            z=.072
            points=[basis(d,p) for p in physical(pier,"Trestle_twin_king_posts")]
            assert all(any(math.dist((u,z,y),p)<EPS for p in points) for y in (-.5,.5))
            assert any(math.dist((u,z,-.5),p)<EPS for p in (basis(d,t) for t in physical(span,"Trestle_twin_king_posts")))
        surfaces=[tuple(basis(d,p) for p in face) for _,face in portal]
        # All ground seams exactly maintain the neighboring corner-based incline.
        ground=[tuple(basis(d,p) for p in face) for name,face in portal if name in (
            "Cut_into_natural_graded_turf","Corner_seam_outside_retaining_head","Crowned_cut_turf_and_portal_backfill")]
        for side in (-1,1):
            for step in range(21):
                t=-1+step/10
                heights=list(along_ray(ground,2,side,t))
                assert heights and all(abs(h-t/2)<EPS for h in heights),(d,side,t,heights)
        trains=("bl_steam","bl_diesel","bl_electric","bl_rail_passenger_wagon","bl_rail_open_wagon")
        # Position each exact model through entrance, crown and open rear.
        # Compare against actual export, not only parametrized opening bounds.
        roof=[tri for group,ps in portal if group in ("Interior_soot-darkened_barrel_jambs",
             "Coursed_brick_intrados","Ashlar_spandrel_above_aperture","Quarry-cut_cornice_with_projecting_drip")
              for tri in [tuple(basis(d,p) for p in ps)]]
        for n in trains:
            highest={}
            for x,_,h in vehicle(n):
                highest[x]=max(h,highest.get(x,-10))
            for x,h in highest.items():
                assert abs(x)<.487-EPS
                for v in (.66,.78,.96,.998):
                    limits=list(along_ray(roof,2,x,v))
                    if limits:
                        assert h+.114-.5+.018<min(limits),(n,d,x,h,v,min(limits))
        for x in (-.29,-.2,-.1,0,.1,.2,.29):
            for h in (.14,.29,.50,.67,.78,.862,.914):
                assert not list(along_ray(surfaces,1,x,h-.5)),(d,x,h,list(along_ray(surfaces,1,x,h-.5)))
                rays+=1
    print(f"RAIL_SPAN_ART_PASS 16 assets, {profiles} exact running/fence/steel profiles, {rays} continuous approach-to-rear bore rays, five rail vehicles")
if __name__=="__main__":
    main()
