#!/usr/bin/env python3
"""Validate the native ordinary crossing art against adjoining road & rail.

Optionally provide the audited OpenTTD 14.1 src/road_cmd.cpp path.
"""
from collections import defaultdict
from math import pi,cos,sin
from pathlib import Path
import sys

from PIL import Image
from small_airport_art import obj,cut,hull,intersects

ROOT=Path(__file__).absolute().parents[1]
M=ROOT/"mods/luanttd_core/models"
T=ROOT/"mods/luanttd_core/textures"
TOP=.114
DECK=.108
EDGE=.3125
GAUGE=.424
FLANGE=(.147,.183)
RAIL_FEATURES=("Polished_railhead","Rail_foot","Rail_web","Ballast_shoulder","Compacted_ballast")
BARRIER="Tapered_striped_movable_crossing_barrier"
ROAD="Joined_two-lane_asphalt_approaches"
GRAVEL="Joined_native_warm_gravel_shoulders"

def source(path):
    s=path.read_text()
    start=s.index("static void DrawTile_Road(TileInfo *ti)")
    b=s[start:start+12000]
    assert "GetCrossingRailAxis" in b and "GetCrossingRoadAxis" in b and "FOUNDATION_LEVELED" in b
    assert "if (IsCrossingBarred(ti->tile)) image += 2" in b
    assert s.count("VALID_LEVEL_CROSSING_SLOPES")>=2

def canonical(v,axis):
    x,h,z=v
    x,z=x-.5,z-.5
    return (x,h,z) if axis==0 else (z,h,-x)

def active_groups(path,axis):
    v,g=obj(path,(0,0))
    c=lambda p:canonical(p,axis)
    assert all(-1.000001<=x<=1.000001 and -1.000001<=z<=1.000001
               for x,_,z in map(c,v)),path
    return {n:[list(map(c,f)) for f in fs] for n,fs in g.items()}

def vals(g,n,pred):
    return [p for f in g[n] for p in f if pred(p)]

def bounds(g):
    return [ (min(xyz),max(xyz)) for xyz in zip(*g) ]

def height(z):
    t=min(1,max(0,(.94-abs(z))/.57))
    return .002+(DECK-.002)*t*t*(3-2*t)

def stripes_match():
    comp=Image.open(T/"bl_level_crossing_atlas.png").convert("RGB")
    old=Image.open(T/"bl_rail_atlas.png").convert("RGB")
    assert comp.crop((0,0,old.width,8)).tobytes()==old.tobytes()
    for axis,mask in enumerate((5,10)):
        native=Image.open(T/f"bl_road_surface_{mask}.png").convert("RGB")
        assert native.size==(32,32)
        px=[native.getpixel((i,0) if axis==0 else (0,i)) for i in range(10,22)]
        assert px==[(154,147,126)]+[(79,82,85)]*10+[(154,147,126)]
        assert comp.getpixel((old.width+4,4))==px[1]
        assert comp.getpixel((old.width+12,4))==px[0]

def validate(axis):
    ref=active_groups(M/f"bl_rail_track_{1<<axis}.obj",axis)
    base=active_groups(M/f"bl_level_crossing_{axis}.obj",axis)
    for s in (-1,1):
        for n in RAIL_FEATURES:
            def end(p):return abs(p[0]-s)<1e-6
            aa=vals(base,n,end);bb=vals(ref,n,end)
            assert aa and bb,n
            assert set(aa)==set(bb),(axis,s,n)
        edge=vals(base,ROAD,lambda p:abs(p[2]-s)<1e-6)
        assert bounds(edge)[0]==(-EDGE,EDGE) and bounds(edge)[1][0]==bounds(edge)[1][1]
        assert abs(edge[0][1]-.002)<1e-6
        shoulder=vals(base,GRAVEL,lambda p:abs(p[2]-s)<1e-6)
        assert bounds(shoulder)[0]==(-.375,.375)
        flag=[p for f in base["Continuous_open_railway_flangeway_floor"] for p in f if s*p[2]>.0]
        a,b=bounds(flag)[2]
        assert abs(a-(FLANGE[0] if s>0 else -FLANGE[1]))<1e-6
        assert abs(b-(FLANGE[1] if s>0 else -FLANGE[0]))<1e-6
        assert max(p[1] for p in flag)<TOP-.029
    assert len(base["Raised_X_railway-crossing_sign_timber_core"])>=48
    assert len(base["Open_pressed_steel_lamp_hoods"])==96
    assert len(base["Green_cast_hinge_standard"])>=48
    assert all(abs(h-height(z))<1e-6 for f in base[ROAD] for x,h,z in f)
    assert all(.107<=p[1]<=.109 for f in base["Seated_rail_crossing_surface_panels"] for p in f)
    authored={}
    for state in ("open","closed"):
        overlay=active_groups(M/f"bl_level_crossing_gate_{axis}_{state}.obj",axis)
        full=active_groups(M/f"bl_level_crossing_{axis}_{state}.obj",axis)
        assert full=={**base,**overlay},state
        lamp="Active_bright_red_approach_lenses" if state=="closed" else "Ruby_standby_lenses"
        assert len(overlay[lamp])>100
        for s in (-1,1):
            arm=[p for f in overlay[BARRIER] for p in f if s*p[2]>0.]
            bb=bounds(arm)
            if state=="open":
                assert min(s*p[0] for p in arm)>EDGE
                assert bb[1][1]>1.16 and bb[1][1]<1.22
            else:
                assert bb[0][0]<-.37 and bb[0][1]>.37
                assert abs(bb[1][0]-.264)<1e-6 and abs(bb[1][1]-.316)<1e-6
            assert abs(s*(bb[2][0]+bb[2][1])/2-.704)<1e-6
        authored[state]=full
    return base,authored

def spatial(groups,lower,upper):
    solids=[]
    for name,fs in groups.items():
        for f in fs:
            if max(y for _,y,_ in f)<lower or min(y for _,y,_ in f)>upper:continue
            poly=cut(cut(f,1,lower,1),1,upper,-1)
            if poly:
                contour=hull((x,z) for x,_,z in poly)
                a,b=zip(*contour)
                solids.append((name,min(a),max(a),min(b),max(b),contour))
    return solids

def pose(prefix,m,angle,dx,dz):
    c,s=cos(angle),sin(angle)
    return [(c*x-s*z+dx,s*x+c*z+dz) for x,z in m]

def collides(a,solids):
    u,w=zip(*a)
    x0,x1,z0,z1=min(u),max(u),min(w),max(w)
    results=set()
    for n,a0,a1,b0,b1,b in solids:
        if a1<x0 or a0>x1 or b1<z0 or b0>z1:continue
        if intersects(a,b):results.add(n)
    return results

def clearance(axis,full):
    # A rigid road model has the exact conservative plan hull of the OBJ
    # at its in-game visual scale. Sample wheel-centre presentation through
    # the open crossing both ways. Use world-ground geometry, excluding
    # only underlying paving/steel at their actual under-tyre height.
    cars=(("bl_coal_tipper_loaded",.42),("bl_leopard_bus",.40),("bl_mail_van",.43))
    tested=0
    for name,scale in cars:
        v,_=obj(M/(name+".obj"))
        a=hull((x*scale,z*scale) for x,_,z in v)
        roof=max(y*scale for _,y,_ in v)
        fixtures={n:fs for n,fs in full["open"].items() if min(p[1] for f in fs for p in f)>.117 or
                  any(y>.17 for f in fs for _,y,_ in f)}
        solids=spatial(fixtures,.018,roof+DECK+.020)
        for d in (-1,1):
            x=.155*d
            angle=0 if d==1 else pi
            for i in range(121):
                z=(i-60)*.025
                assert not collides(pose(name,a,angle,x,z),solids),(axis,name,d,z)
                tested+=1
    # Both closed gates touch the drivable lanes and sit genuinely below a
    # passing loaded cab's roof. They remain out of the full-width rail sweep.
    shut={BARRIER:full["closed"][BARRIER]}
    head=.704
    coal,_=obj(M/"bl_coal_tipper_loaded.obj")
    roof=max(y*.42 for _,y,_ in coal)
    coal_plan=hull((x*.42,z*.42) for x,_,z in coal)
    for s in (-1,1):
        arm=spatial(shut,height(head)+.01,height(head)+roof+.01)
        for d in (-1,1):
            assert BARRIER in collides(pose("coal",coal_plan,0,s*.155,s*head),arm)
    # Longitudinal track sweep uses full real steam and wagon geometry.
    # Run alongside barrier masts, both gates and lamps in both positions.
    for name in ("bl_steam","bl_rail_open_wagon","bl_rail_passenger_wagon"):
        v,_=obj(M/(name+".obj"))
        train=hull((x,z) for x,_,z in v)
        for g in full.values():
            solids=spatial(g,TOP+.002,TOP+max(y for _,y,_ in v))
            for i in range(121):
                x=(i-60)*.028
                assert not collides(pose(name,train,pi/2,x,0),solids),(axis,name,x)
                tested+=1
    return tested

if __name__=="__main__":
    if len(sys.argv)>1:source(Path(sys.argv[1]))
    stripes_match()
    n=0
    for axis in (0,1):
        _,g=validate(axis)
        n+=clearance(axis,g)
    a,_=obj(M/"bl_level_crossing_arm.obj")
    assert -.904<=min(x for x,_,_ in a)<=-.902 and max(x for x,_,_ in a)>.145
    assert min(y for _,y,_ in a)>-.06
    assert (ROOT/"art/level_crossing.blend").is_file()
    print(f"PASS: complete 2-axis rail and road seam match, true wheel flangeways, two bright/dark states, {n:,} full truck/bus/van/engine/wagon clearance poses, and both closed barriers intercept the driving lanes.")
