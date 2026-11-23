#!/usr/bin/env python3
"""Geometry proof for #31 openings and #33 grain payload, plus native station and rail clearances."""
import argparse,re,struct
from pathlib import Path
import stock_rail_metals_art as base
p=argparse.ArgumentParser()
for k in ("engines","sprites","opengfx"):p.add_argument("--"+k,type=Path)
o=p.parse_args()
if o.engines:
    text=base.get(o.engines,base.geo.ENGINES)
    for ID,name,img,price,weight,cap in ((31,"Livestock Van",37,192,20,25),(33,"Grain Hopper",39,182,19,30)):
        assert re.search(rf"RVI\(\s*{img},\s*W,\s*{price},\s*0,\s*0,\s*{weight},\s*0,\s*RC_W,\s*{cap},\s*R,\s*A\),\s*//\s*{ID}\s+{name}",text)
    assert re.search(r"MW\(\s*1827,\s*20,\s*20,\s*50,\s*CT_LIVESTOCK\s*,\s*LandscapeTypes\(\{T,A\s*\}\)\),\s*//\s*31\s+Livestock Van",text)
    assert re.search(r"MW\(\s*1827,\s*20,\s*20,\s*50,\s*MCT_GRAIN_WHEAT_MAIZE,\s*LandscapeTypes\(\{T,A,S\s*\}\)\),\s*//\s*33\s+Grain Hopper",text)
if o.sprites:
    text=base.get(o.sprites,base.geo.SPRITES)
    def array(name):
        s=re.search(rf'{name}\[\]\s*=\s*\{{([^}}]+)}}',text)[1]
        return [int(u,0) for u in re.findall(r"0x[\da-fA-F]+|\b\d+\b",re.sub(r"//[^\n]*","",s))]
    fields=("_engine_sprite_base","_engine_sprite_and","_engine_sprite_add","_wagon_full_adder")
    assert tuple(array(n)[37] for n in fields)==(2749,3,0,0)
    assert tuple(array(n)[39] for n in fields)==(2761,3,0,24)
if o.opengfx:
    text=base.get(o.opengfx,base.PALETTE_PNML)
    for cargo,state,img in (("livestock","full + empty",2749),("grain","empty",2761),("grain","full",2785)):
        assert re.search(rf'{cargo} wagon \({re.escape(state)}\)\s+base_graphics spr{img}\({img}, "sprites/png/trains/temperate_railwagons_28px.png"\)',text)

def fit(key,suffix=""):
    stem=key+suffix
    m=base.mt(stem)
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
    base.geo.fixtures(m,stem,contact)
    return m

live,grain="rail_livestock_van","rail_grain_hopper"
g=base.geo.faces(base.M/f"bl_{live}.obj")[0]
base.closed(g["Independent_weather-black_rolled_livestock_roof"])
side=[f for name,faces in g.items() for f in faces if name not in {"Independent_weather-black_rolled_livestock_roof"}]
for pos in (-.321,-.237,-.127,.127,.237,.321):
    for clear in (.322,.375):
        assert not list(base.along_ray(side,0,pos,clear)),(pos,clear)
    for block in (.300,.349,.398): assert list(base.along_ray(side,0,pos,block)),(pos,block)
E,F=[base.M/f"bl_{grain}_{s}.obj" for s in ("empty","loaded")]
assert F.read_bytes().startswith(E.read_bytes())
e,f=(base.geo.faces(x)[0] for x in (E,F))
base.closed(e["Continuous_closed_flanged_bowl_with_an_empty_recessed_grain_well"])
base.closed(f["Sealed_golden_grain_mass,_sunlit_sloping_shallow_surface"])
seeds=[a for k,a in f.items() if k.startswith("Independent_light_grain_husk")]
assert len(seeds)==84
for seed in seeds:base.closed(seed)
assert max(h for n,g in f.items() if n not in e for p in g for x,z,h in p)<.423
base.geo.couples(fit(live),fit(grain,"_loaded"))
print("STOCK_RAIL_FARM_ART_PASS")
