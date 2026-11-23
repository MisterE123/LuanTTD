#!/usr/bin/env python3
"""Source identity, original iron-ore models, and exact native track/vehicle tests."""
import argparse,os,re,struct,sys
from datetime import date,timedelta
from hashlib import sha256
from math import isclose
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
BASE=Path(os.environ.get("LUANTTD_BASE",str(ROOT))).resolve()
sys.path.insert(0,str(BASE/"tests"))
import stock_road_fleet_d_art as d
M=ROOT/"mods/luanttd_core/models"
T=ROOT/"mods/luanttd_core/textures"
STOCK=(
 (147,"mps","MPS",31,8,3364,5479,55,121,90,96,22,38,12,(-.536,.425),78,.493),
 (148,"uhl","Uhl",32,25,3172,20820,55,140,168,176,25,48,22,(-.528,.437),98,.523),
 (149,"chippy","Chippy",33,42,3556,33238,85,150,240,224,27,69,45,(-.533,.329,.584),120,.548),
)
HOPPER="Watertight_reinforced_open_tipped_iron_ore_hopper_with_actual_steel_thickness"
CORE="Closed_independent_solid_crushed_iron_ore_cargo_mass_below_granular_top"
CARGO="Individual_closed_hematite_and_limonite_iron_ore_stone_"
def stem(m):return f"stock_{m}_iron_ore_truck"

def pinned(path,want):
    b=path.read_bytes();assert sha256(b).hexdigest()==want;return b

def upstream(a):
    if a.engines:
        t=pinned(a.engines,d.PING).decode()
        for id,_,name,row,image,sprite,day,base,buy,run,speed,cap,wt,pwr,*_ in STOCK:
            n=f"{name} Iron Ore Truck"
            p=rf"MR\(\s*{day},\s*20,\s*15,\s*{base},\s*CT_IRON_ORE\s*,\s*LandscapeTypes\(\{{T\s*\}}\)\),\s*//\s*{id} {n}\b"
            q=rf"ROV\(\s*{image},\s*{buy},\s*{run},\s*SND_19_DEPARTURE_OLD_RV_1,\s*{speed},\s*{cap},\s*{wt},\s*{pwr}\),\s*//\s*{row} {n}\b"
            assert re.search(p,t) and re.search(q,t),(id,n)
            print(f"PASS pinned RC1 #{id} {n}: image {image}, cap {cap}, {date(1920,1,1)+timedelta(day)}")
    if a.road_source:
        t=pinned(a.road_source,d.ROAD_PIN).decode()
        def table(n):
            z=re.search(n+r"\[\]\s*=\s*{([^}]+)}",t)[1]
            return [int(v,0) for v in z.split(",") if v.strip()]
        b,ad=table("_roadveh_images"),table("_roadveh_full_adder")
        assert [(b[x[4]],ad[x[4]]) for x in STOCK]==[(x[5],48) for x in STOCK]
        assert "this->cargo.StoredCount() >= this->cargo_cap / 2U" in t
        print("PASS exact directional loaded sprite adder +48 and cargo threshold floor(cap/2): 11, 12, 13.")

def shape():
    a=[]
    for id,m,*_,axles,nrocks,lip in STOCK:
        k=stem(m)
        p=M/f"bl_{k}.obj";q=M/f"bl_{k}_loaded.obj"
        assert q.read_bytes().startswith(p.read_bytes())
        v,g=d.load(p);v2,h=d.load(q)
        extent=d.bounds(v)
        assert all(h[k]==fs for k,fs in g.items()) and d.bounds(v2)==extent
        (x,y,z),(X,Y,Z)=extent
        assert y==0 and z<-.31 and Z>.31
        assert .244<X-x<.268 and .255<Y<.302 and .644<Z-z<.705,(k,extent)
        for s in (-1,1):
            clip=(s*.155+x,s*.155+X)
            assert min(abs(x) for x in clip)>.020 and max(abs(x) for x in clip)<.2925
        treads={(round(x,7),round(z,7)) for x,y,z in v if y==0}
        assert len(treads)==4*len(axles) and {z for _,z in treads}=={round(k*.42,7) for k in axles}
        assert re.search(r"o (?:Actual_warm_front_round_lens|True_front-facing_color_lens)",p.read_text())
        front=g["Actual_warm_front_round_lens" if id==147 else "True_front-facing_color_lens"]
        assert any(n[2]<-.94 for _,_,n in front) and max(z for f,_,_ in front for _,_,z in f)<-.30
        assert min(z for f,_,_ in g["Directional_rear_individual_three-colour_lamps"] for _,_,z in f)>.29
        d.closed(g["Original_shaped_pressed_steel_cab_shell"])
        d.closed(g[HOPPER]);d.closed(h[CORE])
        assert len(g["Full_actual_twin-stage_chromium_piston_cylinder_and_drive_links"])>=10
        assert len(g["Physical_top_hinged_retaining_gate_axle_segments"])>=35
        rock=[f for n,f in h.items() if n.startswith(CARGO)]
        assert len(rock)==nrocks
        for f in rock:
            d.closed(f)
            assert len({c for _,c,_ in f})>=4
            assert min(y for p,_,_ in f for _,y,_ in p)>.148
            assert max(y for p,_,_ in f for _,y,_ in p)<(lip+.039)*.42
        atlas=(T/f"bl_{k}_atlas.png").read_bytes();a.append(atlas)
        assert atlas.startswith(b"\x89PNG\r\n\x1a\n")
        assert struct.unpack(">IIBBBBB",atlas[16:29])==(1024,16,8,2,0,0,0)
        assert (ROOT/"art"/f"{k}.blend").stat().st_size>150000
        print(f"PASS #{id} native W/H/L {(X-x):.5f}/{Y:.5f}/{(Z-z):.5f}; "
              f"{2*len(axles)} true native tread contacts, {nrocks} individually closed ore stones."
              " Empty and loaded shell are byte-identical.")
    assert len(set(a))==3

def full_road():
    import level_crossing_art as crossing
    import road_corner_art as corners
    substitute={p.name:p for p in M.glob("*.obj")}
    baseline=corners.obj
    corners.obj=lambda p,*a:baseline(substitute.get(p.name,p),*a)
    states=[stem(m)+suffix for _,m,*_ in STOCK for suffix in ("","_loaded")]
    corners.STEMS=dict.fromkeys(states,.42)
    corners.stock(corners.visual())
    n=0
    old=crossing.obj
    try:
        for axis in (0,1):
            real={s:crossing.active_groups(crossing.M/f"bl_level_crossing_{axis}_{s}.obj",axis) for s in ("open","closed")}
            for k in states:
                def parse(path,*a):
                    if path.name in ("bl_coal_tipper_loaded.obj","bl_stock_balogh_coal_loaded.obj"):
                        path=substitute[f"bl_{k}.obj"]
                    return old(path,*a)
                crossing.obj=parse
                n+=crossing.clearance(axis,real)
    finally:crossing.obj=old
    assert n==len(states)*2904,n
    print(f"PASS {n:,} native road/rail crossing fixtures across all three empty and loaded model pairs.")

if __name__=="__main__":
    p=argparse.ArgumentParser()
    p.add_argument("--engines",type=Path);p.add_argument("--road-source",type=Path)
    p.add_argument("--road",action="store_true")
    a=p.parse_args()
    upstream(a);shape()
    if a.road:full_road()
    print("STOCK_IRON_ORE_ROAD_ART_PASS")
