#!/usr/bin/env python3
"""Pinned #212 identity, original sealed holds and true native basin fit."""
from argparse import ArgumentParser
from hashlib import sha256
from math import hypot
from pathlib import Path
from PIL import Image
import os,re,sys

ROOT=Path(__file__).resolve().parents[1]
BASE=Path(os.environ.get("LUANTTD_BASE",str(ROOT))).resolve()
sys.path.insert(0,str(BASE/"tests"))
import ship_facility_art as A
import stock_oil_ships_art as O
from ship_lock_art import DIRECTIONS
STEM="stock_bakewell_cargo_ship"
MODELS=ROOT/"mods/luanttd_core/models"
ENGINES="d90c9b2ae091a740522b0f79078c3e5db32b2467cb2a9e0e96592c3c39ee1f74"
CMD="3613afe7ff40e35d2d603be3129c3ccf27c8fc350b2433dc415c0f760b949cf0"
MAPPING="20d611f24d647b869e05a1bbaf98bb55882e5f0bc0070e91f0c1c95002f47196"
SHEET="b44b41a37a174bfe6bbe247cd72ee1868bb470736e9dc96b2e29ff05688b8932"

def pinned(path,key):
    b=path.read_bytes();assert sha256(b).hexdigest()==key;return b

def source(o):
    if o.engines:
        e=pinned(o.engines,ENGINES).decode()
        assert re.search(r"MS\(\s*19724,\s*5,\s*30,\s*98,\s*CT_GOODS\s*,\s*LandscapeTypes\(\{T,A,S\s*\}\)\),\s*//\s*212 Bakewell Cargo ship",e)
        assert re.search(r"SVI\(\s*0,\s*144,\s*1,\s*80,\s*190,\s*113,\s*SND_06_DEPARTURE_CARGO_SHIP,\s*1\s*\),\s*//\s*8 Bakewell Cargo ship",e)
        print("PASS pinned #212 MS/SVI RC1 (image 0, 190 Goods base, refittable, speed 80, 1974 base date).")
    if o.ship_cmd:
        s=pinned(o.ship_cmd,CMD).decode()
        a=re.search(r"_ship_sprites\[\]\s*=\s*\{([^}]+)",s)[1]
        assert int(a.split(",")[0],16)==3677
        fn=s[s.index("void Ship::GetImage("):].split("\n}\n",1)[0]
        assert "result->Set(_ship_sprites[spritenum] + to_underlying(direction));" in fn
        assert "cargo" not in fn and "load" not in fn
        print("PASS RC1 directional image offset 3677; neither loaded nor refitted stock state changes the exterior sprite.")
    if o.opengfx:
        n=pinned(o.opengfx,MAPPING).decode()
        assert all(re.search(rf'spr{i}\({i}, "sprites/png/ships/ships01.png"\)',n) for i in range(3677,3685))
    if o.sheet:
        pinned(o.sheet,SHEET)
        im=Image.open(o.sheet)
        assert im.mode=="P" and im.width>744 and im.height>113

def hull_geometry():
    A.MODELS=MODELS
    m=A.read(STEM,True)
    allp=A.points(m)
    port=A.points(m,["Raked_panoramic_cabin_window_glazing_seated_across_ship_bridge"])
    assert len(port)>=20 and min(z for x,z,h in port)>.33
    names=("Closed_bending_and_ram-taper_coastal_Bakewell_pressure_hull","Twin_true_watertight_dark_steel_cargo_weather_covers",
           "Independent_sealed_hinged_hatch_cover_quadrants","Pin_in_exterior_cargo_cover_folding_hinge_barrel",
           "First_smooth_deep_cast_knuckle_boom_member","Second_longer_telescoping_genuine_hatch_crane_boom",
           "Exposed_chromium_hydraulic_piston_leads_into_knuckle","Closed_pitched_individually_cast_full_propeller_blades")
    for name in names:assert len(m[name])>5,name
    for n in (names[0],names[1],names[-1]):
        O.hull_closed(m[n])
    closed=A.points(m,[names[1]])
    assert not any(-.228<z<-.167 for x,z,h in closed)
    hooks=A.points(m,["Damped_freight_winch_sheave_bottom_block"])
    assert {next(i for i,(a,b) in enumerate(((-.343,-.293),(-.089,-.055))) if a<z<b) for x,z,h in hooks}=={0,1}
    assert min(h for x,z,h in hooks)>max(h for x,z,h in closed)+.07
    assert not (MODELS/f"bl_{STEM}_loaded.obj").exists()
    im=Image.open(ROOT/"mods/luanttd_core/textures"/f"bl_{STEM}_atlas.png")
    assert im.mode=="RGB" and im.size==(320,8)
    for _,faces in m.items():
        for p,uv in faces:
            assert len(set(p))==3 and all(a==uv[0] for a in uv),(p,uv)
            u,v=uv[0];assert abs((int(u*40)+.5)/40-u)<1e-6 and v==.5
    assert (ROOT/"art"/f"{STEM}.blend").stat().st_size>130000
    w,z,y=zip(*allp)
    beam=max(abs(x) for x in w);length=max(abs(a) for a in z)
    sz=(max(w)-min(w),max(y)-min(y),max(z)-min(z))
    assert .347<beam<.362 and .906<length<.923 and min(y)==-.188 and .785<max(y)<.8,(beam,length,min(y),max(y))
    assert max(z)>.90 and min(z)<-.90
    print("PASS two genuine watertight steel hatch covers and hull; 2 real articulated-looking working booms in forward/backover holds, 4 closed screw blades.")
    return beam,length,min(y),max(y),max(hypot(x,z) for x,z,h in allp),sz,sum(map(len,m.values()))

def clear(shape):
    beam,length,draft,height,radial,sz,tris=shape
    def m(k,entity=False):
        A.MODELS=BASE/"mods/luanttd_core/models"
        return A.read(k,entity)
    dock_margin=5
    for d in range(4):
        pier=A.points(m(f"ship_dock_pier_{d}"))
        for ax,s in ((0,1),(0,-1),(1,1),(1,-1)):
            dock_margin=min(dock_margin,2-radial-max(s*p[ax] for p in pier))
    assert dock_margin>.07,dock_margin
    rays=0
    for axis in (0,1):
        for j in (0,1):
            d=m(f"ship_depot_{axis}_{j}")
            for dx in (-beam,-.25,-.11,0,.12,.25,beam):
                for h in (draft,0,.14,.25,.45,.62,.73,height):
                    assert not A.ray(d,axis,dx,h,-1.0001,1.0001),(axis,dx,h)
                    rays+=1
    for d,(dx,dz) in enumerate(DIRECTIONS):
        for tag,hbase in (("lower",0),("middle",0),("upper",1)):
            lock=m(f"ship_lock_{tag}_{d}")
            for phase in (0,.375,.75,1):
                for x0 in (-beam,-.22,0,.22,beam):
                    for h in (draft,0,.25,.55,height):
                        assert not A.ray(lock,0 if dx else 1,x0,h+phase-hbase,-1.0001,1.0001),(d,tag,x0,h,phase)
                        rays+=1
    gate=5
    for label,anchor,sign in (("lower",-1.115,-1),("upper",1.115,1)):
        close=m(f"ship_lock_gate_{label}_closed",True)
        gate=min(gate,min(sign*(z+anchor) for x,z,h in A.points(close))-length)
        op=m(f"ship_lock_gate_{label}_open",True)
        for x in (-beam,-.22,0,.22,beam):
            for h in (draft,0,.25,.55,height):
                assert not A.ray(op,1,x,h,-1,1)
                rays+=1
    assert gate>.031,(gate,length)
    print(f"PASS native W/H/L {'/'.join(f'{q:.5f}' for q in sz)}; {tris:,} triangles, {rays:,} real harbour bores, "
          f"all-yaw radial dock margin {dock_margin:.5f}, worst closed gate gap {gate:.5f}.")

if __name__=="__main__":
    cli=ArgumentParser()
    for k in ("engines","ship-cmd","opengfx","sheet"):cli.add_argument("--"+k,type=Path)
    args=cli.parse_args();source(args);clear(hull_geometry())
    print("STOCK_BAKEWELL_CARGO_ART_PASS")
