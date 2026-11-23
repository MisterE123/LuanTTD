#!/usr/bin/env python3
"""Pinned RC1 sprite identity, real cargo containment and stock road running clearance."""
from argparse import ArgumentParser
from hashlib import sha1
from pathlib import Path
import os,re,sys

ROOT=Path(__file__).resolve().parents[1]
BASE=Path(os.getenv("LUANTTD_BASE",ROOT)).resolve()
sys.path.insert(0,str(BASE/"tests"))
import stock_late_freight_art as Q

GOODS="stock_goss_goods_truck"
COAL="stock_dw_coal_truck"
OIL="stock_perry_oil_tanker"
MODELS=ROOT/"mods/luanttd_core/models"
STOCK={GOODS:(140,24,39,3516,0,18,"Goss Goods Truck","CT_GOODS"),
       COAL:(125,9,35,3484,88,28,"DW Coal Truck","CT_COAL"),
       OIL:(134,18,37,3500,0,27,"Perry Oil Tanker","CT_OIL")}
AX={GOODS:(-.500,.464),COAL:(-.509,.268,.538),OIL:(-.493,.470)}

def cat(e,r,n):
    if e:
        raw=e.read_bytes()
        assert sha1(f"blob {len(raw)}\0".encode()+raw).hexdigest()=="1f71919c2399ebe7053cd78a306a96fb59e25def"
        a=raw.decode()
        for ident,row,img,_,_,capacity,name,cargo in STOCK.values():
            assert re.search(rf"MR\([^\n]*\b{cargo}\b[^\n]*//\s*{ident} {name}",a)
            line=next(x for x in a.splitlines() if re.search(rf"//\s*{row} {name}$",x))
            assert re.search(rf"ROV\(\s*{img},\s*\d+,\s*240,\s*SND_19_DEPARTURE_OLD_RV_1,\s*224,\s*{capacity},",line)
    if r:
        a=r.read_text()
        s,f=(Q.data_table(a,i) for i in ("_roadveh_images","_roadveh_full_adder"))
        for _,_,img,sprite,adder,*extra in STOCK.values():
            assert s[img]==sprite and f[img]==adder
        assert "cargo.StoredCount() >= this->cargo_cap / 2U" in a
    if n:
        t=n.read_text()
        for sprite,x,y in ((3516,594,552),(3484,370,520),(3572,82,648),(3500,82,552)):
            assert re.search(rf'spr{sprite}\({sprite}, "sprites/png/roadvehicles/vehiclesroad01.png"\)\s*\{{\s*\[\s*{x},\s*{y},',t)

def verify(name):
    Q.MODELS=Q.rail_wagon_art.MODELS=MODELS
    g=Q.rail_wagon_art.mesh(name)
    f=Q.parse(name)
    lo,hi=Q.ext(g)
    Q.in_lane(lo,hi)
    Q.turn_check(lo,hi)
    assert max(hi[0],-lo[0])<.130
    for side,tag in ((-1,"L"),(1,"R")):
        wheel=g["Ground_contact_tyre_"+tag]
        t=[(x,z) for x,z,h in wheel if h==0]
        assert min(h for _,_,h in wheel)==0
        assert {round(z,6) for x,z in t}==set(AX[name]) and len(t)==2*len(AX[name])
        assert abs(sum(x for x,z in t)/len(t)-side*.218)<1e-6
    assert min(z for _,z,_ in g["Two_separate_broad_windscreen_panes"])<-.73
    assert min(z for _,z,_ in g["One_ruby_rear_lens_each_side"])>.77
    im=Q.Image.open(ROOT/"mods/luanttd_core/textures"/f"bl_{name}_atlas.png")
    assert im.mode=="RGB" and im.size==(1024,16)
    assert len({im.getpixel((i*16+8,8)) for i in range(64)})>=60
    assert (ROOT/"art"/f"{name}.blend").stat().st_size>125000
    if name==GOODS:
        assert not (MODELS/f"bl_{name}_loaded.obj").exists()
        assert len(f["Blue_outer_long_vertical_goods-body_ribs"])>340
        assert max(z for _,z,_ in g["Folded_rear_deck_tread_with_slip-resistant_edge"])>.80
        assert max(h for _,_,h in g["Independent_hinged_pressed_rear_cargo_door_leaves"])>.60
    if name==OIL:
        assert not (MODELS/f"bl_{name}_loaded.obj").exists()
        Q.manifold(f["Pressure_tanker_rolled_welded_barrel_and_domed_ends"]|f["True_sealed_closure_pressure_plates"])
        assert min(h for _,_,h in g["Capped_chrome_refilling_hatch"])>.67
        assert len(f["Full_wrap_silver_tank_strap_locking_hoop"])==28*4*2
        assert max(z for _,z,_ in g["Capped_discharge_service_ports"])>.779
    eq=[g]
    if name==COAL:
        gf=Q.rail_wagon_art.mesh(name+"_loaded")
        lf=Q.parse(name+"_loaded")
        eq.append(gf)
        assert Q.ext(gf)==(lo,hi)
        assert f.keys()<lf.keys() and all(lf[n]==tris for n,tris in f.items())
        surface="Actual_faceted_black_coal_mound_surface"
        volume="Closed_faceted_coal_cargo_vertical_boundary"
        bottom="Coal_bulk_bottom_makes_closed_full_volume"
        chunks="Individual_modelled_angular_coal_granules"
        added=lf.keys()-f.keys()
        assert added=={surface,volume,bottom,chunks}
        Q.manifold(lf[surface]|lf[volume]|lf[bottom])
        assert len(lf[surface])==280 and len(lf[chunks])==154*6
        assert all(abs(x)<.218 and -.310<z<.735 and .322<h<.612 for n in added for x,z,h in gf[n])
        assert all(n[1]>.50 for tri in lf[surface] for _,_,n in tri)
    count=sum(map(len,f.values()))
    print(f"{name}: x/y/z dims {tuple(round(y-x,4) for x,y in zip(lo,hi))}; {count} empty triangles; freight passes {[Q.freight_fits(k) for k in eq]}.")

if __name__=="__main__":
    p=ArgumentParser()
    p.add_argument("--engines",type=Path)
    p.add_argument("--roadveh",type=Path)
    p.add_argument("--opengfx",type=Path)
    a=p.parse_args()
    cat(a.engines,a.roadveh,a.opengfx)
    Q.road_freight_stop_art.ROOT=BASE
    for name in STOCK:verify(name)
    Q.road_corner_art.MODEL=MODELS
    Q.road_corner_art.STEMS={k:.42 for k in (GOODS,COAL,COAL+"_loaded",OIL)}
    Q.road_corner_art.stock(Q.road_corner_art.visual())
    print("STOCK_LATE_INDUSTRY_ART_PASS")
