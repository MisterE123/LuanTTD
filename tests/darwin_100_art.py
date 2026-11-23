#!/usr/bin/env python3
"""Darwin #226 native mesh, source, and airport geometry verification."""
from collections import Counter
from hashlib import sha256
from math import hypot, pi
from pathlib import Path
import argparse
import os
import re
import struct
import sys

ROOT=Path(__file__).resolve().parents[1]
CORE=ROOT/"mods/luanttd_core"
STEM="bl_stock_darwin_100"
ENGINE_SHA="d90c9b2ae091a740522b0f79078c3e5db32b2467cb2a9e0e96592c3c39ee1f74"
AIRCRAFT_SHA="286ea285a00f2e8c3cee5cdb283703c6a47af77fc6743f9af90bd280ca1be80a"
MOVE_SHA="e3ce9a87ab0f81693136056fc6dd9fac821059fe2ca5468406e84bc4047a1ef5"
LAYOUT_SHA="c371f5a5479dbed83e884aa9849ff67ee7fb1296096a53a3b0bb595cbb6abeb7"


def mesh(file):
    points=[];uv=[];normals=[];faces=[]
    for row in file.read_text().splitlines():
        k,*fields=row.split()
        if k=="v":
            x,y,z=map(float,fields)
            points.append((-x/10,y/10,z/10))
        elif k=="vt":
            u,v=map(float,fields)
            assert 0<u<1 and v==.5
            uv.append(int(u*32))
        elif k=="vn":
            n=tuple(map(float,fields))
            assert .998<sum(t*t for t in n)<1.002
            normals.append(n)
        elif k=="f":
            refs=[tuple(map(int,f.split("/"))) for f in fields]
            assert len(refs)>=3 and all(1<=i<=len(points) and 1<=j<=len(uv) and 1<=k<=len(normals) for i,j,k in refs)
            assert len({uv[j-1] for _,j,_ in refs})==1
            t=tuple(points[i-1] for i,_,_ in refs)
            assert len(set(t))>=3
            faces.append((t,uv[refs[0][1]-1]))
        else:
            assert k in ("o","s") or k.startswith("#"),k
    return points,faces


def bore_test(faces):
    # Rays normal to the intake check both an open recess and solid rim.
    # A solid painted cylinder fails the open-recess case.
    pairs=((-.229,.329,-.497,.066),(0.,.449,-.647,.057),(.229,.329,-.497,.066))
    def at(x,y,p):
        (a,b,c),(d,e,f),(g,h,i)=p
        ux,uy=d-a,e-b
        vx,vy=g-a,h-b
        det=ux*vy-uy*vx
        if abs(det)<1e-12:return None
        w=((x-a)*vy-(y-b)*vx)/det
        v=(ux*(y-b)-uy*(x-a))/det
        if min(w,v,1-w-v)<-1e-8:return None
        return c+w*(f-c)+v*(i-c)
    for x,y,z,rad in pairs:
        lip=-z  # Native nose is -Z, nacelles are aft of origin.
        for dx,dy,blocked in ((0,rad*.34,False),(.95*rad,.006,True)):
            rays=(at(x+dx,y+dy,(poly[0],poly[i],poly[i+1]))
                  for poly,col in faces if col in (13,12,17,19) for i in range(1,len(poly)-1))
            hits=[p for p in rays if p is not None and lip-.001<=p<=lip+.035]
            assert bool(hits)==blocked,(x,dx,hits)
    for k in (17,18,19,20,21,22):
        assert sum(c==k for _,c in faces)>12


def shape():
    assert (ROOT/"art/stock_darwin_100.blend").stat().st_size>100_000
    assert not (CORE/"models"/f"{STEM}_flight.obj").exists()
    p,f=mesh(CORE/"models"/f"{STEM}.obj")
    png=(CORE/"textures"/f"{STEM}_atlas.png").read_bytes()
    assert png.startswith(b"\x89PNG\r\n\x1a\n") and struct.unpack(">IIBBBBB",png[16:29])==(256,8,8,2,0,0,0)
    low,high=[tuple(g(c) for c in zip(*p)) for g in (min,max)]
    assert low[1]==0 and .679<high[1]<.688
    assert 1.912<high[0]-low[0]<1.925
    assert -1.077<low[2]<-1.064 and 1.137<high[2]<1.147
    tires={(round(x,5),round(z,5)) for ps,c in f if c in (25,26) for x,y,z in ps if y==0}
    assert len(tires)==12 and {(x,z) for x,y,z in p if y==0}
    for x,z in ((-.243,.148),(.243,.148),(0,-.717)):
        for s in (-1,1):
            assert sum(0<s*(a-x)<.045 and abs(b-z)<1e-5 for a,b in tires)==2
    assert {c for _,c in f}>=set(range(30))-{5}
    bore_test(f)
    print(f"PASS shape W/H/L = {high[0]-low[0]:.5f}/{high[1]:.5f}/{high[2]-low[2]:.5f}; one invariant exterior, six exact tread tires, three hollow jet intakes.")
    return tires


def source(eq):
    if eq.engines:
        b=eq.engines.read_bytes()
        assert sha256(b).hexdigest()==ENGINE_SHA
        s=b.decode()
        assert re.search(r"MA\(\s*15461,\s*20,\s*25,\s*25,[^\n]*//\s*226 Darwin 100",s)
        assert re.search(r"AVI\(\s*2,\s*18,\s*240,\s*J,\s*SND_09_TAKEOFF_JET,\s*40,\s*74,\s*35,\s*170\s*\),\s*//\s*11 Darwin 100",s)
        assert "#define J AIR_CTOL | AIR_FAST" in s
        print("PASS pinned 16.0-RC1 engine catalog: engine 226, fast CTOL, row 11, 170 passengers and 35 mail.")
    if eq.aircraft:
        b=eq.aircraft.read_bytes()
        assert sha256(b).hexdigest()==AIRCRAFT_SHA
        s=b.decode()
        sprites=re.search(r"_aircraft_sprite\[\]\s*=\s*{([^}]+)}",s).group(1)
        assert [int(p,0) for p in sprites.split(",") if p.strip()][2]==3781
        fn=s.split("void Aircraft::GetImage(",1)[1].split("void GetRotorImage(",1)[0]
        assert "result->Set(to_underlying(direction) + _aircraft_sprite[spritenum]);" in fn
        assert not any(k in fn for k in ("this->state","this->z_pos","this->cargo"))
        assert "avi->subtype & AIR_FAST" in s and "Flag::ShortStrip" in s
        print("PASS pinned 16.0-RC1 sprite source: image 2 = 3781; silhouette invariant across flight phase.")


def city_source(eq,tires):
    b=eq.city_movement.read_bytes()
    assert sha256(b).hexdigest()==MOVE_SHA
    s=b.decode().split("_airport_moving_data_city[]",1)[1].split("};",1)[0]
    rows=[(int(x),int(z),d) for x,z,d in re.findall(r"{\s*(-?\d+),\s*(-?\d+),.*?Direction::([A-Z]+)",s)]
    assert len(rows)==30,rows
    assert rows[:5]==[(85,3,"SE"),(85,22,"N"),(26,41,"SW"),(56,22,"SE"),(38,8,"SW")]
    b=eq.city_layout.read_bytes()
    assert sha256(b).hexdigest()==LAYOUT_SHA
    s=b.decode().split("_tile_table_city_0 =",1)[1].split("};",1)[0]
    tiles={(int(x),int(z)):t for x,z,t in re.findall(r"\{\s*\{\s*(\d+),\s*(\d+)\s*\}\s*,\s*(\w+)\s*\}",s)}
    assert len(tiles)==36 and all("RUNWAY" in tiles[x,5] for x in range(6))
    assert tiles[5,0]=="APT_DEPOT_SE" and "STAND" in tiles[2,0]
    runway=[]
    for begin,end in ((10,11),(14,15)):
        assert rows[begin][1]==rows[end][1]
        for t in range(rows[end][0],rows[begin][0]+1):
            for tx,tz in tires:
                x,z=t/8-.5+tz,rows[begin][1]/8-.5-tx
                if -.5<=x<=11.5:
                    assert 9.5<z<11.5
                    runway.append((x,z))
    low=min(min(z-9.5,11.5-z) for x,z in runway)
    assert len(runway)>1600 and low>.32
    print(f"PASS City source runway tiles: {len(runway):,} tire contact samples on full 6-tile runway, worst tile-margin {low:.5f} nodes.")
    return runway


def city_ground_art(eq,runway):
    # Consumes the independently ported/native motion recorder's rows.
    base=Path(os.getenv("LUANTTD_BASE",str(ROOT)))
    sys.path.insert(0,str(base/"tests"))
    import small_airport_art as a
    group={}
    for z in range(6):
        for x in range(6):
            _,g=a.obj(eq.city_model_dir/f"{eq.city_prefix}{x}_{z}.obj",(x,z))
            for name,faces in g.items():group.setdefault(name,[]).extend(faces)
    if runway:
        wearing=group["Continuous_City_runway_wearing_course"]
        assert len(wearing)>=12 and all(abs(y-.010)<.000006 for f in wearing for x,y,z in f)
        footprints=[a.hull((x,z) for x,y,z in f) for f in wearing]
        missing=[(x,z) for x,z in runway if not any(a.intersects([(x,z)],poly) for poly in footprints)]
        assert not missing,("City runway wearing course",len(missing),missing[:10])
        lo=min(z for f in footprints for x,z in f)
        hi=max(z for f in footprints for x,z in f)
        actual_margin=min(min(z-lo,hi-z) for x,z in runway)
        print(f"PASS real City runway mesh: all {len(runway):,} tire footprints, minimum {actual_margin:.5f} horizontal margin.")

    # Height-sliced conservative envelope avoids false collisions between
    # wings and low footings.
    ac_faces=[poly for poly,_ in mesh(CORE/"models"/f"{STEM}.obj")[1]]
    outside=[(name,f) for name,faces in group.items() for f in faces if max(p[1] for p in f)>.028]
    slabs=[]
    split=[.028,.05,.07,.09,.11,.13,.15,.17,.19,.21,.23,.25,.27,.29,.31,.33,.36,.39,.43,.47,.52,.58,.63,.69]
    for begin,end in zip(split,split[1:]):
        candidates=[]
        for name,f in outside:
            if min(t[1] for t in f)>end or max(t[1] for t in f)<begin:continue
            q=a.cut(a.cut(list(f),1,begin,1),1,end,-1)
            if len(q)<2:continue
            pol=a.hull((x,z) for x,y,z in q)
            candidates.append((name,min(x for x,z in pol),max(x for x,z in pol),
                              min(z for x,z in pol),max(z for x,z in pol),pol))
        footprint=a.hull((x,z) for f in ac_faces for x,y,z in
                        a.cut(a.cut(list(f),1,begin,1),1,end,-1))
        if len(footprint)>2:
            slabs.append((begin,end,footprint,max(hypot(x,z) for x,z in footprint),candidates))
    poses=set()
    last={}
    for row in eq.city_ground_poses.read_text().splitlines():
        leg,u,v,h,d,mark,field,hidden=map(int,row.split())
        if h!=0:
            last.pop((leg,field),None)
            continue
        x,z=u/8-.5,v/8-.5
        poses.add((x,z,d))
        if (leg,field) in last:
            px,pz,pd=last[leg,field]
            if abs(x-px)+abs(z-pz)<.51:
                dd=(d-pd+4)%8-4
                for t in (.25,.50,.75):
                    poses.add((px+t*(x-px),pz+t*(z-pz),pd+t*dd))
        last[leg,field]=(x,z,d)
    assert len(poses)>80
    hits=set()
    for begin,end,wings,largest,polygons in slabs:
        for x,z,d in poses:
            fp=a.plane_mv(wings,x,z,-(d-7)*pi/4)
            for name,ax,bx,az,bz,poly in polygons:
                if ax>x+largest or bx<x-largest or az>z+largest or bz<z-largest:continue
                if a.intersects(fp,poly):
                    hits.add((name,x,z,d,begin,end))
    details=Counter(k for k,*_ in hits)
    assert not hits,("City sliced-envelope clearance candidates",details,sorted(hits)[:12])
    print(f"PASS City art clearance: {len(poses):,} ground and eased intermediate poses across {len(slabs)} height slices against all 36 art tiles.")


if __name__=="__main__":
    p=argparse.ArgumentParser()
    for field in ("engines","aircraft","city-movement","city-layout","city-model-dir","city-ground-poses"):
        p.add_argument("--"+field,type=Path)
    p.add_argument("--city-prefix",default="bl_city_airport_")
    opt=p.parse_args()
    assert bool(opt.city_movement)==bool(opt.city_layout)
    assert bool(opt.city_model_dir)==bool(opt.city_ground_poses)
    tires=shape()
    source(opt)
    runway=city_source(opt,tires) if opt.city_movement else None
    if opt.city_model_dir:city_ground_art(opt,runway)
