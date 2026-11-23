#!/usr/bin/env python3
"""Pinned supersonic airframe, unblocked intakes and native ground/flight envelope."""
import argparse
from pathlib import Path
import re
import struct
from darwin_100_art import ROOT, CORE, mesh, city_ground_art, city_source

def projection(x,y,tri):
    (a,b,c),(d,e,f),(g,h,i)=tri
    ux,uy=d-a,e-b
    vx,vy=g-a,h-b
    det=ux*vy-uy*vx
    if abs(det)<1e-12:return None
    w=((x-a)*vy-(y-b)*vx)/det
    v=(ux*(y-b)-uy*(x-a))/det
    if min(w,v,1-w-v)<-1e-8:return None
    return c+w*(f-c)+v*(i-c)

if __name__=="__main__":
    p=argparse.ArgumentParser()
    for k in ("engines","aircraft","city-movement","city-layout","city-model-dir","city-ground-poses"):
        p.add_argument("--"+k,type=Path)
    p.add_argument("--city-prefix",default="bl_city_airport_")
    opt=p.parse_args()
    if opt.engines:
        s=opt.engines.read_text()
        assert re.search(r"MA\(\s*17652,\s*20,\s*25,\s*35,\s*LandscapeTypes\(\{T,A,S\s*\}\)\),\s*//\s*218 Yate Haugan",s)
        assert re.search(r"AVI\(\s*8,\s*75,\s*250,\s*J,\s*SND_3B_TAKEOFF_JET_FAST,\s*50,\s*181,\s*20,\s*100\s*\),\s*//\s*3 Yate Haugan",s)
    path=CORE/"models/bl_stock_yate_haugan.obj"
    pts,faces=mesh(path)
    fly,air=mesh(CORE/"models/bl_stock_yate_haugan_flight.obj")
    assert (ROOT/"art/stock_yate_haugan.blend").stat().st_size>120000
    png=(CORE/"textures/bl_stock_yate_haugan_atlas.png").read_bytes()
    assert struct.unpack(">IIBBBBB",png[16:29])==(256,8,8,2,0,0,0)
    tires={(x,z) for t,c in faces for x,y,z in t if c in (25,26) and y==0}
    assert len(tires)==20 and {(x,z) for x,y,z in pts if y==0}==tires
    assert min(y for _,y,_ in fly)>.04 and not any(c in (25,26) for _,c in air)
    assert .48<max(y for _,y,_ in pts)<.70 and max(y for _,y,_ in pts)==max(y for _,y,_ in fly)
    assert max(x for x,_,_ in pts)<.72 and min(z for _,_,z in pts)<-1.05 and max(z for _,_,z in pts)<1.03
    a=min(pts,key=lambda t:t[2]);b=min(fly,key=lambda t:t[2])
    assert a[2]==b[2] and .043<b[1]-a[1]<.063,(a,b)
    for x in (-.218,-.136,.136,.218):
        inside=[]
        for poly,c in faces:
            for i in range(1,len(poly)-1):
                z=projection(x,.150,(poly[0],poly[i],poly[i+1]))
                if z is not None:inside.append(z)
        assert not any(-.098<z<-.010 for z in inside), (x,inside)
        assert any(.010<z<.023 for z in inside),(x,inside)
    if opt.city_model_dir:
        samples=city_source(opt,tires) if opt.city_movement else None
        city_ground_art(opt,samples,path)
    print("STOCK_HAUGAN_ART_PASS: exact #218 source, ten wheels, 4 open variable-ramp intakes, separate tucked gear and drooped nose")
