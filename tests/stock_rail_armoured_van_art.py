#!/usr/bin/env python3
"""Verify #37 noncopied native body, rail gauge, and optional pinned stock references."""
import argparse,re,struct
from pathlib import Path
import stock_rail_metals_art as base

p=argparse.ArgumentParser()
for k in ("engines","sprites","opengfx"):p.add_argument("--"+k,type=Path)
o=p.parse_args()
if o.engines:
    text=base.get(o.engines,base.geo.ENGINES)
    assert re.search(r"MW\(\s*1827,\s*20,\s*20,\s*50,\s*MCT_VALUABLES_GOLD_DIAMONDS,\s*LandscapeTypes\(\{T,A,S\s*\}\)\),\s*//\s*37\s+Armoured Van",text)
    assert re.search(r"RVI\(\s*43,\s*W,\s*255,\s*0,\s*0,\s*30,\s*0,\s*RC_W,\s*20,\s*R,\s*A\),\s*//\s*37\s+Armoured Van",text)
if o.sprites:
    text=base.get(o.sprites,base.geo.SPRITES)
    def array(name):
        s=re.search(rf'{name}\[\]\s*=\s*\{{([^}}]+)}}',text)[1]
        return [int(u,0) for u in re.findall(r"0x[\da-fA-F]+|\b\d+\b", re.sub(r"//[^\n]*","",s))]
    assert tuple(array(name)[43] for name in ("_engine_sprite_base","_engine_sprite_and","_engine_sprite_add","_wagon_full_adder"))==(2777,3,0,0)
if o.opengfx:
    text=base.get(o.opengfx,base.PALETTE_PNML)
    assert re.search(r'valuables wagon \(full \+ empty\)\s+base_graphics spr2777\(2777, "sprites/png/trains/temperate_railwagons_28px.png"\)',text)

key="rail_armoured_van"
face=base.geo.faces(base.M/f"bl_{key}.obj")[0]
base.closed(face["Fully_enclosed_rolled_armour_cabin"])
assert "Original_star-shaped_six_sided_secure_lock_guard" in face
m=base.mt(key)
assert max(abs(x) for v in m.values() for x,z,h in v)<.259
assert max(abs(z) for name,v in m.items() if name!="Coupler_knuckles" for x,z,h in v)<.489
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
base.geo.couples(m,base.mt("rail_iron_ore_hopper_empty"))
print("STOCK_RAIL_ARMOURED_VAN_ART_PASS")
