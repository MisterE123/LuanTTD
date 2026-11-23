#!/usr/bin/env python3
"""Exact airliner identity, four annular jets, grounded gear and real City clearance."""
from argparse import ArgumentParser,Namespace
from hashlib import sha1,sha256
from math import hypot
from pathlib import Path
import os,re,struct,sys
ROOT=Path(__file__).resolve().parents[1]
BASE=Path(os.environ.get("LUANTTD_BASE",str(ROOT))).resolve()
sys.path.insert(0,str(BASE/"tests"))
import darwin_100_art as d
import city_airport_art as city
MODELS=ROOT/"mods/luanttd_core/models"
ROWS={
  "bakewell_luckett_lb8":(220,5,6,3741,(18,240,30,200),"SND_09_TAKEOFF_JET","Bakewell Luckett LB-8",
        13695,23,25,((.294,.233,.133,.051),(.566,.015,.158,.046)),(.226,.155,.698),6),
  "darwin_300":(228,13,7,3749,(30,253,50,300),"SND_3D_TAKEOFF_JET_BIG","Darwin 300",
        17227,25,30,((.339,.238,.127,.071),(.666,-.030,.161,.065)),(.390,.195,.743),18)}

def source(a):
    if a.engines:
        raw=a.engines.read_bytes()
        assert sha256(raw).hexdigest()==d.ENGINE_SHA
        t=raw.decode()
        assert "#define J AIR_CTOL | AIR_FAST" in t
        for id,row,n,b,stats,sound,name,days,life,market,*_ in ROWS.values():
            price,cost,mail,pax=stats
            name=re.escape(name)
            assert re.search(rf"MA\(\s*{days},\s*20,\s*{life},\s*{market},\s*LandscapeTypes\(\{{T,A,S\s*\}}\)\),\s*//\s*{id} {name}",t)
            assert re.search(rf"AVI\(\s*{n},\s*{price},\s*{cost},\s*J,\s*{sound},\s*40,\s*74,\s*{mail},\s*{pax}\s*\),\s*//\s*{row} {name}",t)
    if a.aircraft:
        d.source(Namespace(engines=None,aircraft=a.aircraft))
        t=a.aircraft.read_text()
        arr=re.search(r"_aircraft_sprite\[\]\s*=\s*{([^}]+)}",t)[1]
        ids=[int(i,0) for i in arr.split(",") if i.strip()]
        assert all(ids[n]==b for _,_,n,b,*_ in ROWS.values())
    if a.opengfx:
        raw=a.opengfx.read_bytes()
        assert sha1(f"blob {len(raw)}\0".encode()+raw).hexdigest()=="e6ebd63046de845a05dc481c88ab7f4d2fce0208"
        t=raw.decode()
        assert 'spr3741(3741, "sprites/png/aircraft/BL-LB8-YateYAe46.png")' in t
        assert 'spr3749(3749, "sprites/png/aircraft/Darwin300.png")' in t

def ray(x,y,p):
    (a,b,c),(d,e,f),(g,h,i)=p
    u,v=d-a,e-b
    q,r=g-a,h-b
    k=u*r-v*q
    if abs(k)<1e-12:return None
    s=((x-a)*r-(y-b)*q)/k
    t=(u*(y-b)-v*(x-a))/k
    if min(s,t,1-s-t)<-1e-8:return None
    return c+s*(f-c)+t*(i-c)

def bore(fs,pods):
    for ax,lead,y,r0 in pods:
        lip=-lead;r=.88*r0
        for s in (-1,1):
            for dx,dy,wanted in ((0,.27*r,False),(.94*r,0,True)):
                found=any(k is not None and lip-.00003<=k<lip+.026 for p,c in fs if c in (12,13,17,19) for j in range(1,len(p)-1)
                      if (k:=ray(s*ax+dx,y+dy,(p[0],p[j],p[j+1]))) is not None)
                assert found==wanted,(ax,lead,y,dx,wanted)
    for tag in (17,18,19,20,21,22):assert sum(c==tag for _,c in fs)>15

def fit(stem,row):
    id,_,_,_,_,_,name,_,_,_,pods,_,count=row
    p=MODELS/f"bl_stock_{stem}.obj"
    assert not p.with_name(f"{p.stem}_flight.obj").exists()
    assert (ROOT/"art"/f"stock_{stem}.blend").stat().st_size>125000
    png=(ROOT/"mods/luanttd_core/textures"/f"{p.stem}_atlas.png").read_bytes()
    assert png.startswith(b"\x89PNG\r\n\x1a\n") and struct.unpack(">IIBBBBB",png[16:29])==(256,8,8,2,0,0,0)
    ps,fs=d.mesh(p)
    a,b=[tuple(fn(q) for q in zip(*ps)) for fn in (min,max)]
    assert a[1]==0 and a[2]<-1.00 and b[2]>.99
    assert 1.75<b[0]-a[0]<1.96 and b[1]<.706
    contacts={(round(x,5),round(z,5)) for face,c in fs if c in (25,26) for x,y,z in face if y==0}
    assert len(contacts)==count*2,(name,len(contacts),count)
    assert {(round(x,5),round(z,5)) for x,y,z in ps if y==0}==contacts
    roots=((- .228,.154),(.228,.154),(0,-.698)) if id==220 else (
        (-.390,.148),(-.390,.242),(.390,.148),(.390,.242),(-.164,.285),(-.164,.379),
        (.164,.285),(.164,.379),(0,-.743))
    for x,z in roots:
        for side in (-1,1):
            assert sum(0<side*(X-x)<.033 and abs(Z-z)<1e-5 for X,Z in contacts)==2,(x,z,contacts)
    bore(fs,pods)
    if id==228:
        upper={(x,z) for face,c in fs if c==8 for x,y,z in face if y>.407 and -.78<z<-.50}
        assert len(upper)>80
    print(f"#{id} {name}: W/H/L {tuple(round(y-x,5) for x,y in zip(a,b))}, {len(fs):,} faces, {count} runway tires and four open intake bores.")
    return p,contacts

def runway(model,contact,g,source):
    raw=source.read_bytes()
    assert sha256(raw).hexdigest()==d.MOVE_SHA
    z=raw.decode().split("_airport_moving_data_city[]",1)[1].split("};",1)[0]
    rows=[(int(x),int(z)) for x,z in re.findall(r"\{\s*(-?\d+),\s*(-?\d+),\s*\{",z)]
    assert len(rows)==30
    polys=[city.hull((x,z) for x,_,z in f) for f in g[city.RUNWAY]]
    low=min(z for f in polys for _,z in f);high=max(z for f in polys for _,z in f)
    points=[]
    for start,end in ((10,11),(14,15)):
        assert rows[start][1]==rows[end][1]
        for px in range(rows[end][0],rows[start][0]+1):
            for wx,wz in contact:
                x,z=px/8-.5+wz,rows[start][1]/8-.5-wx
                if -.5<=x<=11.5:
                    points.append((x,z))
    assert all(any(city.intersects([p],flat) for flat in polys) for p in points)
    margin=min(min(z-low,high-z) for _,z in points)
    assert margin>.15
    print(f"PASS {model.name}: {len(points):,} wheel samples on exact City runway surface, {margin:.5f} node minimum margin.")

if __name__=="__main__":
    p=ArgumentParser()
    for key in ("engines","aircraft","opengfx","city-layout","city-movement"):
        p.add_argument("--"+key,type=Path)
    p.add_argument("--only",choices=list(ROWS))
    a=p.parse_args();source(a)
    items=[(k,v) for k,v in ROWS.items() if not a.only or a.only==k]
    city.MODELS=BASE/"mods/luanttd_core/models"
    city.pins(a.city_layout,a.city_movement)
    g=city.models();poses=city.poses()
    for k,v in items:
        path,tires=fit(k,v)
        city.sweep(g,path,1.,poses)
        if a.city_movement:runway(path,tires,g,a.city_movement)
    print("STOCK_AIRLINERS_G_ART_PASS")
