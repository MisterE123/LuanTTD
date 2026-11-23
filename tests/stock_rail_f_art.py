#!/usr/bin/env python3
"""Stock source, shell integrity and physical rail/adjacent-body fit for #22/#28."""
import argparse
from collections import Counter
from hashlib import sha256
from math import hypot,sqrt,cos,pi,sin
from pathlib import Path
import os,re,struct,sys
ROOT=Path(__file__).resolve().parents[1]
BASE=Path(os.getenv("LUANTTD_BASE",str(ROOT))).resolve()
sys.path.insert(0,str(BASE/"tests"))
from chaney_jubilee_art import projected_groups,tread_clearance,planar
from rail_span_art import along_ray,load
from small_airport_art import intersects
import rail_wagon_art
from collections import defaultdict
MODELS=ROOT/"mods/luanttd_core/models"
TEXTURES=ROOT/"mods/luanttd_core/textures"
ENGINES="d90c9b2ae091a740522b0f79078c3e5db32b2467cb2a9e0e96592c3c39ee1f74"
SPRITES="7c31b04e7cd5189e2849e0085f163ebc157d9c878135b7c086b83ebda0bd4b57"
POWER="rail_sh_125"
MAIL="rail_mail_van"
AXLES={POWER:(-.271,-.177,.175,.269),MAIL:(-.286,-.191,.191,.286)}

def source(o):
    if o.engines:
        b=o.engines.read_bytes();assert sha256(b).hexdigest()==ENGINES
        s=b.decode()
        assert re.search(r"MT\(\s*20820,\s*20,\s*20,\s*25,\s*CT_MAIL\s*,\s*LandscapeTypes\(\{T\s*\}\)\),\s*//\s*22 SH '125'",s)
        assert re.search(r"RVI\(\s*6,\s*M,\s*20,\s*200,\s*4500,\s*70,\s*190,\s*RC_D,\s*4,\s*R,\s*D\),\s*//\s*22 SH '125'",s)
        assert re.search(r"MW\(\s*1827,\s*20,\s*20,\s*50,\s*CT_MAIL\s*,\s*LandscapeTypes\(\{T,A,S,Y\}\)\),\s*//\s*28 Mail Van",s)
        assert re.search(r"RVI\(\s*35,\s*W,\s*228,\s*0,\s*0,\s*21,\s*0,\s*RC_W,\s*30,\s*R,\s*A\),\s*//\s*28 Mail Van",s)
        assert "#define M RailVehicleType::Multihead" in s and "#define W RailVehicleType::Wagon" in s
        assert re.search(r'#define RVI\([^\n]+\{ a, b, c, j, j, 0, d, e, f, g, h, k, i, 0, 0, VE_DEFAULT, 0, 76, 0, 0, 0 \}',s)
        print("PASS exact 16.0-RC1 MT/RVI #22 (two 4-mail heads) and MW/RVI #28 (30 mail), both stock full length.")
    if o.sprites:
        b=o.sprites.read_bytes(); assert sha256(b).hexdigest()==SPRITES
        s=b.decode()
        def a(n):
            t=re.search(rf'{n}\[\]\s*=\s*\{{([^}}]+)}}',s)[1]
            return [int(v,0) for v in re.findall(r"0x[\da-fA-F]+|\b\d+\b",re.sub(r"//[^\n]*","",t))]
        assert [tuple(a(k)[i] for k in ("_engine_sprite_base","_engine_sprite_and","_engine_sprite_add","_wagon_full_adder"))
                for i in (6,7,35)]==[(2941,7,0,0),(2941,7,4,0),(2741,3,0,0)]
        print("PASS stock sprite directions 6/7 on base 2941 (rear +4); mail image 35/base 2741. No alternate load meshes.")

def faces(path):
    group=None;out=defaultdict(list);v=[];used_uv=[]
    for line in path.read_text().splitlines():
        if line.startswith("o "):group=line[2:]
        if line.startswith("v "):
            x,y,z=map(float,line[2:].split());v.append((-x/10,z/10,y/10))
        if line.startswith("vt "):
            x,y=map(float,line[3:].split());assert 0<x<1 and y==.5
            used_uv.append(x)
        if line.startswith("f "):
            ids=[tuple(map(int,el.split("/"))) for el in line[2:].split()]
            assert len({t[1] for t in ids})==1
            p=[v[t[0]-1] for t in ids]
            assert len(set(p))>=3,(group,len(set(p)),p)
            out[group].append(p)
    return out,used_uv

def fixtures(m,key,treads):
    points={(round(x,4),round(h,4)) for p in m.values() for x,z,h in p}
    dep=load("bl_rail_depot_1")
    porch=[f for n,f in dep if n=="Dressed_stone_arch_voussoirs"]
    pl=load("bl_rail_platform_2")
    closed={"Dressed_stone_platform","Platform_coping_and_tactile_edge","Platform_canopy","Cast_shelter_posts"}
    platform=min(x for n,f in pl if n in closed for x,z,h in f)
    assert platform-max(abs(x) for x,h in points)>.08
    x_min=min(abs(v[0]) for n,f in dep if n in {"Brick_side_walls","Stone_jambs"} for v in f)
    assert x_min-max(abs(x) for x,h in points)>.07,(key,x_min)
    back=max(z for n,f in dep if n=="Cast_end-of-track_buffer" for _,z,_ in f)
    assert -.499-back>.17
    roof=[f for n,f in dep if n in ("Slate_roof","Standing_seam_roof","Slate_roof_fascia")]
    safety=[]
    for x,h in points:
        yy=h-.386
        for z in (-.58,0,.54,.574,.627):
            hits=list(along_ray(roof,2,x,z))+list(along_ray(porch,2,x,z))
            if hits:safety.append(min(hits)-yy)
    assert min(safety)>.045,(key,min(safety))
    portal=[f for n,f in load("bl_rail_tunnel_portal_1") if n=="Coursed_brick_intrados"]
    for x,h in points:
        for z in (.65,.77,.92):
            pitch=list(along_ray(portal,2,x,z))
            assert pitch and h-.386+.035<min(pitch),(key,x,h,z)
    # Physically test tire patches against each mirrored ST-track native
    # exact 45° railhead in three poses, including both ports near seams.
    samples=0
    ports={4:((-1,0),(0,-1)),8:((1,0),(0,1)),16:((1,0),(0,-1)),32:((-1,0),(0,1))}
    for mask,(a,b) in ports.items():
        asset=load(f"bl_rail_eased_{mask}_3")
        rails=[[(x,z) for x,z,y in f] for n,f in asset if n=="Polished_railhead" and all(abs(y+.386)<1e-5 for x,z,y in f)]
        assert rails
        u,v=(b[0]-a[0])/sqrt(2),(b[1]-a[1])/sqrt(2)
        for offset in (.35,.45,.55,.65):
            cx,cz=a[0]+(b[0]-a[0])*offset,a[1]+(b[1]-a[1])*offset
            for side,z,x0,x1 in treads:
                for rot in (-1,1):
                    z0=z*rot
                    seg=[(cx+u*z0-v*rot*x,cz+v*z0+u*rot*x) for x in (x0,x1)]
                    assert any(intersects(seg,q) for q in rails), (key,mask,z,side,offset)
                    samples+=1
    print(f"PASS {key}: {tread_clearance(treads):,} straight/curve tread overlaps, {samples} exact eased-diagonal tread samples, "
          f"{len(points)*3:,} portal rays; depot roof minimum {min(safety):.5f}, platform coping horizontal minimum "
          f"{platform-max(abs(x) for x,h in points):.5f}.")

def shape(key):
    g,uv=faces(MODELS/f"bl_{key}.obj")
    stock="Closed_formed_SH_125_monocoque_pressure_hull" if key==POWER else "Closed_steel_postal_van_monocoque_with_rounded_clerestory"
    hull=g[stock];assert len(hull)>130
    edge=Counter(tuple(sorted((a,b))) for f in hull for a,b in zip(f,f[1:]+f[:1]))
    assert set(edge.values())=={2},(stock,Counter(edge.values()))
    if key==POWER:
        assert max(z for p in g["Raked_two_separately_glazed_broad_cab_panes"] for x,z,h in p)<-.230
        assert min(z for p in g["Distinct_rear_vestibule_inset_small_window_glass"] for x,z,h in p)>.44
        assert len(g["Fifteen_distinct_steel_radiator_louvres_on_each_drive_side"])>=180
        assert len(g["Open-plan_radial_powder-coated_fan_grille_ribs"])>=180
    else:
        assert len(g["True_vertical_hinge_knuckles_and_exposed_pins"])>=110
        assert len(g["External_real_bars_on_separate_monitored_pane"])>=70
        assert len(g["Two_separate_inset_double_loading_door_leaves_on_each_side"])>=25
        assert len(g["Guarded_dark_aperture_glazing_fitted_into_a_mail_door"])>=24
    orig=rail_wagon_art.MODELS;rail_wagon_art.MODELS=MODELS
    try:m=rail_wagon_art.mesh(key)
    finally:rail_wagon_art.MODELS=orig
    q=m["Coupler_knuckles"]
    assert min(z for x,z,h in q)==-.499 and max(z for x,z,h in q)==.499
    assert abs((min(h for x,z,h in q)+max(h for x,z,h in q))/2-.157)<1e-6
    assert abs(min(h for x,z,h in m["True_inner_DMU_railhead_flange"])+.009)<1e-6
    whe=AXLES[key];assert min(b-a for a,b in zip(whe,whe[1:]))>.088
    contact=[]
    for s,name in ((-1,"L"),(1,"R")):
        t=m[f"Rolling_tread_DMU_{name}"]
        assert min(h for x,z,h in t)==0
        assert {z for x,z,h in t if h==0}==set(whe)
        for a in whe:
            xs=[x for x,z,h in t if z==a and h==0]
            contact.append((s,a,min(xs),max(xs)))
    png=(TEXTURES/f"bl_{key}.png").read_bytes()
    width,height=struct.unpack_from(">II",png,16)
    assert width==len(uv)*8 and height==8
    assert (ROOT/"art"/f"{key}.blend").stat().st_size>130000
    fixtures(m,key,contact)
    print(f"PASS {key}: watertight pressure hull, 8 wheels, body max width/height = "
          f"{2*max(abs(x) for p in m.values() for x,z,h in p):.5f}/{max(h for p in m.values() for x,z,h in p):.5f}.")
    return m

def couples(a,b):
    count=0
    for x,y in ((a,a),(a,b),(b,a),(b,b)):
        A,B=projected_groups(x),projected_groups(y)
        for hand in (-1,1):
            for ra in (False,True):
                for rb in (False,True):
                    for i in range(125):
                        t=-.46+i*.023
                        ahead=[(n,h0,h1,planar(p,t,hand,ra)) for n,h0,h1,p in A]
                        behind=[(n,h0,h1,planar(p,t-1,hand,rb)) for n,h0,h1,p in B]
                        for ka,a0,a1,(x0,x1,z0,z1,p) in ahead:
                            for kb,b0,b1,(u0,u1,w0,w1,q) in behind:
                                if min(a1,b1)-max(a0,b0)<1e-4 or x0>u1 or x1<u0 or z0>w1 or z1<w0:continue
                                assert not intersects(p,q),(ka,kb,hand,ra,rb,t)
                        count+=1
    print(f"PASS {count:,} coupled curve and straight poses for all adjacent combinations of the two bodies and reciprocal orientations.")

if __name__=="__main__":
    cli=argparse.ArgumentParser()
    cli.add_argument("--engines",type=Path);cli.add_argument("--sprites",type=Path)
    args=cli.parse_args()
    source(args)
    a,b=shape(POWER),shape(MAIL)
    assert (TEXTURES/f"bl_{POWER}.png").read_bytes()!=(TEXTURES/f"bl_{MAIL}.png").read_bytes()
    couples(a,b)
    print("STOCK_RAIL_F_ART_PASS")
