#!/usr/bin/env python3
"""Verify RC1 catalog identity, shape and exact stock-lane clearance for #137/#143/#146."""
from argparse import ArgumentParser
from collections import Counter
from hashlib import sha1,sha256
from pathlib import Path
import os,re,sys

from PIL import Image

ROOT=Path(__file__).resolve().parents[1]
BASE=Path(os.environ.get("LUANTTD_BASE",ROOT)).resolve()
sys.path.insert(0,str(BASE/"tests"))
from coal_tipper_art import bounds,in_lane,turn_check
from balogh_goods_truck_art import freight_fits
from witcombe_wood_truck_art import data_table
import rail_wagon_art
import road_corner_art
import road_freight_stop_art
MODELS=ROOT/"mods/luanttd_core/models"
S=.42
M="stock_moreland_wood_truck"
G="stock_goss_grain_truck"
F="stock_foster_livestock_van"
AX={M:(-.535,.264,.536),G:(-.485,.459),F:(-.491,.451)}
STOCK={M:(146,30,41,3540,48,24,"Moreland Wood Truck"),
       G:(143,27,40,3532,48,30,"Goss Grain Truck"),F:(137,21,38,3508,0,18,"Foster Livestock Van")}

def source(e,r):
    if e:
        raw=e.read_bytes()
        assert sha1(f"blob {len(raw)}\0".encode()+raw).hexdigest()=="1f71919c2399ebe7053cd78a306a96fb59e25def"
        a=e.read_text()
        for i,row,img,_,_,size,n in STOCK.values():
            assert re.search(rf"MR\([^\n]*// {i} {n}",a)
            p=next(l for l in a.splitlines() if re.search(rf"// {row} {n}$",l))
            assert re.search(rf"ROV\(\s*{img},\s*\d+,\s*240,\s*SND_19_DEPARTURE_OLD_RV_1,\s*224,\s*{size},",p)
    if r:
        text=r.read_text()
        image=data_table(text,"_roadveh_images")
        full=data_table(text,"_roadveh_full_adder")
        for _,_,img,sprite,adder,_,_ in STOCK.values():
            assert image[img]==sprite and full[img]==adder
        assert "cargo.StoredCount() >= this->cargo_cap / 2U" in text

def parse(stem):
    def ff(p):return tuple(map(float,p))
    v=[];n=[];uv=[];g={}
    for ln in (MODELS/f"bl_{stem}.obj").read_text().splitlines():
        t,*p=ln.split()
        if t=="v":v.append(ff(p))
        elif t=="vn":n.append(ff(p))
        elif t=="vt":
            u,v0=ff(p);c=round(64*u-.5)
            assert abs(64*u-.5-c)<.00005 and 0<=c<64 and v0==.5
            uv.append(c)
        elif t=="o":
            k=p[0];assert k not in g;g[k]=set()
        elif t=="f":
            a=[tuple(map(int,w.split("/"))) for w in p]
            assert len(a)==3 and all(0<i<=len(v) and 0<j<=len(uv) and 0<l<=len(n) for i,j,l in a)
            f=tuple(sorted((v[i-1],uv[j-1],n[l-1]) for i,j,l in a))
            assert len({q[0] for q in f})==3 and f not in g[k],k
            g[k].add(f)
    assert len(uv)==64
    return g

def ext(g):
    return bounds([(x*S,h*S,z*S) for pts in g.values() for x,z,h in pts])

def manifold(f):
    s=Counter()
    for a,b,c in ([v for v,_,_ in xyz] for xyz in f):
        s.update(tuple(sorted(p)) for p in ((a,b),(b,c),(a,c)))
    assert set(s.values())=={2}

def crosses_yz(f,y,z):
    a,b,c=[tuple(t*.1 for t in v) for v,_,_ in f]
    if max(t[1] for t in (a,b,c))<y or min(t[1] for t in (a,b,c))>y:return False
    if max(t[2] for t in (a,b,c))<z or min(t[2] for t in (a,b,c))>z:return False
    ua,ub,pa=a[1]-c[1],b[1]-c[1],y-c[1]
    va,vb,pb=a[2]-c[2],b[2]-c[2],z-c[2]
    d=ua*vb-ub*va
    if abs(d)<1.e-12:return False
    u=(pa*vb-pb*ub)/d;v=(pb*ua-pa*va)/d
    return u>=0 and v>=0 and u+v<=1

def check(k):
    f=parse(k);g=rail_wagon_art.mesh(k)
    shape=ext(g)
    in_lane(*shape);turn_check(*shape)
    assert min(z for _,z,_ in g["Two_separate_broad_windscreen_panes"])<-.72
    assert min(z for _,z,_ in g["One_ruby_rear_lens_each_side"])>.77
    for l,s in (("L",-1),("R",1)):
        pts=g[f"Ground_contact_tyre_{l}"]
        assert min(h for _,_,h in pts)==0
        t=[(x,z) for x,z,h in pts if h==0]
        assert len(t)==len(AX[k])*2
        assert {round(z,6) for x,z in t}==set(AX[k])
        for z in AX[k]:
            xs=[x for x,a in t if abs(a-z)<1.e-6]
            assert abs(sum(xs)/len(xs)-s*.218)<1.e-6
    atlas=Image.open(ROOT/"mods/luanttd_core/textures"/f"bl_{k}_atlas.png")
    assert atlas.mode=="RGB" and atlas.size==(1024,16)
    assert len({atlas.getpixel((i*16+8,8)) for i in range(64)})>=60
    assert (ROOT/"art"/f"{k}.blend").stat().st_size>125000
    shapes=[g]
    if k==F:
        assert not (MODELS/f"bl_{k}_loaded.obj").exists()
        slots=[v for v in f if v.startswith("Real_slot_slat_")]
        assert len(slots)==24
        for p in slots:manifold(f[p])
        for z in (-.197,-.011,.176,.363,.550,.682):
            for y in (.416,.474,.524,.585):
                assert not [name for name,fs in f.items() if any(crosses_yz(q,y,z) for q in fs)],(y,z)
            for y in (.448,.561):assert any(crosses_yz(q,y,z) for name in slots for q in f[name])
        for s in (-1,1):
            assert any(x*s>.15 and h<.345 and z>.74 for x,z,h in g["Tail_ramp_silver_double_wall_pivot_bars"])
        assert min(h for _,_,h in g["Two_separate_upper_cattle_access_hatch_door_wings"])>.5059
    else:
        lf=parse(k+"_loaded");load=rail_wagon_art.mesh(k+"_loaded")
        assert f.keys()<lf.keys() and all(lf[n]==v for n,v in f.items())
        assert shape==ext(load)
        shapes.append(load)
        new={p:lf[p] for p in lf.keys()-f.keys()}
        if k==M:
            for pre in ("Tapered_timber_bark_","Distinct_sawn_timber_growth_rings_","Sapwood_cut_core_"):
                part=[n for n in new if n.startswith(pre)]
                assert len(part)==20
                for j,(a,b) in enumerate(((-.208,.241),(.256,.747)),1):
                    pp=[n for n in part if f"_bundle_{j}_log_" in n]
                    assert len(pp)==10
                    assert all(a<z<b and abs(x)<.21 and .268<h<.647 for n in pp for x,z,h in load[n])
            assert sum(n.startswith("Actual_fitted_load_cinch_") for n in new)==4
        if k==G:
            bulk,vol,bottom,kernels=("Original_lofted_crown_of_golden_bulk_grain","Actual_grain_volume_below_surface","Bounded_bottom_face_of_grain_volume","Individual_scattered_raised_grain_kernels")
            assert set(new)=={bulk,vol,bottom,kernels}
            manifold(new[bulk]|new[vol]|new[bottom])
            assert len(new[bulk])==224 and len(new[kernels])==132*6
            assert all(abs(x)<.214 and -.309<z<.732 and .314<h<.594 for n in new for x,z,h in load[n])
            assert all(n[1]>.68 for face in new[bulk] for _,_,n in face)
            for name,interior in (("Tall_inward-facing_hopper_walls",True),("Pressed_exterior_silver_drop_side_panels",False)):
                assert all((v[0]*n[0]<0)==interior for face in f[name] for v,_,n in face)
    clear=[freight_fits(r) for r in shapes]
    lo,hi=shape
    print(f"{STOCK[k][0]} {k}: {tuple(round(b-a,4) for a,b in zip(lo,hi))} node dimensions; {clear} exact freight clearance poses.")

if __name__=="__main__":
    p=ArgumentParser()
    p.add_argument("--engines",type=Path)
    p.add_argument("--roadveh",type=Path)
    a=p.parse_args()
    source(a.engines,a.roadveh)
    rail_wagon_art.MODELS=MODELS
    road_freight_stop_art.ROOT=BASE
    for k in STOCK:check(k)
    road_corner_art.MODEL=MODELS
    road_corner_art.STEMS={n:S for n in (M,M+"_loaded",G,G+"_loaded",F)}
    road_corner_art.stock(road_corner_art.visual())
    print("STOCK_LATE_FREIGHT_ART_PASS")
