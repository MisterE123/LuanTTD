#!/usr/bin/env python3
"""FFP Dart and YAC 1-11 model, audited pinned source, and real City ground fixtures."""
import argparse
from datetime import date,timedelta
from hashlib import sha256
from pathlib import Path
import os,re,struct,sys,zlib
ROOT=Path(__file__).resolve().parents[1]
BASE=Path(os.environ.get("LUANTTD_BASE",str(ROOT))).resolve()
sys.path.insert(0,str(BASE/"tests"))
import darwin_100_art as d
import city_airport_art as city
MODELS=ROOT/"mods/luanttd_core/models"
TEXTURES=ROOT/"mods/luanttd_core/textures"

# Model, engine ID, AVI row, intro, model life, market life, running factor, PAX,
# approximate native span/height/length, wheel centers (-/+X, Z), intake aperture.
ROWS=(
 ("ffp_dart","FFP Dart",217,2,12659,18,20,130,90,(1.568,.535,1.702),(.182,.130,-.554),(.172,.237,.438,.063*.88)),
 ("yate_yac_1_11","Yate Aerospace YAC 1-11",225,10,15371,22,25,135,95,(1.534,.595,1.740),(.202,.162,-.543),(.184,.259,.475,.067*.88)),
)

def source(opt):
    if opt.engines:
        b=opt.engines.read_bytes()
        assert sha256(b).hexdigest()==d.ENGINE_SHA
        s=b.decode()
        for _,name,idx,row,day,life,market,running,pax,*_ in ROWS:
            assert re.search(rf"MA\(\s*{day},\s*20,\s*{life},\s*{market},\s*LandscapeTypes\(\{{T,A,S\s*\}}\)\),\s*//\s*{idx}\s+{name}\b",s)
            assert re.search(rf"AVI\(\s*2,\s*16,\s*{running},\s*J,\s*SND_09_TAKEOFF_JET,\s*35,\s*74,\s*10,\s*{pax}\s*\),\s*//\s*{row}\s+{name}\b",s)
            print(f"PASS #{idx} pinned MA/AVI source, J fast CTOL, {pax} passengers, {date(1920,1,1)+timedelta(day)}")
        assert "#define J AIR_CTOL | AIR_FAST" in s
    d.source(argparse.Namespace(engines=None,aircraft=opt.aircraft))

def bore(faces,pair):
    def hit(x,y,p):
        (a,b,c),(d,e,f),(g,h,i)=p
        u,v=d-a,e-b
        q,r=g-a,h-b
        det=u*r-v*q
        if abs(det)<1e-12:return None
        m=((x-a)*r-(y-b)*q)/det
        n=(u*(y-b)-v*(x-a))/det
        if min(m,n,1-m-n)<-1e-8:return None
        return c+m*(f-c)+n*(i-c)
    ax,y,z,r=pair
    for x in (-ax,ax):
        for dx,dy,wanted in ((0,r*.36,False),(.94*r,0,True)):
            found=[q for p,col in faces if col in (12,13,17,19) for j in range(1,len(p)-1)
                   if (q:=hit(x+dx,y+dy,(p[0],p[j],p[j+1]))) is not None and z-.00001<q<z+.037]
            assert bool(found)==wanted,(x,dx,found)
    for tag in (17,18,19,20,21,22):
        assert sum(c==tag for _,c in faces)>12

def shape(row):
    stem,name,idx,*_=row
    dims,attach,nt=row[-3:]
    p=MODELS/f"bl_stock_{stem}.obj"
    assert not p.with_name(f"{p.stem}_flight.obj").exists()
    blend=ROOT/"art"/f"stock_{stem}.blend"
    assert blend.stat().st_size>90_000
    png=(TEXTURES/f"{p.stem}_atlas.png").read_bytes()
    assert png.startswith(b"\x89PNG\r\n\x1a\n") and struct.unpack(">IIBBBBB",png[16:29])==(256,8,8,2,0,0,0)
    image=zlib.decompress(png[41:41+int.from_bytes(png[33:37],"big")])
    assert len(image)==8*(1+256*3) and len({image[1+i*24:4+i*24] for i in range(32)})==32
    vs,fs=d.mesh(p)
    a,b=[tuple(f(x) for x in zip(*vs)) for f in (min,max)]
    measured=(b[0]-a[0],b[1]-a[1],b[2]-a[2])
    assert all(abs(x-y)<.020 for x,y in zip(measured,dims)),(name,measured)
    assert a[1]==0 and a[2]<-.8 and b[2]>.88
    tires={(round(x,5),round(z,5)) for poly,col in fs if col in (25,26) for x,y,z in poly if y==0}
    assert len(tires)==12
    assert {(round(x,5),round(z,5)) for x,y,z in vs if y==0}==tires
    w,main,nose=attach
    for x,z in ((-w,main),(w,main),(0.,nose)):
        for s in (-1,1):
            assert sum(0<s*(a-x)<.033 and abs(z-b)<1e-5 for a,b in tires)==2
    bore(fs,nt)
    print(f"PASS #{idx} {name} W/H/L = " + "/".join(f"{x:.5f}" for x in measured)
          + f"; {len(vs):,} vertices, {len(fs):,} faces; 6 exact runway contact tires and 2 genuine open intakes")
    return p,tires

def full_city(args,data):
    # Upstream engines share exact taxi speed factors. Replay all three gates in
    # both directions using true FFP/Yate acceleration, stock motion and body art.
    city.MODELS=BASE/"mods/luanttd_core/models"
    city.TRACE=city.TRACE.replace("acceleration=40,max_speed=947","acceleration=35,max_speed=947")
    city.pins(args.city_layout,args.city_movement)
    g=city.models()
    poses=city.poses()
    for p,tires in data:
        city.sweep(g,p,1.,poses)
        if args.city_movement:
            xs=d.city_source(args,tires)
            parts=g[city.RUNWAY]
            outline=[city.hull((x,z) for x,_,z in f) for f in parts]
            assert all(any(city.intersects([(x,z)],f) for f in outline) for x,z in xs)
            lo=min(z for f in outline for _,z in f);hi=max(z for f in outline for _,z in f)
            m=min(min(z-lo,hi-z) for x,z in xs)
            print(f"PASS actual City wearing course supporting {len(xs):,} precise wheel samples for {p.name}, minimum {m:.5f} lateral margin")

if __name__=="__main__":
    parser=argparse.ArgumentParser()
    parser.add_argument("--city",action="store_true")
    for key in ("engines","aircraft","city-layout","city-movement"):
        parser.add_argument("--"+key,type=Path)
    args=parser.parse_args()
    assert bool(args.city_layout)==bool(args.city_movement)
    source(args)
    data=[shape(row) for row in ROWS]
    if args.city:full_city(args,data)
    print("STOCK_AIRLINERS_E_ART_PASS")
