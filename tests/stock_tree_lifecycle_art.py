#!/usr/bin/env python3
"""Check original seven-stage tree art, renderer mount contract, and media footprint."""
from argparse import ArgumentParser
from collections import Counter
from math import hypot, sqrt
from pathlib import Path
import re
from struct import unpack
import sys

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/"tools"))
from build_stock_tree_lifecycle_art import (
    assets, MODELS, STAGES, COLOR, MATURE_WIDTH, WIDTH_FRACTION, EDIT_RGB,
)

TREE_NAMES=("Growing1","Growing2","Growing3","Grown","Dying1","Dying2","Dead")


def check_upstream(path):
    # CI passes the checkout root; direct art workflows may pass its src directory.
    if (path / "src" / "tree_map.h").is_file():
        path = path / "src"
    text=(path/"tree_map.h").read_text()
    part=re.search(r"enum class TreeGrowthStage.*?\{(.*?)\};",text,re.S)[1]
    assert dict((n,int(v)) for n,v in re.findall(r"\b(\w+)\s*=\s*([0-6])\b",part))==dict(zip(TREE_NAMES,range(7)))
    draw=(path/"tree_cmd.cpp").read_text().split("static void DrawTile_Trees",1)[1].split("static int GetSlopePixelZ_Trees",1)[0]
    assert re.search(r"i\s*==\s*trees\s*-\s*1\s*\?\s*GetTreeGrowth\(ti->tile\)\s*:\s*TreeGrowthStage::Grown",draw)


def decode(path,lift,old=False):
    pts,uv,ns=[],[],[]
    coverage=Counter()
    groups=Counter()
    signature=[]
    label=""
    for line in path.read_text().splitlines():
        if not line:continue
        tag,*args=line.split()
        if tag=="#" or tag=="o":
            label=" ".join(args)
        elif tag=="v":
            x,y,z=map(float,args)
            # Relative grass datum base+.5+lift/2; preserve authored old
            # even/odd quarter mount position (vertical-only shift).
            pts.append((-x,round(y+1.5-.5*lift,5),z))
        elif tag=="vt":
            u,v=map(float,args)
            index=int(u*64)
            assert abs(u-(index+.5)/64)<.000001 and v==.5
            if not old:assert index in COLOR.values()
            uv.append(index)
        elif tag=="vn":
            n=tuple(map(float,args))
            assert abs(sum(t*t for t in n)-1)<.00020
            ns.append(n)
        elif tag=="f":
            trip=[tuple(map(int,q.split("/"))) for q in args]
            assert len(trip)>=3
            assert all(0<i<=len(pts) and 0<t<=len(uv) and 0<n<=len(ns) for i,t,n in trip)
            if not old:assert len({t for i,t,n in trip})==1
            p=[pts[i-1] for i,t,n in trip]
            assert len(set(p))==len(p)
            u,v=[[p[k][i]-p[0][i] for i in range(3)] for k in (1,2)]
            area=.5*sqrt(sum((u[i]*v[j]-u[j]*v[i])**2 for i,j in ((0,1),(0,2),(1,2))))
            assert area>1e-8,(path,args,area)
            color=uv[trip[0][1]-1]
            coverage[color]+=len(trip)-2
            groups[label]+=len(trip)-2
            signature.append(tuple(trip))
    lo=min(y for _,y,_ in pts)
    hi=max(y for _,y,_ in pts)
    width=max(max(p[i] for p in pts)-min(p[i] for p in pts) for i in (0,2))
    assert -.043<=lo<0<hi<1.12
    assert width<.70
    assert all(-.38<x<.38 and -.38<z<.38 for x,y,z in pts)
    if not old:assert any(z<.03 and x<.03 and y<-.018 for x,y,z in pts)
    return pts,uv,ns,groups,coverage,signature,hi,width


def check(opts):
    if opts.upstream:check_upstream(Path(opts.upstream))
    if opts.atlas:
        from PIL import Image
        a=Image.open(ROOT/"mods/luanttd_core/textures/bl_scenery_palette.png")
        for key,index in COLOR.items():
            assert a.getpixel((4*index+2,4))==tuple(bytes.fromhex(EDIT_RGB[key])),key
    base=ROOT/"art/stock_tree_lifecycle.blend"
    assert base.read_bytes().startswith((b"BLENDER",b"\x28\xb5\x2f\xfd"))
    assert base.stat().st_size<425000
    payload=0
    paths=set()
    for path,b in assets():
        assert path.read_bytes()==b,path
        payload+=len(b)
        paths.add(path)
    assert len(paths)==120 and paths==set(MODELS.glob("bl_stock_forest_*_g*.obj"))
    assert payload<2_080_000
    assert not list(MODELS.glob("bl_stock_forest_*_g3.obj"))  # mature branches share existing geometry
    all_tri=0
    for style in range(4):
        old=MODELS/f"bl_stock_forest_{style}_0.obj"
        mature=decode(old,0,True)
        life=[]
        for stage in STAGES:
            phase=[]
            for lift in range(5):
                src=MODELS/f"bl_stock_forest_{style}_{lift}_g{stage}.obj"
                geometry=decode(src,lift)
                if lift==0:
                    phase=geometry
                else:
                    assert geometry==phase,(style,stage,lift,"must be same geometry shifted vertically only")
            _,_,_,groups,coverage,_,h,w=phase
            triangles=sum(coverage.values())
            all_tri+=triangles
            assert triangles<=525
            assert abs(MATURE_WIDTH[style]*WIDTH_FRACTION[stage][style]-w)<.00004
            if stage<=2:
                assert w<mature[-1] and h<mature[-2]
                assert sum(coverage[COLOR[x]] for x in ("green shade","green","green light","pine shade","pine","pine light"))>25
            elif style in (0,3):
                assert any("Visible twig ends" in p for p in groups)
                if stage==6:
                    assert all("foliage" not in p.casefold() for p in groups)
                    assert not set(coverage).intersection(range(35,44))
                elif stage==5:
                    assert coverage[COLOR["wheat"]]+coverage[COLOR["gold"]]+coverage[COLOR["rust"]]>0
            else:
                assert any("needle skirts" in p for p in groups)
                assert coverage[COLOR["cedar"]]+coverage[COLOR["soil shade"]]>30
                if stage==6:
                    assert not set(coverage).intersection(range(36,43))
            life.append((round(h,4),round(w,4),tuple(sorted(coverage.items()))))
        assert life[0][0]<life[1][0]<life[2][0]<mature[-2]
        assert life[0][1]<life[1][1]<life[2][1]<mature[-1]
        assert len(set(life))==6
    print(f"PASS RC1 tree stages: 24 original age/style designs, 120 mounted variants, stage 3 reused, {all_tri:,} prototype triangles, {payload:,} raw bytes")


if __name__=="__main__":
    p=ArgumentParser()
    p.add_argument("--upstream")
    p.add_argument("--atlas",action="store_true",help="also verify source RGB swatches against established atlas using Pillow")
    check(p.parse_args())
