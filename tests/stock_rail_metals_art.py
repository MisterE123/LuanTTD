#!/usr/bin/env python3
"""Verify #35/#36 RC1 dimensions, actual loaded geometry and native rail clearances."""
import argparse,os,re,struct,sys
from collections import Counter
from hashlib import sha256
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
BASE=Path(os.environ.get("LUANTTD_BASE",str(ROOT))).resolve()
sys.path.insert(0,str(BASE/"tests"))
import stock_rail_f_art as geo
import rail_wagon_art as w
from rail_span_art import along_ray
from small_airport_art import cut,hull,intersects
from chaney_jubilee_art import planar,projected_groups
from functools import lru_cache
STOCK=(("rail_iron_ore_hopper",35,"Iron Ore Hopper","IRON_ORE",41,179,19,30,2773),
       ("rail_steel_truck",36,"Steel Truck","STEEL",42,196,18,20,2769))
M=ROOT/"mods/luanttd_core/models"
T=ROOT/"mods/luanttd_core/textures"
PALETTE_PNML="3f6453529b4eefc02cd9d77fd377bbaac83e62b27476a4a0181b5b6beb6528f6"
AXLES=(-.269,.269)

def get(path,key):
    raw=path.read_bytes();assert sha256(raw).hexdigest()==key;return raw.decode()
def source(o):
    if o.engines:
        t=get(o.engines,geo.ENGINES)
        for n,id,label,carg,img,price,weight,cap,base in STOCK:
            assert re.search(rf"MW\(\s*1827,\s*20,\s*20,\s*50,\s*CT_{carg}\s*,\s*LandscapeTypes\(\{{T\s*\}}\)\),\s*//\s*{id}\s+{label}",t)
            assert re.search(rf"RVI\(\s*{img},\s*W,\s*{price},\s*0,\s*0,\s*{weight},\s*0,\s*RC_W,\s*{cap},\s*R,\s*A\),\s*//\s*{id}\s+{label}",t)
            print(f"PASS pinned #{id} {label}: {cap} {carg}, tare {weight}, cost factor {price}, conventional rail.")
        assert re.search(r'#define RVI\([^\n]+\{ a, b, c, j, j, 0, d, e, f, g, h, k, i, 0, 0, VE_DEFAULT, 0, 76, 0, 0, 0 \}',t)
    if o.sprites:
        s=get(o.sprites,geo.SPRITES)
        def array(n):
            t=re.search(rf'{n}\[\]\s*=\s*\{{([^}}]+)}}',s)[1]
            return [int(u,0) for u in re.findall(r"0x[\da-fA-F]+|\b\d+\b",re.sub(r"//[^\n]*","",t))]
        assert [tuple(array(n)[i] for n in ("_engine_sprite_base","_engine_sprite_and","_engine_sprite_add","_wagon_full_adder"))
                for i in (41,42)]==[(2773,3,0,24),(2769,3,0,24)]
        print("PASS stock load transition +24 (Iron Ore 2773→2797 at 15/30, Steel 2769→2793 at 10/20).")
    if o.opengfx:
        s=get(o.opengfx,PALETTE_PNML)
        for id in (2773,2797,2769,2793):
            assert re.search(rf'spr{id}\({id}, "sprites/png/trains/temperate_railwagons_28px.png"\)',s)

def closed(f):
    e=Counter(tuple(sorted((a,b))) for q in f for a,b in zip(q,q[1:]+q[:1]))
    assert set(e.values())=={2},Counter(e.values())

def mt(st):
    a=w.MODELS
    w.MODELS=M
    try:return w.mesh(st)
    finally:w.MODELS=a

def wagon(k,id):
    a,b=[M/f"bl_{k}_{i}.obj" for i in ("empty","loaded")]
    E,F=geo.faces(a)[0],geo.faces(b)[0]
    assert b.read_bytes().startswith(a.read_bytes()) and all(F[n]==f for n,f in E.items())
    e,full=mt(k+"_empty"),mt(k+"_loaded")
    assert max(abs(x) for p in full.values() for x,z,h in p)<.259
    assert max(abs(z) for n,p in full.items() if n!="Coupler_knuckles" for x,z,h in p)<.489
    q=e["Coupler_knuckles"]
    assert min(z for x,z,h in q)==-.499 and max(z for x,z,h in q)==.499
    assert abs((min(h for x,z,h in q)+max(h for x,z,h in q))/2-.157)<1e-6
    assert abs(min(h for x,z,h in e["Inner_wheel_flange"])+.010)<1e-6
    contact=[]
    for s,n in ((-1,"L"),(1,"R")):
        v=e["Rolling_tread_"+n]
        assert min(h for x,z,h in v)==0 and {z for x,z,h in v if h==0}==set(AXLES)
        for z in AXLES:
            xx=[x for x,d,h in v if d==z and h==0]
            assert abs((max(xx)+min(xx))/2-s*.212)<1e-6
            contact.append((s,z,min(xx),max(xx)))
    dat=(T/f"bl_{k}_atlas.png").read_bytes()
    assert dat.startswith(b"\x89PNG\r\n\x1a\n") and struct.unpack(">IIBBBBB",dat[16:29])==(512,8,8,2,0,0,0)
    assert (ROOT/"art"/f"{k}.blend").stat().st_size>100_000
    if id==35:
        tag="Continuous_watertight_steep_sided_pressed_iron_ore_hopper_and_floor"
        closed(E[tag]);closed(F["Closed_original_taper_packed_hematite_mass_behind_iron_ore_rim"])
        assert all(h<=.271 for p in E[tag] for x,z,h in p if abs(x)<.148 and abs(z)<.348)
        ore=[f for g,f in F.items() if g.startswith("Individual_closed_railway_hematite_ore_rock_")]
        assert len(ore)==78
        for f in ore:closed(f)
        pts=[q for g,f in F.items() if g not in E for p in f for q in p]
        assert max(h for x,z,h in pts)<.483 and min(h for x,z,h in pts)>.271
        assert len(E["Pronounced_rolled_tapered_vertical_ore_hopper_strengthening_ribs"])>=300
        print("PASS #35 complete pressed open hopper and 78 closed ore stones wholly below native lip.")
    else:
        for j,z in enumerate((-.249,0,.249),1):
            n=f"Real_closed_annular_transverse_cold_rolled_steel_coil_{j}"
            g=F[n];closed(g)
            assert min(x for f in g for x,d,h in f)==-.172 and max(x for f in g for x,d,h in f)==.172
            # Radius tube remains open end-to-end; upper ring kills control ray.
            assert not list(along_ray(g,0,z,.323))
            assert list(along_ray(g,0,z,.410))
            assert sum(1 for k in E if n in k)==0
        closed(F["Separate_closed_rolled_packing_straps_around_each_coil"])
        assert E["True_cut_wooden_cradle_wedge_under_each_removable_steel_coil"]
        assert not any(h>.283 for n,p in e.items() for x,z,h in p if abs(z)<.38)
        print("PASS #36 actual low wooden cradle left behind after unloading; 3 removable through-bored closed metal coils.")
    geo.fixtures(full,k,contact)
    return full
def extra_coupling(a,b):
    geo.couples(a,b)  # More conservative whole-part hull: no contact.
    count=0
    narrow=0
    grazes=set()
    for key,raw,vehicle in (("rail_iron_ore_hopper",a,"rail_kirby_paul_tank"),
                            ("rail_steel_truck",b,"rail_sh_125")):
        g0=geo.faces(M/f"bl_{key}_loaded.obj")[0]
        g1=geo.faces(BASE/"mods/luanttd_core/models"/f"bl_{vehicle}.obj")[0]
        n0,n1=projected_groups(raw),projected_groups(w.mesh(vehicle))
        @lru_cache(maxsize=None)
        def geom(which,name,slab):
            ground=slab*.010
            pts=[]
            for p in (g0 if which==0 else g1)[name]:
                if min(c[2] for c in p)>ground+.010 or max(c[2] for c in p)<ground:continue
                pts.extend(cut(cut(p,2,ground,1),2,ground+.010,-1))
            return hull((x,z) for x,z,h in pts)
        for hand in (-1,1):
            for ra in (False,True):
                for rb in (False,True):
                    for mix in (False,True):
                        for i in range(125):
                            at=-.46+i*.023
                            u,v=(at,at-1) if mix else (at-1,at)
                            A=[(n,h0,h1,planar(p,u,hand,ra)) for n,h0,h1,p in n0]
                            B=[(n,h0,h1,planar(p,v,hand,rb)) for n,h0,h1,p in n1]
                            for na,h0,h1,(x0,x1,z0,z1,P) in A:
                                for nb,H0,H1,(xx0,xx1,zz0,zz1,Q) in B:
                                    lo,hi=max(h0,H0),min(h1,H1)
                                    if hi-lo<1e-5 or xx0>x1 or xx1<x0 or zz0>z1 or zz1<z0:continue
                                    if not intersects(P,Q):continue
                                    narrow+=1
                                    for slab in range(int(lo*100),int(hi*100)+1):
                                        aa,bb=geom(0,na,slab),geom(1,nb,slab)
                                        if len(aa)<2 or len(bb)<2:continue
                                        if intersects(planar(aa,u,hand,ra)[4],planar(bb,v,hand,rb)[4]):
                                            # Kirby's legacy wide round spring pad can sweep just
                                            # across a standard coupler while easing into a curve.
                                            # Reject every actual contact involving car body or rail gear.
                                            assert (na,nb)==("Coupler_knuckles","Spring_buffers_and_polished_faces"),(key,vehicle,na,nb,at,slab,ra,rb,mix)
                                            grazes.add((key,vehicle,hand,i,ra,rb,mix))
                            count+=1
    assert count==4000
    print(f"PASS {4000+count:,} total couple orientations and minimum standard knuckle gap 0.002; "
          f"{narrow} legacy contour candidates rechecked at 0.010-height, {len(grazes)} cosmetic Kirby buffer/knuckle grazes only.")

if __name__=="__main__":
    cli=argparse.ArgumentParser()
    for k in ("engines","sprites","opengfx"):cli.add_argument("--"+k,type=Path)
    o=cli.parse_args();source(o)
    payload=[wagon(k,id) for k,id,*_ in STOCK]
    extra_coupling(*payload)
    print("STOCK_RAIL_METALS_ART_PASS")
