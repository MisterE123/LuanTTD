#!/usr/bin/env python3
"""Check 16.0-RC1 stock armoured IDs, fixed exterior and true road clearance."""
from argparse import ArgumentParser
from hashlib import sha1
from pathlib import Path
import os,re,sys
ROOT=Path(__file__).resolve().parents[1]
BASE=Path(os.getenv("LUANTTD_BASE",ROOT)).resolve()
sys.path.insert(0,str(BASE/"tests"))
import stock_late_freight_art as Q
MODELS=ROOT/"mods/luanttd_core/models"
STOCK={
"stock_balogh_armoured_truck":(153,37,10,3372,360,5479,55,145,90,96,12,38,12,"Balogh Armoured Truck",(-.469,.426)),
"stock_uhl_armoured_truck":(154,38,27,3180,104,22281,55,170,168,176,15,48,22,"Uhl Armoured Truck",(-.491,.461)),
"stock_foster_armoured_truck":(155,39,44,3564,616,33603,85,180,240,224,16,69,45,"Foster Armoured Truck",(-.511,.256,.526))}

def pinned(e,r,n):
    if e:
        raw=e.read_bytes()
        assert sha1(f"blob {len(raw)}\0".encode()+raw).hexdigest()=="1f71919c2399ebe7053cd78a306a96fb59e25def"
        t=raw.decode()
        for id,row,img,s,y,day,rel,cost,run,speed,size,weight,hp,name,ax in STOCK.values():
            assert re.search(rf"MR\(\s*{day},\s*20,\s*15,\s*{rel},\s*MCT_VALUABLES_GOLD_DIAMONDS,\s*LandscapeTypes\(\{{T,A,S\s*\}}\)\),\s*//\s*{id} {name}",t)
            assert re.search(rf"ROV\(\s*{img},\s*{cost},\s*{run},\s*SND_19_DEPARTURE_OLD_RV_1,\s*{speed},\s*{size},\s*{weight},\s*{hp}\),\s*//\s*{row} {name}",t)
    if r:
        s=r.read_text();imgs=Q.data_table(s,"_roadveh_images");loads=Q.data_table(s,"_roadveh_full_adder")
        for _,_,i,j,*_ in STOCK.values():assert imgs[i]==j and loads[i]==0
    if n:
        raw=n.read_bytes()
        assert sha1(f"blob {len(raw)}\0".encode()+raw).hexdigest()=="ff7de7f3ea587fc554fc9331399bc35333607364"
        t=raw.decode()
        for _,_,i,j,y,*_ in STOCK.values():
            assert re.search(rf'spr{j}\({j}, "sprites/png/roadvehicles/vehiclesroad01.png"\)\s*\{{\s*\[\s*594,\s*{y},',t)
def model(k):
    m=Q.rail_wagon_art.mesh(k);f=Q.parse(k)
    desc,ax=STOCK[k][-2:]
    assert not (MODELS/f"bl_{k}_loaded.obj").exists()
    assert (ROOT/"art"/f"{k}.blend").stat().st_size>100000
    a=Q.Image.open(ROOT/"mods/luanttd_core/textures"/f"bl_{k}_atlas.png")
    assert a.size==(1024,16) and a.mode=="RGB"
    assert len({a.getpixel((i*16+8,8)) for i in range(64)})>=60
    Q.manifold(f["Original_sealed_rolled_plated_valuables_secure_transport_coachwork"])
    assert "Independent_exterior_steel_rear_valuables_door_leaves" in f
    assert len(f["Closed_outward_armoured_cargo_door_anti-sag_hinge_pins"])==6*28
    assert not any("crate" in k.lower() or "visible_cargo" in k.lower() for k in f)
    if "balogh" in k:
        assert all(z<-.54 for _,z,_ in m["Balogh_independent_long_early_rounded_bonnet"])
        assert min(z for _,z,_ in m["Balogh_early_opaque_glass_headlamp_lens"])<-.787
        assert min(z for _,z,_ in m["Balogh_characteristic_nearly_vertical_two_original_windscreen_panes"])>-.555
    else:
        assert min(z for _,z,_ in m["Two_genuinely_separate_dark_safety_windshield_panes"])<-.68
        assert ("Uhl_separate_silver_midcentury_radiator_elements" in m)==("uhl" in k)
        assert ("Foster_contemporaneous_lower_square_radiator_inserts" in m)==("foster" in k)
    assert min(z for _,z,_ in m["One_ruby_rear_lens_each_side"])>.77
    for s,side in ((-1,"L"),(1,"R")):
        v=m["Ground_contact_tyre_"+side]
        tr=[(x,z) for x,z,h in v if h==0]
        assert len(tr)==len(ax)*2 and min(h for _,_,h in v)==0
        assert {round(z,6) for x,z in tr}==set(ax)
        assert abs(sum(x for x,z in tr)/len(tr)-s*.218)<.000001
    lo,hi=Q.ext(m);Q.in_lane(lo,hi);Q.turn_check(lo,hi)
    print(f"{desc}: x/y/z {tuple(round(b-a,4) for a,b in zip(lo,hi))}; "
          f"{sum(map(len,f.values())):,} triangles; {Q.freight_fits(m):,} exact freight stop/fence poses.")

if __name__=="__main__":
    p=ArgumentParser()
    p.add_argument("--engines",type=Path);p.add_argument("--roadveh",type=Path);p.add_argument("--opengfx",type=Path)
    a=p.parse_args();pinned(a.engines,a.roadveh,a.opengfx)
    Q.MODELS=Q.rail_wagon_art.MODELS=MODELS;Q.road_freight_stop_art.ROOT=BASE
    for k in STOCK:model(k)
    Q.road_corner_art.MODEL=MODELS;Q.road_corner_art.STEMS=dict.fromkeys(STOCK,.42)
    Q.road_corner_art.stock(Q.road_corner_art.visual())
    print("STOCK_ARMOURED_TRUCKS_ART_PASS")
