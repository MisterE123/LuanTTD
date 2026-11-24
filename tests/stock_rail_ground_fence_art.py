#!/usr/bin/env python3
"""Verify every adapted fence form, native anchor offset and cutout material."""
from collections import Counter
from pathlib import Path
from math import hypot
import argparse
import io
import re
import sys

from PIL import Image

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/"tools"))
from build_stock_rail_ground_fence_art import (
    BORDERS, CORNER_REFERENCE, FORMS, PROFILES, MODELS, STEM, TEX,
    assets, POST_FOOT, POST_TOP, WIRE_TOP, WIRE_BOTTOM,
)

EXPECTED={2:("nw",),3:("se",),4:("nw","se"),5:("ne",),6:("sw",),7:("ne","sw"),
          8:("vert",),9:("vert",),10:("horiz",),11:("horiz",)}
DIRECTION_CONSTANT={2:"FenceNW",3:"FenceSE",4:"FenceSENW",5:"FenceNE",6:"FenceSW",7:"FenceNESW",
                    8:"FenceVert1",9:"FenceVert2",10:"FenceHoriz1",11:"FenceHoriz2"}


def floor(x,z,p):
    # Reverse the native coordinates into stock continuous 16-pixel
    # position, independently of the authoring builder.
    u,v=(x+.5)*8,(z+.5)*8
    return {0:0,3:u/16,12:(16-u)/16,6:v/16,9:(16-v)/16}[p]-.5


def expect_source(path):
    text=path.read_text()
    for g,shape in EXPECTED.items():
        fn=re.search(r"case RailGroundType::"+DIRECTION_CONSTANT[g]+r":\s+(.*?)break;",
                     text,re.S)
        assert fn
        statement=fn[1].upper()
        for side in shape:
            stem={"vert":"RFO_FLAT_LEFT" if g==8 else "RFO_FLAT_RIGHT",
                  "horiz":"RFO_FLAT_UPPER" if g==10 else "RFO_FLAT_LOWER"}.get(side,"DRAWTRACKFENCE_"+side.upper())
            assert stem in statement
    # Verify the flat crossing point matches the original corner's
    # 8+8 sort anchor; the corner is height, not an X/Z displacement.
    for g,key in CORNER_REFERENCE.items():
        assert re.search(r"\{Corner::"+key+r",\s+8,\s+8,\s+1,\s+1\}",text)
    for offsets in ("0, 1, 16, 1","1, 0, 1, 16","0, 15, 16, 1","15, 0, 1, 16"):
        assert offsets in text


def parse(name,wire):
    pts,vt,ns=[],[],[]
    src=Counter()
    parts=Counter()
    part=""
    for line in name.read_text().splitlines():
        kind,*values=line.split()
        if kind=="#":
            part=" ".join(values)
        elif kind=="v":
            x,y,z=map(float,values)
            pts.append((1-x,y,z))  # engine reflect X, mount +1
            assert all(-.5-1e-6<=w<=1.5+1e-6 for w in (z,1-x))
        elif kind=="vt":
            uv=tuple(map(float,values))
            assert len(uv)==2 and all(0<u<1 for u in uv)
            if uv[0]>.7: assert wire.getpixel((int(uv[0]*wire.width),16))[3]==255
            vt.append(uv)
        elif kind=="vn":
            n=tuple(map(float,values))
            assert abs(sum(v*v for v in n)-1)<4e-6
            ns.append(n)
        elif kind=="f":
            assert len(values)==4 # strictly indexed convex quads
            refs=[tuple(map(int,p.split("/"))) for p in values]
            assert all(0<i<=len(pts) and 0<j<=len(vt) and 0<k<=len(ns) for i,j,k in refs)
            assert len({i for i,_,_ in refs})==4
            assert len({k for _,_,k in refs})==1
            key="wire" if "lattice" in part else ("posts" if "posts" in part else "rails")
            assert all(vt[j-1][0]<.7 for i,j,k in refs) if key=="wire" else all(vt[j-1][0]>.742 for i,j,k in refs)
            parts[key]+=1
            for i,_,_ in refs:src[key,i-1]+=1
    return pts,src,parts


def check(opts):
    assert FORMS==EXPECTED
    assert CORNER_REFERENCE=={8:"W",9:"E",10:"N",11:"S"}
    if opts.upstream_rail_cmd:expect_source(Path(opts.upstream_rail_cmd))
    atlas_path=TEX/f"bl_{STEM}_atlas.png"
    atlas=Image.open(atlas_path)
    assert atlas.mode=="RGBA" and atlas.size==(128,32)
    lattice=Counter(atlas.getpixel((x,y))[3] for x in range(88) for y in range(32))
    assert set(lattice)=={0,255} and .25<lattice[255]/sum(lattice.values())<.43
    assert all(atlas.getpixel((x,y))[3]==0 for x in range(88,96) for y in range(32))
    assert all(atlas.getpixel((x,y))[3]==255 for x in range(96,128) for y in range(32))
    bytes_total,quads=0,0
    for path,payload in assets():
        assert path.read_bytes()==payload,path
        if path==atlas_path:continue
        bytes_total+=len(payload)
        ground,profile=map(int,path.stem.split("_")[-2:])
        points,src,parts=parse(path,atlas)
        n=len(EXPECTED[ground])
        assert parts=={"posts":30*n,"rails":12*n,"wire":2*n}
        quads+=sum(parts.values())
        for border in EXPECTED[ground]:
            (a,b),(c,d)=BORDERS[border]
            for t in (0,.25,.5,.75,1):
                x,z=a+(c-a)*t,b+(d-b)*t
                # The whole footprint of the post is buried enough to touch
                # the native sloped plane (not just its center).
                pole=[p for i,p in enumerate(points) if ("posts",i) in src
                      and abs(abs(p[0]-x)-.015)<1e-6 and abs(abs(p[2]-z)-.015)<1e-6]
                assert len(pole)==8,(border,x,z,pole)
                assert all(y<floor(xx,zz,profile)-.03 for xx,y,zz in pole if y<floor(x,z,profile))
                hs=sorted(y for _,y,_ in pole)
                assert all(abs(y-(floor(x,z,profile)+POST_FOOT))<1e-6 for y in hs[:4])
                assert all(abs(y-(floor(x,z,profile)+POST_TOP))<1e-6 for y in hs[4:])
        if profile:
            assert max(y for x,y,z in points)-min(y for x,y,z in points)>1.44
        else:
            assert max(y for x,y,z in points)-min(y for x,y,z in points)<.50
        for (kind,i) in src:
            if kind=="wire":
                x,y,z=points[i]
                assert min(abs(y-floor(x,z,profile)-h) for h in (WIRE_TOP,WIRE_BOTTOM))<1e-6
    expected_files={f"bl_{STEM}_{g}_{p}.obj" for p,grounds in PROFILES.items() for g in grounds}
    assert {p.name for p in MODELS.glob(f"bl_{STEM}_*_*.obj")}==expected_files
    assert bytes_total<95_000
    for a,b in ((8,9),(10,11)):
        assert (MODELS/f"bl_{STEM}_{a}_0.obj").read_bytes()==(MODELS/f"bl_{STEM}_{b}_0.obj").read_bytes()
    blender=ROOT/"art/stock_rail_ground_fence.blend"
    assert blender.stat().st_size<230_000 and blender.read_bytes().startswith((b"BLENDER",b"\x28\xb5\x2f\xfd"))
    print(f"PASS stock rail fence geometry and atlas: {len(expected_files)} mounts, {quads} indexed quads, {bytes_total:,} model bytes")


if __name__=="__main__":
    p=argparse.ArgumentParser()
    p.add_argument("--upstream-rail-cmd")
    check(p.parse_args())
