#!/usr/bin/env python3
"""Native geometry and optional exact stock road-fixture tests for fleet D."""
import argparse
from collections import Counter
from hashlib import sha256
from math import isclose
from pathlib import Path
import re
import struct
import sys

ROOT=Path(__file__).resolve().parents[1]
MODEL=ROOT/"mods/luanttd_core/models"
TEX=ROOT/"mods/luanttd_core/textures"
STEMS=("stock_uhl_coal_truck","stock_foster_oil_tanker","stock_reynard_mail_truck")
S=.42
PING="d90c9b2ae091a740522b0f79078c3e5db32b2467cb2a9e0e96592c3c39ee1f74"
ROAD_PIN="d46e52e03d11a98dd2adeeeebaedb87954e36ad839e982669ab7e048ed8ddb8d"


def load(path):
    v=[];uv=[];norm=[];g={};name=None
    for line in path.read_text().splitlines():
        k,*bits=line.split()
        if k=="v":
            x,y,z=map(float,bits)
            v.append((-x*S/10,y*S/10,z*S/10))
        elif k=="vn":
            n=tuple(map(float,bits))
            assert isclose(sum(x*x for x in n),1,abs_tol=1e-4)
            norm.append(n)
        elif k=="vt":
            x,y=map(float,bits)
            assert y==.5 and isclose(x,(len(uv)+.5)/64,abs_tol=1e-6)
            uv.append(x)
        elif k=="o":name=bits[0]
        elif k=="f":
            i,c,n=zip(*(map(int,p.split("/")) for p in bits))
            assert len(set(i))==3 and len(set(c))==len(set(n))==1 and name
            assert all(1<=j<=len(v) for j in i) and 1<=c[0]<=len(uv) and 1<=n[0]<=len(norm)
            g.setdefault(name,[]).append((tuple(v[j-1] for j in i),c[0],norm[n[0]-1]))
        else:assert k.startswith("#")
    assert len(uv)==64 and len(g)>=45
    return v,g


def bounds(v):
    return [tuple(fn(a) for a in zip(*v)) for fn in (min,max)]


def closed(faces):
    edges=Counter(tuple(sorted((a,b))) for p,_,_ in faces for a,b in zip(p,(p[1],p[2],p[0])))
    assert set(edges.values())=={2},Counter(edges.values())


def art():
    for key in STEMS:
        path=MODEL/f"bl_{key}.obj"
        cargo=MODEL/f"bl_{key}_loaded.obj"
        v,g=load(path)
        low,high=bounds(v)
        dim=[b-a for a,b in zip(low,high)]
        assert .244<dim[0]<.268 and .258<dim[1]<.296 and .643<dim[2]<.700,(key,dim)
        assert low[1]==0
        for side in (-1,1):
            lane=(low[0]+side*.155,high[0]+side*.155)
            assert min(abs(x) for x in lane)>.020
            assert max(abs(x) for x in lane)<.3125-.020
        points={(x,z) for x,y,z in v if y==0}
        assert len(points)==8 and len({z for _,z in points})==2
        png=(TEX/f"bl_{key}_atlas.png").read_bytes()
        assert png.startswith(b"\x89PNG\r\n\x1a\n")
        assert struct.unpack(">IIBBBBB",png[16:29])==(1024,16,8,2,0,0,0)
        assert (ROOT/"art"/f"{key}.blend").stat().st_size>120_000
        head="Actual_warm_front_round_lens" if "oil" in key else "True_front-facing_color_lens"
        assert min(n[2] for _,_,n in g[head])<-.94
        assert max(z for p,_,_ in g[head] for _,_,z in p)<-.30
        assert min(z for p,_,_ in g["Directional_rear_individual_three-colour_lamps"] for _,_,z in p)>.30
        closed(g["Original_shaped_pressed_steel_cab_shell"])
        if "coal" in key:
            assert cargo.read_bytes().startswith(path.read_bytes())
            vv,full=load(cargo)
            assert bounds(vv)==[low,high] and all(full[n]==g[n] for n in g)
            hopper="Closed_structural_open_coal_tipper_bed_with_thicker_rolled_rim"
            closed(g[hopper])
            closed(full["Coal_cargo_bed_core"])
            lumps=[fs for name,fs in full.items() if name.startswith("Separate_watertight_crushed_coal_rock_")]
            assert len(lumps)==98
            for lump in lumps:
                closed(lump)
                assert len({i for _,i,_ in lump})>=3
            assert g["Independent_chromed_telescoping_piston_link"] and g["Upper_tailgate_hinge_shafts"]
            assert max(y for lump in lumps for p,_,_ in lump for _,y,_ in p)<.231
        else:
            assert not cargo.exists(),f"{key} is a single stock exterior."
            if "oil" in key:
                tank="Continuous_sealed_contoured_Foster_oil_barrel_with_both_pressure_heads"
                closed(g[tank])
                closed(g["Two_separate_closed_full_circumference_tension_bands"])
                for name in ("Load_bearing_two_pressed_curved_saddles_beneath_oil_tank",
                             "Satin_circular_oil_filling_hatch_dome",
                             "Separate_long_continuous_flexible_delivery_hose",
                             "Individual_round_anti-slip_tail_ladder_rungs",
                             "Independent_shutoff_valve_angled_red_lever"):
                    assert g[name],name
            if "mail" in key:
                closed(g["Watertight_Reynard_sealed_mail_van_curved_crown_shell"])
                for name in ("Actual_broad_sliding_parcel_door_deep_rail_shadow",
                             "Raised_original_line-art_letter_symbol",
                             "Real_separate_van_gate_hinge_pivot_barrel"):
                    assert g[name],name
        print(f"PASS {key}: native .42, four tires exactly at Y=0, role hardware,"+
              " W/H/L "+"/".join(f"{d:.5f}" for d in dim))


def upstream(enginepath,roadpath):
    if enginepath:
        e=enginepath.read_bytes()
        assert sha256(e).hexdigest()==PING
        a=e.decode()
        for number,tag,row,img,buy,cap,day in (
            (124,"Uhl Coal Truck",8,18,128,25,20089),
            (127,"Reynard Mail Truck",11,19,135,28,21550),
            (133,"Foster Oil Tanker",17,20,140,25,19359),
        ):
            assert re.search(rf"MR\(\s*{day},\s*20,\s*15,\s*55,.*?//\s*{number} {tag}\b",a)
            assert re.search(rf"ROV\(\s*{img},\s*{buy},\s*168,\s*SND_19_DEPARTURE_OLD_RV_1,\s*176,\s*{cap},\s*48,\s*22\),\s*//\s*{row} {tag}\b",a)
    if roadpath:
        b=roadpath.read_bytes()
        assert sha256(b).hexdigest()==ROAD_PIN
        s=b.decode()
        def table(label):
            a=re.search(label+r"\[\]\s*=\s*{([^}]+)}",s)
            return [int(x,0) for x in a[1].split(",") if x.strip()]
        assert table("_roadveh_images")[18:21]==[3100,3108,3116]
        assert table("_roadveh_full_adder")[18:21]==[88,0,0]
        assert "this->cargo.StoredCount() >= this->cargo_cap / 2U" in s
    if enginepath or roadpath:
        print("PASS pinned 16.0-RC1 #124/#127/#133; stock rows, sprite adder and half-capacity criteria.")


def road_fixtures(repo):
    sys.path.insert(0,str(repo/"tests"))
    import level_crossing_art as crossing
    import road_corner_art as corners
    rewrite={p.name:p for p in MODEL.glob("*.obj")}
    saved=corners.obj
    corners.obj=lambda path,*args:saved(rewrite.get(path.name,path),*args)
    corners.STEMS=dict.fromkeys((*STEMS,STEMS[0]+"_loaded"),S)
    corners.stock(corners.visual())
    original=crossing.obj
    n=0
    for axis in (0,1):
        real={s:crossing.active_groups(crossing.M/f"bl_level_crossing_{axis}_{s}.obj",axis) for s in ("open","closed")}
        for key in corners.STEMS:
            def substitute(path,*args):
                if path.name in ("bl_coal_tipper_loaded.obj","bl_stock_balogh_coal_loaded.obj"):
                    path=rewrite[f"bl_{key}.obj"]
                return original(path,*args)
            crossing.obj=substitute
            n+=crossing.clearance(axis,real)
    crossing.obj=original
    assert n==4*2904,n
    print(f"PASS {n:,} stock grade-crossing cases across all four model states.")


if __name__=="__main__":
    p=argparse.ArgumentParser()
    for key in ("road-fixtures","engines","road-source"):p.add_argument("--"+key,type=Path)
    opt=p.parse_args()
    upstream(opt.engines,opt.road_source)
    art()
    if opt.road_fixtures:road_fixtures(opt.road_fixtures.resolve())
