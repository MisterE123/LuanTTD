#!/usr/bin/env python3
"""Verify one-tile RC1 roof/terminal geometry, facade, and native icon media."""
from collections import Counter
from math import hypot
from PIL import Image
from pathlib import Path
import sys

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/"tools"))
from build_heliport_art import COLORS, DECK, FLOOR, MOD, assets, create, rgb

a=create()
for path,payload in assets(a).items():
    assert path.read_bytes()==payload,path

source=ROOT/"art/heliport.blend"
assert source.stat().st_size<250_000
assert source.read_bytes().startswith((b"BLENDER",b"\x28\xb5\x2f\xfd"))

points=[p for faces in a.parts.values() for _,face in faces for p in face]
assert all(-.5<=x<=1.5 and -.5<=z<=1.5 for x,y,z in points)
assert min(p[1] for p in points)<FLOOR<max(p[1] for p in points)
assert DECK-FLOOR==60/8
byfloor=a.parts["03 Lower stepped terminal annex"]
assert 2.88<max(p[1] for _,f in byfloor for p in f)<2.91

roof=a.parts["08 Eight-sided reinforced landing deck"]
assert max(p[1] for _,f in roof for p in f)==DECK
cap,= [f for mat,f in roof if mat=="asphalt"]
cx,cz=5/8-.5,9/8-.5
assert min(p[0] for p in cap)<cx<max(p[0] for p in cap)
assert min(p[2] for p in cap)<cz<max(p[2] for p in cap)
paint=a.parts["09 Landing ring and touchdown surface"]
assert len(paint)==35  # 32 rim quads + 3 real painted H strips
assert all(DECK+.001<=y<=DECK+.00301 for _,f in paint for x,y,z in f)
for _,face in paint[:32]:
    assert all(.5059<=hypot(x-cx,z-cz)<=.5511 for x,_,z in face)
for _,f in paint:
    # Clockwise viewed from above in X/Z projects to a +Y-facing Luanti
    # surface, and the primer remains visible from the approach.
    ax,_,az=f[0]
    bx,_,bz=f[1]
    cx1,_,cz1=f[2]
    assert (bz-az)*(cx1-ax)-(bx-ax)*(cz1-az)>0

# A plausible partial implementation places glass a storey above or
# outside its stair-stepped box. Neither approximation is acceptable.
glazed=a.parts["04 Upper bronze mullions, shade vanes and recessed ribbon glass"]+a.parts["05 Lower terminal glazing"]
for _,face in glazed:
    assert all(y<2.713 for x,y,z in face if x>1.36)
    assert all(z<=1.38 for x,y,z in face)
assert len(glazed)>560

atlas=Image.open(MOD/"textures/bl_heliport_atlas.png")
assert atlas.size==(128,16)
for i,key in enumerate(COLORS):
    assert atlas.getpixel((5*i+2,8))==rgb(key)
icon=Image.open(MOD/"textures/bl_dispatch_heliport.png").convert("RGBA")
assert icon.size==(32,32)
opaque=[icon.getpixel((x,y)) for y in range(32) for x in range(32) if icon.getpixel((x,y))[3]>245]
assert 380<len(opaque)<695
pad=[icon.getpixel((x,y)) for y in range(2,10) for x in range(9,26)]
assert sum(r>208 and g>196 and b<228 and alpha>245 for r,g,b,alpha in pad)>=20
assert icon.getpixel((0,0))[3]==0
assert icon.tobytes()!=Image.open(MOD/"textures/bl_dispatch_city_airport.png").convert("RGBA").tobytes()
mesh=(MOD/"models/bl_heliport_0_0.obj").read_text().splitlines()
counts=Counter(line.split()[0] for line in mesh)
assert 950<counts["f"]<2100
print(f"PASS heliport: one tile, RC1 60px roof and terminal, backed glazing, {counts['f']} triangles, unique 32px icon")
