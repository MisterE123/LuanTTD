#!/usr/bin/env python3
"""Check Coleman #216 OBJ contact, true two gear states and stock airfield clearance."""
from collections import Counter
from math import hypot, isclose, pi
from pathlib import Path
import re
import struct
import sys

import small_airport_art as airport
from air_paid_upstream import read as pinned_read

ROOT=Path(__file__).resolve().parents[1]


def inspect(name):
    vertices,uv=[],[]
    meshes=[]
    for row in (ROOT/"mods/luanttd_core/models"/f"bl_{name}.obj").read_text().splitlines():
        fields=row.split()
        if not fields: continue
        tag,*a=fields
        if tag=="v":
            x,h,z=(float(t)/10 for t in a)
            vertices.append((-x,h,z))
        elif tag=="vt":
            u,v=map(float,a)
            ink=int(u*32)
            assert 0<=ink<32 and abs(u-(ink+.5)/32)<2e-7 and v==.5
            uv.append(ink)
        elif tag=="f":
            ids=[[int(n) for n in t.split("/")[:2]] for t in a]
            assert len(ids)==3 and len({uv[t-1] for _,t in ids})==1
            meshes.append((tuple(sorted(vertices[i-1] for i,_ in ids)),uv[ids[0][1]-1]))
    return vertices,meshes


def source(path):
    e=pinned_read(Path(path),"engines.h")
    assert re.search(r"MA\(\s*9922,\s*20,\s*24,\s*20,\s*T\|A\|S\s*\).*// 216 Coleman Count",e)
    assert re.search(r"AVI\(\s*0,\s*15,\s*100,\s*P,\s*SND_08_TAKEOFF_PROPELLER,\s*20,\s*37,\s*8,\s*65\s*\).*//\s+1 Coleman Count",e)
    assert re.search(r"MA\(\s*13695.*// 220 Bakewell Luckett LB-8",e)
    assert re.search(r"AVI\(\s*6,.*\bJ,.*//\s+5 Bakewell Luckett LB-8",e)


def main():
    atlas=(ROOT/"mods/luanttd_core/textures/bl_coleman_count_atlas.png").read_bytes()
    assert struct.unpack(">II",atlas[16:24])==(256,8)
    points,ground=inspect("coleman_count")
    up,flying=inspect("coleman_count_flight")
    shape=airport.hull((x,z) for x,y,z in points)
    radius=max(hypot(*p) for p in shape)
    assert max(abs(x) for x,y,z in points)>.946 and radius<.993
    height=max(p[1] for p in points)
    assert isclose(height,.681,abs_tol=2e-6)
    assert isclose(min(p[2] for p in points),-.777,abs_tol=.004)
    assert isclose(max(p[2] for p in points),.886,abs_tol=.006)
    assert isclose(min(p[1] for p in points),0,abs_tol=2e-7)
    assert .121 < min(y for x,y,z in up) < .130
    assert min(z for x,y,z in up)==min(z for x,y,z in points)
    assert max(z for x,y,z in up)==max(z for x,y,z in points)
    assert max(y for x,y,z in up)==height
    # Trust actual tyre vertices, not a metadata label or the base bbox.
    contacts=[p for face,ink in ground if ink==21 for p in face if abs(p[1])<1e-7]
    assert len({(round(x,6),round(z,6)) for x,y,z in contacts})==12
    for centre,long in ((-.326,.071),(.326,.071),(0,-.552)):
        assert any(x>.009+centre and abs(z-long)<1e-6 for x,y,z in contacts)
        assert any(x<centre-.009 and abs(z-long)<1e-6 for x,y,z in contacts)
    assert not any(c in (20,21,22,23) for _,c in flying)
    common=Counter(ground)&Counter(flying)
    assert 12000<sum(common.values())<17500
    assert set(c for _,c in Counter(ground)-common)<={3,4,13,20,21,22,23,24}
    assert set(c for _,c in Counter(flying)-common)<={3,24}
    tippts={p for face,index in ground if index==19 for p in face}
    assert all(.15<abs(x)<.81 for x,y,z in tippts)
    for x0,z0 in ((.326,-.395),(-.326,-.395),(.614,-.297),(-.614,-.297)):
        assert sum(abs(x-x0)<.16 and abs(z-z0)<.04 for x,y,z in tippts)>=30
    groups=airport.footprint()
    polygons=[]
    for name,faces in groups.items():
        for p in faces:
            if max(v[1] for v in p)<=airport.GROUND: continue
            clipped=airport.cut(airport.cut(p,1,airport.GROUND,1),1,height+.015,-1)
            if not clipped: continue
            a,b=min(v[0] for v in clipped),max(v[0] for v in clipped)
            d,e=min(v[2] for v in clipped),max(v[2] for v in clipped)
            polygons.append((name,a,b,d,e,airport.hull((x,z) for x,y,z in clipped)))
    # Reuse the source-stock movement test with Coleman acceleration = 20;
    # row #1 shares the exact speed factor (37*128/10) with #0.
    airport.TRACE=airport.TRACE.replace("acceleration=18","acceleration=20")
    old=None
    poses=set()
    for leg,px,pz,y,d,point,aid,hidden in airport.trace():
        if y!=0:
            old=None
            continue
        x,z=px/8-.5,pz/8-.5
        poses.add((x,z,d))
        if old and old[:2]==(leg,aid):
            ax,az,ad=old[2:]
            if abs(ax-px)+abs(az-pz)<=4:
                arc=(d-ad+4)%8-4
                for f in (.25,.5,.75):
                    poses.add((x+(ax-px)/8*(1-f),z+(az-pz)/8*(1-f),ad+arc*f))
        old=(leg,aid,px,pz,d)
    assert len(poses)>550
    for x,z,d in poses:
        transformed=airport.plane_mv(shape,x,z,-(d-7)*pi/4)
        for name,a,b,c,e,mesh in polygons:
            if a>x+radius or b<x-radius or c>z+radius or e<z-radius: continue
            assert not airport.intersects(transformed,mesh),(name,x,z,d)
    if len(sys.argv)>1: source(sys.argv[1])
    print(f"PASS: Coleman #216 four true propellers, six tire contact patches, shared flight skin, {len(poses)} real ported ground poses at both stands and hangar")


if __name__=="__main__":
    main()
