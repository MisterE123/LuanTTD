#!/usr/bin/env python3
"""Exact RC1 ship stock IDs and native hull/dock/depot/lock clearance."""
from argparse import ArgumentParser
from collections import Counter
from hashlib import sha1
from math import hypot,isclose
from pathlib import Path
import os,re,sys

from PIL import Image
ROOT=Path(__file__).resolve().parents[1]
BASE=Path(os.getenv("LUANTTD_BASE",ROOT)).resolve()
sys.path.insert(0,str(BASE/"tests"))
import ship_facility_art as A
from ship_lock_art import DIRECTIONS
MODELS=ROOT/"mods/luanttd_core/models"
OLD="stock_mps_oil_tanker"
NEW="stock_cs_inc_oil_tanker"
STOCK={OLD:(204,0,220,140,"MPS Oil Tanker"),NEW:(205,1,350,125,"CS-Inc. Oil Tanker")}
HULL="Native_continuous_watertight_pressure_hull_and_weather_deck"

def sources(e,s,g):
    if e:
        raw=e.read_bytes()
        assert sha1(f"blob {len(raw)}\0".encode()+raw).hexdigest()=="1f71919c2399ebe7053cd78a306a96fb59e25def"
        t=raw.decode()
        for k,(id,row,cap,run,name) in STOCK.items():
            q=re.escape(name)
            assert re.search(rf"MS\([^\n]*\bCT_OIL\b[^\n]*//\s*{id} {q}",t)
            assert re.search(rf"SVI\(\s*1,\s*\d+,\s*1,\s*\d+,\s*{cap},\s*{run},\s*SND_06_DEPARTURE_CARGO_SHIP,\s*0\s*\),\s*//\s*{row} {q}",t)
    if s:
        t=s.read_text()
        raw=re.search(r"_ship_sprites\[\]\s*=\s*\{([^}]+)",t)[1]
        ss=[int(v.strip(),16) for v in raw.split(",")]
        assert ss[1]==3669
        fn=t[t.index("void Ship::GetImage("):].split("\n}\n",1)[0]
        assert "result->Set(_ship_sprites[spritenum] + to_underlying(direction));" in fn
        assert "cargo" not in fn and "load" not in fn
    if g:
        t=g.read_text()
        assert all(re.search(rf'spr{k}\({k}, "sprites/png/ships/ships01.png"\)',t) for k in range(3669,3677))

def mesh(stem):
    A.MODELS=MODELS
    return A.read(stem,True)
def facility(stem,entity=False):
    A.MODELS=BASE/"mods/luanttd_core/models"
    return A.read(stem,entity)

def hull_closed(shape):
    incidence=Counter()
    for (a,b,c),_ in shape:
        incidence.update(tuple(sorted((p,q))) for p,q in ((a,b),(b,c),(a,c)))
    assert set(incidence.values())=={2}

def ship(stem):
    m=mesh(stem);allp=A.points(m)
    assert all(m[k] for k in (
        HULL,"Welded_real_tubing_between_each_cargo_hold_and_transfer_manifold",
        "Real_curved_reserve_deck_tank_vent_lines","Original_forward_wheelhouse_panoramic_sea-blue_glass",
        "Real_working_port_and_starboard_oil_transfer_outlets","Below-water_centreline_propeller_shaft"))
    hull_closed(m[HULL])
    assert not (MODELS/f"bl_{stem}_loaded.obj").exists()
    assert (ROOT/"art"/f"{stem}.blend").stat().st_size>100000
    im=Image.open(ROOT/"mods/luanttd_core/textures"/f"bl_{stem}_atlas.png")
    assert im.mode=="RGB" and im.size==(512,8)
    for n,faces in m.items():
        for f,uv in faces:
            assert len(set(f))==3 and all(p==uv[0] for p in uv)
            u,v=uv[0]
            assert v==.5 and isclose(u,(round(u*64-.5)+.5)/64,abs_tol=1e-6)
    x,z,y=zip(*allp)
    gauge=max(abs(a) for a in x);length=max(abs(a) for a in z)
    sz=tuple(round(max(p)-min(p),4) for p in (x,y,z))
    assert .293<gauge<.353 and .858<length<.923
    assert -.191<min(y)<-.167 and .766<max(y)<.831
    assert -.924<min(z)<-.865 and .855<max(z)<.918
    assert all(a>.38 for _,a,_ in A.points(m,["Distinct_original_aft_raised_tanker_bridge_cabin"]))
    assert all(y>.150 for x,z,y in A.points(m,["Long_running_raised_pressure_transfer_main_lines"]))
    assert any(x<0 for x,z,y in A.points(m,["Distinct_capped_outward_loading_manifold_flanges"]))
    assert any(x>0 for x,z,y in A.points(m,["Distinct_capped_outward_loading_manifold_flanges"]))
    if stem==OLD:assert "Classic_tall_forward-raked_steam_funnel" in m and "CS_oil_transfer_portal_column" not in m
    else:assert all(k in m for k in ("Later_short_paired_offset_motors_exhaust_casing","CS_oil_transfer_portal_column","Permanent_original_horizontal_bridge_radar_scanner"))
    # Narrow adjacent berth centers exactly one 2-node tile from the dock
    # water-part. Prove every yaw by the full rendered ship radial bound.
    radial=max(hypot(a,b) for a,b,_ in allp)
    dock_margin=5
    for d in range(4):
        pier=facility(f"ship_dock_pier_{d}")
        edge=A.points(pier)
        for ax,s in ((0,1),(0,-1),(1,1),(1,-1)):
            far=max(s*p[ax] for p in edge)
            dock_margin=min(dock_margin,2-radial-far)
    assert dock_margin>.061,dock_margin
    ray=A.ray
    hmin,hmax=min(y),max(y)
    rays=0
    for axis in (0,1):
        for j in (0,1):
            d=facility(f"ship_depot_{axis}_{j}")
            for dx in (-gauge,-.25,-.11,0,.12,.25,gauge):
                for h in (hmin,0,.14,.25,.45,.62,.73,hmax):
                    assert not ray(d,axis,dx,h,-1.0001,1.0001),(axis,dx,h)
                    rays+=1
    for d,(dx,dz) in enumerate(DIRECTIONS):
        for label,hbase in (("lower",0),("middle",0),("upper",1)):
            lock=facility(f"ship_lock_{label}_{d}")
            for phase in (0,.375,.75,1):
                for x0 in (-gauge,-.22,0,.22,gauge):
                    for h in (hmin,0,.25,.55,hmax):
                        assert not ray(lock,0 if dx else 1,x0,h+phase-hbase,-1.0001,1.0001),(d,label,x0,h,phase)
                        rays+=1
    gate_margin=5
    for key,anchor,sign in (("lower",-1.115,-1),("upper",1.115,1)):
        closed=facility(f"ship_lock_gate_{key}_closed",True)
        clear=min(sign*(b+anchor) for a,b,h in A.points(closed))-length
        gate_margin=min(gate_margin,clear)
        opened=facility(f"ship_lock_gate_{key}_open",True)
        for x0 in (-gauge,-.22,0,.22,gauge):
            for h in (hmin,0,.25,.55,hmax):
                assert not ray(opened,1,x0,h,-1,1)
                rays+=1
    assert gate_margin>.031,gate_margin
    total=sum(map(len,m.values()))
    print(f"#{STOCK[stem][0]}: {sz} native x/y/z nodes, {total:,} triangles, {rays:,} bore rays clear, "
          f"per-yaw dock clearance ≥{dock_margin:.4f}, minimum closed-gate clearance {gate_margin:.4f}.")
    return sz,total

if __name__=="__main__":
    p=ArgumentParser()
    p.add_argument("--engines",type=Path)
    p.add_argument("--ship-cmd",type=Path)
    p.add_argument("--opengfx",type=Path)
    a=p.parse_args();sources(a.engines,a.ship_cmd,a.opengfx)
    old,new=ship(OLD),ship(NEW)
    assert new[0][0]>old[0][0]+.05 and new[0][2]>old[0][2]+.08
    print("STOCK_OIL_SHIPS_ART_PASS")
