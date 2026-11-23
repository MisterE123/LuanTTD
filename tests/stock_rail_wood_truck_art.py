#!/usr/bin/env python3
"""Verify original real stock Wood Truck rack and log mesh dimensions and provenance."""
import argparse,re,struct
from pathlib import Path
import stock_rail_metals_art as base

p=argparse.ArgumentParser()
for k in ("engines","sprites","opengfx"):p.add_argument("--"+k,type=Path)
o=p.parse_args()
if o.engines:
    t=base.get(o.engines,base.geo.ENGINES)
    assert re.search(r"MW\(\s*1827,\s*20,\s*20,\s*50,\s*CT_WOOD\s*,\s*LandscapeTypes\(\{T,A,S\s*\}\)\),\s*//\s*34\s+Wood Truck",t)
    assert re.search(r"RVI\(\s*40,\s*W,\s*181,\s*0,\s*0,\s*16,\s*0,\s*RC_W,\s*30,\s*R,\s*A\),\s*//\s*34\s+Wood Truck",t)
if o.sprites:
    text=base.get(o.sprites,base.geo.SPRITES)
    def array(name):
        s=re.search(rf'{name}\[\]\s*=\s*\{{([^}}]+)}}',text)[1]
        return [int(u,0) for u in re.findall(r"0x[\da-fA-F]+|\b\d+\b",re.sub(r"//[^\n]*","",s))]
    assert tuple(array(n)[40] for n in ("_engine_sprite_base","_engine_sprite_and","_engine_sprite_add","_wagon_full_adder"))==(2765,3,0,24)
if o.opengfx:
    text=base.get(o.opengfx,base.PALETTE_PNML)
    for state,img in (("empty",2765),("full",2789)):
        assert re.search(rf'wood wagon \({state}\)\s+base_graphics spr{img}\({img}, "sprites/png/trains/temperate_railwagons_28px.png"\)',text)

key="rail_wood_truck"
e,f=[base.M/f"bl_{key}_{s}.obj" for s in ("empty","loaded")]
assert f.read_bytes().startswith(e.read_bytes())
E,F=(base.geo.faces(x)[0] for x in (e,f))
base.closed(E["Closed_chamfered_timber_flatbed_base"])
assert E["Four_paired_outward-raked_steel_load_restraint_stakes"]
# Verify the platform really is open (no opaque bowl/roof).
assert not list(base.along_ray([a for g,b in E.items() for a in b],0,-.210,.384))
trunks={n:v for n,v in F.items() if n.startswith("Independent_closed_longitudinal_pine_log")}
assert len(trunks)==5
for key_,faces in trunks.items():
    base.closed(faces)
    z=[z for t in faces for x,z,h in t]
    assert min(z)<-.34 and max(z)>.34,(key_,min(z),max(z))
for i in (1,2):base.closed(F[f"Closed_crosswise_packed_log_strap_{i}"])
m=base.mt(key+"_loaded")
assert max(abs(x) for pts in m.values() for x,z,h in pts)<.259
assert max(abs(z) for n,pts in m.items() if n!="Coupler_knuckles" for x,z,h in pts)<.489
q=m["Coupler_knuckles"]
assert {min(z for x,z,h in q),max(z for x,z,h in q)}=={-.499,.499}
assert abs((min(h for x,z,h in q)+max(h for x,z,h in q))/2-.157)<1e-6
contact=[]
for sign,label in ((-1,"L"),(1,"R")):
    v=m["Rolling_tread_"+label]
    assert min(h for x,z,h in v)==0 and {z for x,z,h in v if h==0}==set(base.AXLES)
    for z in base.AXLES:
        xs=[x for x,d,h in v if d==z and h==0]
        assert abs((max(xs)+min(xs))/2-sign*.212)<1e-6
        contact.append((sign,z,min(xs),max(xs)))
dat=(base.T/f"bl_{key}_atlas.png").read_bytes()
assert dat.startswith(b"\x89PNG\r\n\x1a\n") and struct.unpack(">IIBBBBB",dat[16:29])==(512,8,8,2,0,0,0)
assert (base.ROOT/"art"/f"{key}.blend").stat().st_size>100_000
base.geo.fixtures(m,key,contact)
base.geo.couples(m,base.mt("rail_grain_hopper_empty"))
print("STOCK_RAIL_WOOD_TRUCK_ART_PASS")
