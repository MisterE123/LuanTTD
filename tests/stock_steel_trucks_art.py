#!/usr/bin/env python3
"""RC1 stock sprite identity, independently verified annular steel and exact truck stop/lanes."""
from argparse import ArgumentParser
from hashlib import sha1
from math import cos,pi,sin,tau
from pathlib import Path
import os,re,sys
ROOT=Path(__file__).resolve().parents[1]
BASE=Path(os.getenv("LUANTTD_BASE",ROOT)).resolve()
sys.path.insert(0,str(BASE/"tests"))
import stock_late_freight_art as Q
MODELS=ROOT/"mods/luanttd_core/models"
INFO={
"stock_balogh_steel_truck":(150,34,9,3356,52,5479,55,112,90,96,15,38,12,"Balogh Steel Truck",(-.464,.432),(.214,.518,.441,.131)),
"stock_uhl_steel_truck":(151,35,26,3164,222,21185,55,135,168,176,18,48,22,"Uhl Steel Truck",(-.492,.466),(.182,.514,.447,.145)),
"stock_kelling_steel_truck":(152,36,43,3548,392,31777,85,145,240,224,20,69,45,"Kelling Steel Truck",(-.522,.258,.531),(.162,.513,.452,.153))}

def source(e,r,g):
    if e:
        raw=e.read_bytes()
        assert sha1(f"blob {len(raw)}\0".encode()+raw).hexdigest()=="1f71919c2399ebe7053cd78a306a96fb59e25def"
        t=raw.decode()
        for i,idx,img,spr,y,day,rel,cost,run,speed,cap,wt,hp,name,*_ in INFO.values():
            assert re.search(rf"MR\(\s*{day},\s*20,\s*15,\s*{rel},\s*CT_STEEL\s*,\s*LandscapeTypes\(\{{T\s*\}}\)\),\s*//\s*{i} {name}",t)
            assert re.search(rf"ROV\(\s*{img},\s*{cost},\s*{run},\s*SND_19_DEPARTURE_OLD_RV_1,\s*{speed},\s*{cap},\s*{wt},\s*{hp}\),\s*//\s*{idx} {name}",t)
    if r:
        s=r.read_text()
        sprites=Q.data_table(s,"_roadveh_images");adds=Q.data_table(s,"_roadveh_full_adder")
        for i,idx,img,sprite,*_ in INFO.values():assert sprites[img]==sprite and adds[img]==48
        assert "cargo.StoredCount() >= this->cargo_cap / 2U" in s
    if g:
        t=g.read_text()
        for i,idx,img,s,y,*_ in INFO.values():
            for sp,yy in ((s,y),(s+48,y+64)):
                assert re.search(rf'spr{sp}\({sp}, "sprites/png/roadvehicles/flatbeds.png"\)\s*\{{\s*tmpl_roadvehicles\(0,{yy}\)',t)
def coil_ray(f,y,z):
    for face in f:
        p,q,r=[tuple(c*.10 for c in v) for v,_,_ in face]
        a,b,c,d=q[1]-p[1],r[1]-p[1],q[2]-p[2],r[2]-p[2]
        det=a*d-b*c
        if abs(det)<1e-12:continue
        u=((y-p[1])*d-(z-p[2])*b)/det
        v=((z-p[2])*a-(y-p[1])*c)/det
        if min(u,v,1-u-v)>=-1.e-8:return True
    return False

def verify(k):
    d=INFO[k];ax=d[-2]
    a,b,h,r=d[-1]
    empty,loaded=(Q.rail_wagon_art.mesh(k+s) for s in ("","_loaded"))
    f,g=(Q.parse(k+s) for s in ("","_loaded"))
    assert f.keys()<g.keys() and all(g[n]==p for n,p in f.items())
    ext=Q.ext(empty)
    assert Q.ext(loaded)==ext
    lo,hi=ext
    Q.in_lane(lo,hi);Q.turn_check(lo,hi)
    for s,side in ((-1,"L"),(1,"R")):
        t=empty["Ground_contact_tyre_"+side]
        pts=[(x,z) for x,z,h in t if h==0]
        assert min(h for _,_,h in t)==0 and len(pts)==2*len(ax)
        assert {round(z,6) for x,z in pts}==set(ax)
        assert abs(sum(x for x,z in pts)/len(pts)-s*.218)<1.e-6
    assert len(f["Individually_sawn_exposed_longitudinal_timber_flatbed_slats"])==8*28
    assert all(z>.77 for _,z,_ in empty["One_ruby_rear_lens_each_side"])
    if d[0]==150:
        assert all(z<-.78 for _,z,_ in empty["Short_warm_opaque_Balogh_headlight_neck_lenses"])
        assert max(z for _,z,_ in empty["Balogh_independent_pressed_vintage_hood"])<-.53
    else:
        p=empty["Independent_source-style_twin_windshield_glass_panes"]
        assert min(z for _,z,_ in p)<-.66 and (max(z for _,z,_ in p)>-.58)==(d[0]==151)
    for j,zz,yy,R in ((1,a,h,r),(2,b,h-.006,r-.004)):
        name=f"Closed_annular_rolled_sheet_steel_load_Coil_{j}"
        Q.manifold(g[name])
        assert len(g[name])==8*36*2
        assert not coil_ray(g[name],yy,zz),"Core must be open and not painted"
        assert coil_ray(g[name],yy+.7*R,zz),"Metal surrounds opening"
        assert not coil_ray(g[name],yy+R+.003,zz)
        xx,z,h0=zip(*loaded[name])
        assert max(map(abs,xx))<.106
        assert .29<min(h0)<.331 and max(h0)<.61
        assert zz-R<min(z)<max(z)<zz+R
        assert len(g[f"Separate_concentric_steel_sheet_rolled_ring_ends_Coil_{j}"])==8*36*2*2
        for s in ("rear","front"):
            straps=loaded[f"Real_tied_down_{s}_strap_through_the_eye_Coil_{j}"]
            assert min(y for _,_,y in straps)<.31 and max(x for x,_,_ in straps)>.16 and min(x for x,_,_ in straps)<-.16
    png=Q.Image.open(ROOT/"mods/luanttd_core/textures"/f"bl_{k}_atlas.png")
    assert png.mode=="RGB" and png.size==(1024,16)
    assert (ROOT/"art"/f"{k}.blend").stat().st_size>130000
    assert sum(map(len,g.values()))-sum(map(len,f.values()))>3000
    print(f"#{d[0]} {d[-3]}: {tuple(round(b-a,4) for a,b in zip(lo,hi))} node dimensions; two true steel coils.")
    print(f"Freight stop/fence clear exact poses: {Q.freight_fits(empty)} empty, {Q.freight_fits(loaded)} loaded")

if __name__=="__main__":
    p=ArgumentParser()
    p.add_argument("--engines",type=Path);p.add_argument("--roadveh",type=Path)
    p.add_argument("--opengfx",type=Path);p.add_argument("--only",choices=list(INFO))
    a=p.parse_args();source(a.engines,a.roadveh,a.opengfx)
    Q.MODELS=Q.rail_wagon_art.MODELS=MODELS
    Q.road_freight_stop_art.ROOT=BASE
    names=[n for n in INFO if not a.only or a.only==n]
    for k in names:verify(k)
    Q.road_corner_art.MODEL=MODELS
    Q.road_corner_art.STEMS={k+s:.42 for k in names for s in ("","_loaded")}
    Q.road_corner_art.stock(Q.road_corner_art.visual())
    print("STOCK_STEEL_TRUCKS_ART_PASS")
