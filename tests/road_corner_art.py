#!/usr/bin/env python3
"""Stock short road curves clear every modeled tread sample and keep all seams."""
from collections import defaultdict
from math import floor
from pathlib import Path
import sys

from PIL import Image

from foster_bus_art import TRACE, cast, runner
from small_airport_art import obj

ROOT=Path(__file__).resolve().parents[1]
TEX=ROOT/"mods/bayline/textures"
MODEL=ROOT/"mods/bayline/models"
sys.path.insert(0,str(ROOT/"tools"))

from road_surface_raster import ASPHALT, CORNERS, STRIPE, connector, road_raster, rotate, straight_pixel
from build_sloped_road_art import flat_world_raster, test as edge_test

STEMS={"foster_bus":.40,"leopard_bus":.40,"town_flyer":.42,"coach":.42,"truck":.40,
       "balogh_goods_truck":.42,"mail_van":.43,"coal_tipper":.42,"witcombe_wood_truck":.42}
PAVED=(ASPHALT,STRIPE)
SUBDIVISIONS=16


def visual():
    parts={}
    surfaces=[]
    for mask in range(16):
        ribbon=road_raster(mask)
        committed=Image.open(TEX/f"bl_road{mask}.png").convert("RGBA")
        assert ribbon.tobytes()==committed.tobytes(),mask
        if mask in CORNERS:
            before={(x,z) for x in range(32) for z in range(32)
                    if straight_pixel(mask,x,z) in PAVED}
            after={(x,z) for x in range(32) for z in range(32) if ribbon.getpixel((x,z)) in PAVED}
            assert len(after-before)==81 and len(before-after)==1
            assert not any(connector(*p) for p in before^after)
            # Flood fill from one of the road arms: no isolated paint
            # fragments or broken intermediate row in the bend.
            todo=[next(iter(after))]
            seen=set(todo)
            for x,z in todo:
                for dx,dz in ((1,0),(-1,0),(0,1),(0,-1)):
                    p=x+dx,z+dz
                    if p in after and p not in seen: todo.append(p);seen.add(p)
            assert seen==after
            seed=road_raster(6)
            assert all(seed.getpixel((x,z))==ribbon.getpixel(rotate(x,z,CORNERS[mask]))
                       for x in range(32) for z in range(32))
        else:
            # Straight arms, dead ends, three-way and four-way works retain
            # each original input pixel, not only the edge centerline.
            assert all(ribbon.getpixel((x,z))==straight_pixel(mask,x,z)
                       for x in range(32) for z in range(32)),mask
        for x in range(32):
            for z in range(32):
                if connector(x,z):
                    assert ribbon.getpixel((x,z))==straight_pixel(mask,x,z)
        surface=Image.open(TEX/f"bl_road_surface_{mask}.png").convert("RGB")
        assert surface.tobytes()==flat_world_raster(mask).tobytes(),mask
        surfaces.append(surface)
        town=Image.new("RGB",(32,32))
        for q in range(4):
            img=Image.open(TEX/f"bl_town_street_{mask}_{q}.png").convert("RGB")
            town.paste(img,(q%2*16,q//2*16))
        town=town.transpose(Image.Transpose.FLIP_TOP_BOTTOM)
        assert all(town.getpixel((x,z))==ribbon.getpixel((x,z))[:3]
                    for x in range(32) for z in range(32) if ribbon.getpixel((x,z))[3]),mask
        parts[mask]={p for x in range(32) for z in range(32) if ribbon.getpixel(p:=(x,z)) in PAVED}
    edge_test(surfaces)
    return parts


def stock(parts):
    # Use exactly the source-port frames and presentation. Check 16
    # subposes between stock pulses; no interpolation or speed code changes.
    runner.SAMPLE=TRACE.replace("for l=0,8",f"for l=0,{SUBDIVISIONS}").replace("l/8",f"l/{SUBDIVISIONS}")
    boards=defaultdict(dict)
    samples=[]
    for key,side,x,z,a in runner.trace():
        tag,i,j=key.split("_")
        k=int(i),int(j)
        if tag=="board":boards[k][int(x),int(z)]=side
        else:samples.append((k,x,z,a))
    assert len(samples)==12784
    fixes={}
    for key,scale in STEMS.items():
        v,_=obj(MODEL/f"bl_{key}.obj")
        floor_y=min(y for x,y,z in v)
        tires={(x*scale,z*scale) for x,y,z in v if abs(y-floor_y)<1e-7}
        assert len(tires)>=4,key
        tracks=defaultdict(list)
        for x,z in tires:tracks[(x<0,z<0)].append((x,z))
        points=set(tires)
        # Test each contact-line interior as well as vertices of the
        # authoring tire rings. Most vehicles yield exactly 4 treads.
        for t in tracks.values():
            if len(t)==2:
                (x,z),(X,Z)=t
                points.update((x+(X-x)*k/4,z+(Z-z)*k/4) for k in (1,2,3))
        saved=0
        for k,x,z,heading in samples:
            for px,pz in cast(points,x,z,heading):
                tx,tz=floor((px+.5)/2),floor((pz+.5)/2)
                mask=boards[k].get((tx,tz))
                if mask is None:
                    raise AssertionError((key,k,px,pz,"left five connected stock tiles"))
                i,j=floor((px-2*tx+.5)*16),floor((pz-2*tz+.5)*16)
                if straight_pixel(mask,i,j) not in PAVED: saved+=1
                assert (i,j) in parts[mask],(key,k,mask,i,j,x,z,heading)
        fixes[key]=saved
    assert all(n>0 for n in fixes.values())
    print("Prior asphalt misses now on asphalt:",fixes)
    print(f"ROAD_CORNER_ART_PASS: {len(samples):,} poses × {len(fixes)} vehicle models; zero tire-contact misses.")


if __name__=="__main__":
    stock(visual())
