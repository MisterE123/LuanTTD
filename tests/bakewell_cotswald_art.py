#!/usr/bin/env python3
"""Validate both native LB-3 exports and all stock Country Airport ground poses."""
from collections import Counter
from math import hypot, pi
from pathlib import Path
import re
import struct
import sys
import zlib

import small_airport_art as airport
from air_paid_upstream import read as pinned_read

ROOT = Path(__file__).resolve().parents[1]
STEM = "bl_bakewell_cotswald"


def read_obj(suffix):
    p = ROOT / "mods/luanttd_core/models" / f"{STEM}{suffix}.obj"
    points, palette, faces = [], [], []
    for line in p.read_text().splitlines():
        tag, *values = line.split()
        if tag == "v":
            x,y,z = (float(n)/10 for n in values)
            points.append((-x,y,z))
        elif tag == "vt":
            u,v = map(float,values)
            assert 0 <= u < 1 and v == .5
            palette.append(int(u*32))
        elif tag == "f":
            ids = [tuple(map(int,a.split("/")[:2])) for a in values]
            ink = {palette[j-1] for _,j in ids}
            assert 3 <= len(ids) <= 20 and len(ink)==1
            faces.append((tuple(sorted(points[i-1] for i,_ in ids)),ink.pop()))
    return p,points,faces


def main():
    png=ROOT/"mods/luanttd_core/textures"/f"{STEM}_atlas.png"
    assert struct.unpack(">II",png.read_bytes()[16:24]) == (256,8)
    d,p,down = read_obj("")
    u,q,up = read_obj("_flight")
    count = sum(len(zlib.compress(x.read_bytes(),9)) for x in (d,u,png))
    assert count < 98_000, count
    assert len(down) < 3400 and len(up) < 3400
    assert abs(min(y for _,y,_ in p)) < .00001
    assert .06 < min(y for _,y,_ in q) < .10
    height=max(y for _,y,_ in p)
    assert .624 < height < .634
    assert -0.686 < min(z for _,_,z in p)<-.679 and .732<max(z for _,_,z in p)<.738
    assert .937<max(x for x,_,_ in p)<.944
    for k in (0,2):
        assert min(a[k] for a in p)==min(a[k] for a in q)
        assert max(a[k] for a in p)==max(a[k] for a in q)
    assert max(y for _,y,_ in q)==height
    touches = {(round(x,5),round(z,5)) for f,ink in down if ink==21
               for x,y,z in f if abs(y)<.00001}
    for x,z in ((0,.615),(-.322,-.159),(.322,-.159)):
        for side in (-1,1):
            assert any(side*(a-x)>.008 and abs(b-z)<.00001 for a,b in touches),(x,z,touches)
    assert len(touches)==6
    assert not any(t in (20,21,22,23) for _,t in up)
    common=Counter(down)&Counter(up)
    assert sum(common.values()) > 1250
    assert set(m for _,m in Counter(down)-common) <= {3,20,21,22,23,27}
    assert set(m for _,m in Counter(up)-common) <= {2}
    tips={x for face,ink in down if ink==19 for x,y,z in face}
    assert any(x<-.25 for x in tips) and any(x>.25 for x in tips)
    if len(sys.argv)>1:
        src=pinned_read(Path(sys.argv[1]),"engines.h")
        assert re.search(r"MA\(\s*4929,\s*20,\s*30,\s*30,\s*T\|A\|S\s*\).*// 219 Bakewell Cotswald LB-3",src)
        assert re.search(r"AVI\(\s*5,\s*15,\s*98,\s*P,\s*SND_08_TAKEOFF_PROPELLER,\s*20,\s*37,\s*6,\s*30\s*\).*//\s+4 Bakewell Cotswald LB-3",src)

    shape=airport.hull((x,z) for x,y,z in p)
    radius=max(hypot(*v) for v in shape)
    polygons=[]
    for name,faces in airport.footprint().items():
        for f in faces:
            if max(v[1] for v in f)<=airport.GROUND: continue
            part=airport.cut(airport.cut(f,1,airport.GROUND,1),1,height+.015,-1)
            if not part: continue
            a,b=min(v[0] for v in part),max(v[0] for v in part)
            c,d=min(v[2] for v in part),max(v[2] for v in part)
            polygons.append((name,a,b,c,d,airport.hull((x,z) for x,y,z in part)))
    # Row #4, stock acceleration 20 and same speed parameter 37 as Sampson.
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
        swept=airport.plane_mv(shape,x,z,-(d-7)*pi/4)
        for name,a,b,c,e,mesh in polygons:
            if a>x+radius or b<x-radius or c>z+radius or e<z-radius: continue
            assert not airport.intersects(swept,mesh),(name,x,z,d)
    print(f"PASS: LB-3 contact for twin mainwheels and tailwheel; {len(poses)} stock ground poses; compressed runtime {count} bytes")


if __name__=="__main__":
    main()
