#!/usr/bin/env python3
"""Rebuild stock Helidepot/Helistation art and check real visible aircraft clearance."""
from math import hypot
from pathlib import Path
from re import search
import sys

from PIL import Image

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/"tools"))
from build_rotary_airfield_art import (
    APRON, COLORS, FIELDS, MOD, PORTAL_ARCH_CLEAR_Y, category_icon, files,
    make, px_to_native, rgb,
)

RC1_EXPECT={
    "helidepot":(((0,0,"office","north west"),(1,0,"hangar",""),
                 (0,1,"pad","west south"),(1,1,"apron","east south")),
                ((8,24),),(24,4),1976),
    "helistation":(((0,0,"hangar",""),(1,0,"office","north"),(2,0,"pad","north"),
                   (3,0,"pad","north east"),(0,1,"apron","west south"),(1,1,"apron","south"),
                   (2,1,"apron","south"),(3,1,"pad","south east")),
                  ((40,8),(56,8),(56,24)),(8,3),1980),
}


def raw_points(stem):
    p=MOD/"models"/f"bl_stock_{stem}.obj"
    return [tuple(float(v)*.1 for v in line.split()[1:])
            for line in p.read_text().splitlines() if line.startswith("v ")]


def swept_envelope():
    # Body and main-rotor motion, including the asset attachment offsets used
    # by Luanti. Check both models, not arbitrary placeholder dimensions.
    radio={}
    data=(MOD/"airport_airframe_art.lua").read_text()
    for lua_key,stem in (("tricario","tricario_heli"),("guru_x2","guru_x2")):
        chunk=data.split(lua_key+"={",1)[1]
        m=search(r"rotor_offset=\{x=([-\d.]+),y=([-\d.]+),z=([-\d.]+)\}",chunk)
        offx,offy,offz=(float(x)*.1 for x in m.groups())
        body,head=raw_points(stem),raw_points(stem+"_rotor")
        tail=raw_points(stem+"_tail")
        t=search(r"tail_offset=\{x=([-\d.]+),y=([-\d.]+),z=([-\d.]+)\}",chunk)
        tailx,taily,tailz=(float(v)*.1 for v in t.groups())
        # Tail rotates around lateral X; then the whole helicopter can yaw.
        radius=max(max(hypot(x,z) for x,_,z in body),
                   max(hypot(x,z) for x,_,z in head)+hypot(offx,offz),
                   max(hypot(tailx+x,abs(tailz)+hypot(y,z)) for x,y,z in tail))
        height=max(max(y for _,y,_ in body),max(y for _,y,_ in head)+offy,
                   taily+max(hypot(y,z) for _,y,z in tail))
        radio[lua_key]=(radius,height)
    return radio


all_icons=[]
media=0
triangles=0
envelopes=swept_envelope()
category=MOD/"textures/bl_dispatch_rotary_airfields.png"
assert category.read_bytes()==category_icon()
all_icons.append(category)
for field in FIELDS:
    layout,stops,storage,year=RC1_EXPECT[field.name]
    assert field.cells==tuple((kind,edges) for x,z,kind,edges in layout)
    assert (field.park_px,field.depot_px,field.start_year)==(stops,storage,year)
    views=make(field)
    for path,payload in files(field,views).items():
        assert path.read_bytes()==payload,path
        media+=1
        if path.suffix==".obj":
            triangles+=sum(line.startswith(b"f ") for line in payload.splitlines())
    assert len(views)==field.width*2

    for tx,tz,tile,edges in layout:
        a=views[tx,tz]
        geom=[p for faces in a.parts.values() for _,f in faces for p in f]
        assert all(-.5<=x<=1.5 and -.5<=z<=1.5 for x,y,z in geom)
        aprons=a.parts["01 Continuous airfield concrete"]
        concrete,=[f for m,f in aprons if m=="Apron aggregate"]
        assert set(concrete)=={(x,APRON,z) for x in (-.5,1.5) for z in (-.5,1.5)}
        assert ("04 Low steel perimeter guardrail (RC1 fence edges)" in a.parts)==bool(edges)

        if tile=="pad":
            pad=a.parts["03 Marked helicopter stand"]
            cx,cz=next((x-tx*2,z-tz*2) for x,z in map(px_to_native,stops)
                       if -.5<x-tx*2<1.5 and -.5<z-tz*2<1.5)
            assert (cx,cz)==(.5,.5)
            inset,=[f for m,f in pad if m=="Deck inset"]
            assert min(x for x,y,z in inset)<cx<max(x for x,y,z in inset)
            assert min(z for x,y,z in inset)<cz<max(z for x,y,z in inset)
            assert len(inset)==(28 if field.name=="helidepot" else 8)
            assert len([f for m,f in pad if m=="H enamel"])==(33 if field.name=="helidepot" else 3)
            for model,(r,h) in envelopes.items():
                assert r<.940 and h<.65,(model,r,h)
                for _,f in pad:
                    assert all(y<APRON+.040 for x,y,z in f)

        elif tile=="hangar":
            # Largest parked and taxiing rotor sweep must have free clearance
            # all the way to the depot slot, including when it still renders
            # in the last approach frame. An opaque "black door" would fail.
            x,z=px_to_native(storage); cx,cz=x-2*tx,z-2*tz
            assert cx==.5 and -.2<=cz<.1
            portal=a.parts["05 Open southeast helicopter maintenance bay"]
            for model,(radius,height) in envelopes.items():
                assert APRON+height+.12 < PORTAL_ARCH_CLEAR_Y
                for _,f in portal:
                    xmin,xmax=min(p[0] for p in f),max(p[0] for p in f)
                    ymin,ymax=min(p[1] for p in f),max(p[1] for p in f)
                    zmin,zmax=min(p[2] for p in f),max(p[2] for p in f)
                    # Only check the moving volume, not through the deck.
                    obstructs=(xmax>cx-radius and xmin<cx+radius and
                               ymax>APRON+.03 and ymin<APRON+height+.05 and
                               zmax>cz-radius and zmin<1.5)
                    assert not obstructs,(model,"obstruction in open hangar",(_,f))
        elif tile=="office":
            hall=a.parts["07 Terminal checked luggage and waiting room"]
            assert max(y for _,f in hall for x,y,z in f)<.5
            assert "08 Recessed windows, passenger doors and entrance canopy" in a.parts

    source=ROOT/f"art/{field.name}.blend"
    assert source.stat().st_size<250_000
    assert source.read_bytes().startswith((b"BLENDER",b"\x28\xb5\x2f\xfd"))
    atlas=Image.open(MOD/"textures"/f"bl_{field.name}_atlas.png")
    assert atlas.size==(256,16)
    for i,key in enumerate(COLORS):
        assert atlas.getpixel((6*i+3,8))==rgb(key)
    all_icons.append(MOD/"textures"/f"bl_dispatch_{field.name}.png")

all_icons.append(MOD/"textures/bl_dispatch_heliport.png")
different=set()
for f in all_icons:
    a=Image.open(f).convert("RGBA")
    assert a.size==(32,32) and a.getpixel((0,0))[3]==0
    opaque=sum(a.getpixel((x,y))[3]>240 for x in range(32) for y in range(32))
    assert 220<opaque<770,(f,opaque)
    different.add(a.tobytes())
assert len(different)==4
assert 4000<triangles<11000,triangles
print(f"PASS rotary aviation artwork: 4/8 RC1 sections, 1/3 stands, 2 stock airframes clearance, {media+1} deterministic media, {triangles} triangles")
