#!/usr/bin/env python3
"""Pin the two RC1 stock mail slots and physically check both Blender exports."""
from argparse import ArgumentParser
from hashlib import sha1
from pathlib import Path
import os,re,sys

ROOT=Path(__file__).resolve().parents[1]
BASE=Path(os.getenv("LUANTTD_BASE",ROOT)).resolve()
sys.path.insert(0,str(BASE/"tests"))
import stock_late_freight_art as Q
MODEL=ROOT/"mods/luanttd_core/models"
STOCK={"stock_mps_mail_truck":(126,10,2,3300,22,96,"MPS Mail Truck",(-.472,.416),.205),
       "stock_perry_mail_truck":(128,12,36,3492,30,224,"Perry Mail Truck",(-.503,.454),.218)}

def sources(e,r,n):
    if e:
        raw=e.read_bytes()
        assert sha1(f"blob {len(raw)}\0".encode()+raw).hexdigest()=="1f71919c2399ebe7053cd78a306a96fb59e25def"
        a=raw.decode()
        for i,j,k,_,capacity,speed,name,_,_ in STOCK.values():
            assert re.search(rf"MR\([^\n]*\bCT_MAIL\b[^\n]*//\s*{i} {name}",a)
            row=next(x for x in a.splitlines() if re.search(rf"//\s*{j} {name}$",x))
            assert re.search(rf"ROV\(\s*{k},\s*\d+,\s*\d+,\s*SND_19_DEPARTURE_OLD_RV_1,\s*{speed},\s*{capacity},",row)
    if r:
        s=r.read_text()
        imgs=Q.data_table(s,"_roadveh_images");adds=Q.data_table(s,"_roadveh_full_adder")
        for i,j,k,sprite,*rest in STOCK.values():
            assert imgs[k]==sprite and adds[k]==0
    if n:
        a=n.read_text()
        for k,y in ((3300,264),(3492,520)):
            assert re.search(rf'spr{k}\({k}, "sprites/png/roadvehicles/vehiclesroad01.png"\)\s*\{{\s*\[\s*626,\s*{y},',a)

def geometry(stem):
    g=Q.rail_wagon_art.mesh(stem)
    f=Q.parse(stem)
    i,_,_,_,_,_,name,ax,track=STOCK[stem]
    assert not (MODEL/f"bl_{stem}_loaded.obj").exists()
    lo,hi=Q.ext(g)
    Q.in_lane(lo,hi)
    Q.turn_check(lo,hi)
    for side,tag in ((-1,"L"),(1,"R")):
        t=g[f"Ground_contact_tyre_{tag}"]
        assert min(h for _,_,h in t)==0
        contact=[(x,z) for x,z,h in t if h==0]
        assert len(contact)==4 and {round(z,6) for x,z in contact}==set(ax)
        assert abs(sum(x for x,z in contact)/4-side*track)<1.e-6
    if i==126:
        assert max(z for _,z,_ in g["Period_separate_round_warm_headlamp_lens"])<-.778
        assert min(z for _,z,_ in g["Round_incandescent_period_tail_reflector"])>.742
        assert min(z for _,z,_ in g["Split_old_safety_glass_face_nearly_vertical"])>-.492
        assert min(z for _,z,_ in g["Sculpted_rounded_louver_bonnet_separate_from_van"])<-.771
        assert len(f["Individually_painted_cream_postal_MAIL_lettering"])>=200
        assert len(f["Closed_sloping_cloth_van_canopy"])>90
    else:
        assert min(z for _,z,_ in g["Two_separately_split_sloping_Perry_windscreen_panes"])<-.739
        assert max(z for _,z,_ in g["Two_separately_split_sloping_Perry_windscreen_panes"])>-.595
        assert len(f["Seven_real_formed_late_van_charcoal_roof_belts"])==7*28
        assert max(z for _,z,_ in g["Bright_visible_nonslip_arrow-step_brushed_edge"])>.8
        assert min(z for _,z,_ in g["Raised_separate_ribbon_LEDs_at_door's_outer_edge"])>.760
        assert len(f["Original_plated_mail_fleet_logotype_individual_areas"])>=200
    png=Q.Image.open(ROOT/"mods/luanttd_core/textures"/f"bl_{stem}_atlas.png")
    assert png.mode=="RGB" and png.size==(1024,16)
    assert len({png.getpixel((16*j+8,8)) for j in range(64)})>=60
    assert (ROOT/"art"/f"{stem}.blend").stat().st_size>100000
    count=Q.freight_fits(g)
    print(f"#{i} {name}: {tuple(round(b-a,4) for a,b in zip(lo,hi))} native x/y/z units; "
          f"{sum(map(len,f.values()))} triangles and {count} freight clearance poses.")

if __name__=="__main__":
    p=ArgumentParser()
    p.add_argument("--engines",type=Path)
    p.add_argument("--roadveh",type=Path)
    p.add_argument("--opengfx",type=Path)
    a=p.parse_args();sources(a.engines,a.roadveh,a.opengfx)
    Q.MODELS=Q.rail_wagon_art.MODELS=MODEL
    Q.road_freight_stop_art.ROOT=BASE
    for name in STOCK:geometry(name)
    Q.road_corner_art.MODEL=MODEL
    Q.road_corner_art.STEMS=dict.fromkeys(STOCK,.42)
    Q.road_corner_art.stock(Q.road_corner_art.visual())
    print("STOCK_MAIL_COMPANIONS_ART_PASS")
