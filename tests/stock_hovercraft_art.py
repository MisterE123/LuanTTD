#!/usr/bin/env python3
"""Pinned base hovercraft, sealed skirt and fan ring, marina physical fit."""
from argparse import ArgumentParser
from hashlib import sha1
from math import hypot,isclose
from pathlib import Path
import os,re,sys
from PIL import Image

ROOT=Path(__file__).resolve().parents[1]
BASE=Path(os.environ.get("LUANTTD_BASE",ROOT)).resolve()
sys.path.insert(0,str(BASE/"tests"))
import stock_oil_ships_art as shared
from ship_lock_art import DIRECTIONS
A=shared.A
STEM="stock_bakewell_300_hovercraft"
MODELS=ROOT/"mods/luanttd_core/models"

def sources(e,s,g):
    if e:
        raw=e.read_bytes()
        assert sha1(f"blob {len(raw)}\0".encode()+raw).hexdigest()=="1f71919c2399ebe7053cd78a306a96fb59e25def"
        t=raw.decode()
        assert re.search(r'MS\(\s*17257,\s*10,\s*25,\s*90,\s*CT_PASSENGERS\s*,\s*LandscapeTypes\(\{T,A,S\s*\}\)\),\s*//\s*208 Bakewell 300 Hovercraft',t)
        assert re.search(r'SVI\(\s*3,\s*148,\s*1,\s*224,\s*100,\s*190,\s*SND_07_DEPARTURE_FERRY,\s*0\s*\),\s*//\s*4 Bakewell 300 Hovercraft',t)
    if s:
        t=s.read_text()
        raw=re.search(r"_ship_sprites\[\]\s*=\s*\{([^}]+)",t)[1]
        assert [int(x,16) for x in raw.split(",")][3]==3693
        fn=t[t.index("void Ship::GetImage("):].split("\n}\n",1)[0]
        assert "result->Set(_ship_sprites[spritenum] + to_underlying(direction));" in fn
        assert all(k not in fn for k in ("cargo","load","speed"))
    if g:
        t=g.read_text()
        assert all(re.search(rf'spr{k}\({k}, "sprites/png/ships/ships01.png"\)',t) for k in range(3693,3701))

def floats():
    shared.MODELS=MODELS
    m=shared.mesh(STEM)
    assert not (MODELS/f"bl_{STEM}_loaded.obj").exists()
    skirt="Sealed_separate_amphibious_pneumatic_skirt_and_central_air_plenum"
    rigid="Separate_rigid_sealed_aluminium_load_deck_and_vehicle_shell"
    duct="Real_open_annular_rear_thrust_ducts"
    for name in (skirt,rigid,duct):shared.hull_closed(m[name])
    skirt_points=A.points(m,[skirt])
    assert min(y for x,z,y in skirt_points)<-.098
    assert .124<max(y for x,z,y in skirt_points)<.128
    assert min(y for x,z,y in A.points(m,[rigid]))>.11
    assert len(m["Independent_rounded_flexible_black_apron_skirt_fingers"])==2*28*4*2
    assert len(m["Five_swept_fan_individual_blade_machined_tips"])==2*5*6*2
    assert len(m["Small_individual_glazed_saloon_side_windows"])==2*12*2
    assert len(m["Curved_separate_pilot_bridge_front_windshields"])==4*5*2
    for s in (-1,1):
        assert all(v[1]>.505 for f,_ in m[duct] for v in f)
        # Actual open tapered cylinder, with rings checked independently of
        # blades: central ray is free and rim/ring annulus intercepts.
        g={duct:[(p,uv) for p,uv in m[duct] if sum(x for x,z,h in p)*s>0]}
        assert not A.ray(g,1,s*.243,.415,.501,.633)
        assert A.ray(g,1,s*.243+.090,.420,.501,.633)
        assert not A.ray(g,1,s*.243+.112,.415,.501,.633)
        assert all(abs(x-s*.243)<.108 for f,_ in g[duct] for x,z,h in f)
    assert (ROOT/"art"/f"{STEM}.blend").stat().st_size>100000
    im=Image.open(ROOT/"mods/luanttd_core/textures"/f"bl_{STEM}_atlas.png")
    assert im.mode=="RGB" and im.size==(512,8) and len({im.getpixel((8*i+4,4)) for i in range(64)})>=62
    pts=A.points(m)
    for group,fs in m.items():
        for f,uv in fs:
            assert len(set(f))==3 and all(k==uv[0] for k in uv)
            u,v=uv[0]
            assert v==.5 and isclose(u,(round(u*64-.5)+.5)/64,abs_tol=1e-6)
    vx,vz,vy=zip(*pts)
    gauge,length=max(map(abs,vx)),max(map(abs,vz))
    assert .365<gauge<.393 and .85<length<.909
    assert min(vz)<-.862 and max(vz)>.847
    assert -.102<min(vy)<-.095 and .610<max(vy)<.67
    print("Geometry: native W/H/L",tuple(round(max(a)-min(a),4) for a in (vx,vy,vz)),
          "nodes;",sum(map(len,m.values())),"triangles, two open aft ducts, segmented skirt.")
    return pts,gauge,length,min(vy),max(vy)

def clear(pts,gauge,length,bottom,top):
    shared.BASE=BASE
    facility=shared.facility
    radial=max(hypot(x,z) for x,z,y in pts)
    dock=10;rays=0
    for i in range(4):
        p=A.points(facility(f"ship_dock_pier_{i}"))
        for ax,s in ((0,1),(0,-1),(1,1),(1,-1)):
            dock=min(dock,2-radial-max(s*q[ax] for q in p))
    assert dock>.08,dock
    ray=A.ray
    for axis in (0,1):
        for side in (0,1):
            g=facility(f"ship_depot_{axis}_{side}")
            for x in (-gauge,-.25,-.11,0,.12,.25,gauge):
                for h in (bottom,0,.14,.25,.45,.58,top):
                    assert not ray(g,axis,x,h,-1.0001,1.0001),(axis,side,x,h)
                    rays+=1
    for d,(dx,dz) in enumerate(DIRECTIONS):
        for label,hbase in (("lower",0),("middle",0),("upper",1)):
            g=facility(f"ship_lock_{label}_{d}")
            for phase in (0,.375,.75,1):
                for x in (-gauge,-.22,0,.22,gauge):
                    for h in (bottom,0,.25,.5,top):
                        assert not ray(g,0 if dx else 1,x,h+phase-hbase,-1.0001,1.0001)
                        rays+=1
    gate=10.
    for key,anchor,sg in (("lower",-1.115,-1),("upper",1.115,1)):
        g=facility(f"ship_lock_gate_{key}_closed",True)
        gate=min(gate,min(sg*(z+anchor) for _,z,_ in A.points(g))-length)
        g=facility(f"ship_lock_gate_{key}_open",True)
        for x in (-gauge,-.22,0,.22,gauge):
            for h in (bottom,0,.25,.5,top):
                assert not ray(g,1,x,h,-1.,1.)
                rays+=1
    assert gate>.04,gate
    print(f"{rays:,} physical depot/lock rays; ≥{dock:.4f} dock all-yaw and {gate:.4f} closed-gate margin.")

if __name__=="__main__":
    p=ArgumentParser()
    p.add_argument("--engines",type=Path)
    p.add_argument("--ship-cmd",type=Path)
    p.add_argument("--opengfx",type=Path)
    a=p.parse_args()
    sources(a.engines,a.ship_cmd,a.opengfx)
    clear(*floats())
    print("STOCK_HOVERCRAFT_ART_PASS")
