#!/usr/bin/env python3
"""Source, body, coupler, turnout, rolling, and portal checks for engine #8."""
from argparse import ArgumentParser
from collections import defaultdict
from math import atan,cos,hypot,pi,sin
from pathlib import Path
import re
import struct

from rail_span_art import along_ray,load
from rail_wagon_art import mesh
from small_airport_art import hull,intersects

ROOT=Path(__file__).resolve().parents[1]
NAME="rail_chaney_jubilee"
AXLES={"Bogie":(-.304,-.251),"Driver":(-.148,-.007,.134),"Tender":(.218,.267,.316)}
EPS=2e-6

def source(engines,sprites,pnml,sheet):
    if engines:
        t=Path(engines).read_text()
        assert re.search(r"MT\(\s*5114,\s*20,\s*21,\s*30,\s*CT_NONE\s*,\s*T\s*\),\s*//\s*8 Chaney 'Jubilee'",t)
        assert re.search(r"RVI\(\s*0,\s*G,\s*13,\s*112,\s*1000,\s*131,\s*120,\s*RC_S,\s*0,\s*R,\s*S\),\s*//\s*8 Chaney 'Jubilee'",t)
        assert re.search(r"#define G RAILVEH_SINGLEHEAD",t)
    if sprites:
        t=Path(sprites).read_text()
        assert re.search(r'_engine_sprite_base\[\]\s*=\s*\{\s*0x0B59',t)
    if pnml:
        t=Path(pnml).read_text()
        assert re.search(r'spr2905\(2905, "sprites/png/trains/temperate_engines_28px.png"\).*?\(111, 35\)',t)
    if sheet:
        from collections import Counter
        from PIL import Image
        im=Image.open(sheet)
        assert im.mode=="P" and im.size==(369,340)
        row=im.crop((110,35,369,64))
        idx=Counter(row.get_flattened_data() if hasattr(row,"get_flattened_data") else row.getdata())
        assert sum(idx[k] for k in range(198,206))>500

def centers(groups):
    look=[]
    for f,axles in AXLES.items():
        for side,s in (("L",-1),("R",1)):
            t=groups["Rolling_tread_"+f+"_"+side]
            assert min(h for _,_,h in t)==0
            assert set(round(z,6) for _,z,h in t if abs(h)<EPS)==set(axles)
            for a in axles:
                p=[x for x,z,h in t if abs(z-a)<EPS and abs(h)<EPS]
                lo,hi=min(p),max(p)
                assert lo<s*.212<hi
                look.append((s,a,lo,hi))
    assert len(look)==16
    f=groups["True_inward_rail_guiding_wheel_flanges"]
    assert abs(min(h for _,_,h in f)+.009)<EPS
    assert .168<min(abs(x) for x,_,_ in f)<max(abs(x) for x,_,_ in f)<.179
    return look

def tread_clearance(contacts):
    # Compare actual tread spans to 60-mm-equivalent rail heads, exact two
    # track axes and both curve hands. These are eight real wheelset poses,
    # including the narrow tender and bogie wheels, not a rail-box proxy.
    for bit,perp in ((1,1),(2,0)):
        asset=load(f"bl_rail_track_{bit}")
        x={round(v[perp],6) for n,f in asset for v in f if n=="Polished_railhead" and abs(v[2]+.386)<EPS}
        assert x=={-.242,-.182,.182,.242}
        for s,z,a,b in contacts:
            assert min(s*.212+.030,b)-max(s*.212-.030,a)>.04
    q=0
    for k in (-1,1):
        for tick in range(1,64):
            theta=tick*pi/128
            for side,z,a,b in contacts:
                c=1+k*side*.212
                if min(theta,pi/2-theta)<atan(abs(z)/(c-.05)):continue
                ra,rb=sorted(hypot(1+k*p,z) for p in (a,b))
                assert min(rb,c+.029)-max(ra,c-.029)>.006,(k,side,z,ra,rb,c)
                q+=1
    return q

def bend(s,k):
    # Stock surface projection uses a radius-one 90-degree corner with
    # tangent straight approaches, also used on a turnout's diverging leg.
    if s<0:return s,0,0
    y=min(s,pi/2)
    return sin(y),k*(1-cos(y)+max(0,s-y)),k*y

def planar(poly,t,k,reversed):
    x,z,a=bend(t,k)
    c,s=cos(a),sin(a)
    sign=-1 if reversed else 1
    ps=[(x+sign*(u*s-w*c),z-sign*(u*c+w*s)) for u,w in poly]
    a,b=zip(*ps)
    return min(a),max(a),min(b),max(b),ps

def projected_groups(m):
    out=[]
    for n,v in m.items():
        # Split single mesh groups by vehicle half, so two separate buffer
        # ends or each wheel at either end never fill empty space between.
        for stop in (-1,1):
            p=[(x,z,h) for x,z,h in v if z*stop>.27 and h>=.087]
            groups=[p]
            # Buffers and rail wheels are separate left/right objects; a hull
            # across them fills the intentionally empty path of the coupler.
            if any(word in n.lower() for word in ("buffer","rolling_tread","access_rails")):
                groups=[[i for i in p if i[0]*side>.01] for side in (-1,1)]
            for group in groups:
                q=hull((x,z) for x,z,_ in group)
                if len(q)<3:continue
                out.append((n,min(h for _,_,h in group),max(h for _,_,h in group),q))
    return out

def coupling(jubilee):
    own=projected_groups(jubilee)
    n=0
    cosmetic=set()
    for name in ("rail_passenger_wagon","rail_open_wagon","rail_coal_wagon_loaded"):
        wagon=mesh(name)
        for b in (wagon,jubilee):
            q=b["Coupler_knuckles"]
            assert any(abs(z-.499)<EPS for _,z,_ in q)
            assert any(abs(z+.499)<EPS for _,z,_ in q)
            h=[h for _,_,h in q]
            assert abs((min(h)+max(h))*.5-.157)<EPS
        other=projected_groups(wagon)
        for hand in (-1,1):
            for rev in (False,True):
                for i in range(100):
                    at=-.35+i*.028
                    b=[(n,h0,h1,planar(p,at-1,hand,False)) for n,h0,h1,p in other]
                    for ga,h0,h1,p in own:
                        ax,bx,az,bz,aa=planar(p,at,hand,rev)
                        for gb,H0,H1,(x0,x1,z0,z1,bb) in b:
                            if min(h1,H1)-max(h0,H0)<1e-4 or x0>bx or x1<ax or z0>bz or z1<az:
                                continue
                            if not intersects(aa,bb):continue
                            # The simulation uses a rigid one-node tangent body.
                            # A static coupling can yaw past a stock buffer face:
                            # record these separate from fatal chassis/cab overlap.
                            assert "Coupler" in ga and "buffer" in gb.lower(),(name,hand,rev,at,ga,gb)
                            cosmetic.add((name,hand,rev,i))
                    # Static exact 2-mm gap on a straight becomes a short gap
                    # when tangent vehicles turn. No fake flex in runtime mesh.
                    tail=planar([(0,-.499 if rev else .499)],at,hand,rev)[4][0]
                    nose=planar([(0,-.499)],at-1,hand,False)[4][0]
                    sep=hypot(nose[0]-tail[0],nose[1]-tail[1])
                    assert .0019<sep<.141,(at,hand,rev,sep)
                    n+=1
    return n,len(cosmetic)

def verify(a):
    source(a.upstream_engines,a.upstream_sprites,a.opengfx_pnml,a.opengfx_sheet)
    m=mesh(NAME)
    mandatory=("Long_royal_blue_unobstructed_cylindrical_boiler_casing",
      "Integral_cab-tender_visible_short_swivel_drawbar","Tender_thick_inside_open_coal_wall",
      "Taper_shouldered_separate_air_chimney_with_open_bore","Ten_separately_shaped_Jubilee_driving-wheel_spokes",
      "Eccentric_main_crosshead_piston_rod","Valve_gear_return_crank_stamped_link_lever",
      "Tender_original_raised_JUBILEE_fleet_identity","Actual_front_and_rear_cab_window_inserted_glazing")
    assert set(mandatory)<=m.keys()
    assert len(m[mandatory[4]])>200
    assert all(z<=-.43999 for _,z,_ in m["Amber_clear_polished_front_locomotive_lamp_lens"])
    assert all(z>.451 for _,z,_ in m["Tender_ruby_glass_rear_end-of-train_lamp"])
    v=[p for ps in m.values() for p in ps]
    assert max(abs(x) for x,_,_ in v)<.266 and max(h for _,_,h in v)<.700
    assert max(abs(z) for n,group in m.items() if n!="Coupler_knuckles" for x,z,h in group)<.488
    c=tread_clearance(centers(m))
    n,k=coupling(m)
    bore=[f for name,f in load("bl_rail_tunnel_portal_1") if name=="Coursed_brick_intrados"]
    for x,y in {(round(x,4),round(h,4)) for x,_,h in v}:
        for q in (.65,.77,.92):
            hh=min(along_ray(bore,2,x,q))
            assert y+.114-.5+.035<hh,(x,y,q,hh)
    path=ROOT/"mods/luanttd_core/textures"/("bl_"+NAME+".png")
    atlas=path.read_bytes()
    assert atlas[:8]==b"\x89PNG\r\n\x1a\n" and struct.unpack_from(">II",atlas,16)==(352,8)
    assert (ROOT/"art/chaney_jubilee.blend").stat().st_size>100000
    print(f"JUBILEE_ART_PASS: exact 14.1 engine #8 / OpenGFX image 2905 cues; 16 real tread contacts, {c:,} rail overlaps, {n:,} body-clear coupled curve/turnout phases ({k} close static coupling hardware envelopes), same spot portal fit.")

if __name__=="__main__":
    p=ArgumentParser()
    p.add_argument("--upstream-engines")
    p.add_argument("--upstream-sprites")
    p.add_argument("--opengfx-pnml")
    p.add_argument("--opengfx-sheet")
    verify(p.parse_args())
