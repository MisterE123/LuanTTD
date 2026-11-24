#!/usr/bin/env python3
"""Check RC1 steel layout 1 mesh mapping, repeated modules and retained yard reuse."""
from argparse import ArgumentParser
from collections import Counter, defaultdict
from math import sqrt
from pathlib import Path
import re
from struct import unpack

ROOT=Path(__file__).resolve().parents[1]
GEO=ROOT/"mods/luanttd_core/models"
TEX=ROOT/"mods/luanttd_core/textures"
PREFIX="bl_industry_steel_mill"
STOCK={
    (0,0):52,(0,1):53,(1,0):54,(1,1):55,(2,0):52,(2,1):53,(3,0):54,(3,1):55,
    (0,2):56,(1,2):57,(2,2):56,(3,2):57,(1,3):56,(2,3):57,
}


def load(path,cell,gfx,atlas_w):
    pts,norms,uv=[],[],[]
    sections=defaultdict(Counter)
    touching=defaultdict(set)
    title=""
    x,z=cell
    content=path.read_text().splitlines()
    assert f"industry 8, layout 1 ({x},{z}) GFX {gfx}" in content[0]
    for line in content[1:]:
        seq=line.split()
        if not seq:continue
        tag,*args=seq
        if tag=="o":title=args[0]
        elif tag=="v":
            nx,ny,nz=map(float,args)
            assert -.5000001<=-nx<=1.5000001 and -.5000001<=nz<=1.5000001
            assert -.500001<=ny<=2.75
            pts.append((-nx,nz,ny+.5))
        elif tag=="vn":
            n=tuple(map(float,args))
            assert abs(sum(v*v for v in n)-1)<.000036
            norms.append(n)
        elif tag=="vt":
            u,v=map(float,args)
            assert abs(u-(len(uv)+.5)/atlas_w)<.000001 and v==.5
            uv.append(u)
        elif tag=="f":
            assert len(args)==3
            refs=[tuple(map(int,p.split("/"))) for p in args]
            assert all(0<v<=len(pts) and 0<t<=len(uv) and 0<n<=len(norms) for v,t,n in refs)
            vs=[pts[r[0]-1] for r in refs]
            assert len(set(vs))==3,(path,title,vs)
            p=[vs[1][i]-vs[0][i] for i in range(3)]
            q=[vs[2][i]-vs[0][i] for i in range(3)]
            area=.5*sqrt(sum((p[i]*q[j]-p[j]*q[i])**2 for i,j in ((0,1),(0,2),(1,2))))
            assert area>1e-9,(path,title,vs)
            tcs={r[1] for r in refs}
            assert len(tcs)==1
            canonical=tuple(sorted(tuple(round(v,6) or 0 for v in p) for p in vs))
            sections[title][canonical,next(iter(tcs))]+=1
            for v in vs:
                for l,u,t in (("west","east",0),("north","south",1)):
                    other=1-t
                    if abs(v[t]+.5)<1e-7:touching[title,l].add((round(v[other],6),round(v[2],6)))
                    if abs(v[t]-1.5)<1e-7:touching[title,u].add((round(v[other],6),round(v[2],6)))
        else:assert False,(path,line)
    surfaces=[v for v in pts if abs(v[2]-.003)<1e-6]
    assert {(.5+s,.5+t,.003) for s in (-1,1) for t in (-1,1)}<=set(tuple(round(q,6) for q in v) for v in surfaces),path
    assert len(uv)==atlas_w
    return sections,touching


def check(opts):
    if opts.upstream_layout:
        source=Path(opts.upstream_layout).read_text()
        l=re.search(r"\b_tile_table_steel_mill_1\s*\{(.*?)\n\};",source,re.S)
        assert l
        from_upstream={tuple(map(int,(x,z))):int(gfx) for x,z,gfx in
                       re.findall(r"\{\{(\d+),\s*(\d+)\},\s*(\d+)\}",l[1])}
        assert from_upstream==STOCK,list(from_upstream.items())
    master=ROOT/"art"/"stock_steel_mill_layout_1.blend"
    assert 10_000<master.stat().st_size<1_800_000
    assert master.read_bytes().startswith((b"BLENDER",b"\x28\xb5\x2f\xfd"))
    stock_atlas=(TEX/(PREFIX+"_atlas.png")).read_bytes()
    assert (TEX/(PREFIX+"_l1_atlas.png")).read_bytes()==stock_atlas
    png_width,=unpack(">I",stock_atlas[16:20])
    assert png_width%8==0
    palette_count=png_width//8
    files={tuple(map(int,m.groups())) for p in GEO.glob(PREFIX+"_l1_*_*.obj")
           if (m:=re.fullmatch(PREFIX+r"_l1_(\d+)_(\d+)\.obj",p.name))}
    assert files==set(STOCK)
    tiles,seams={},{}
    total=0
    for cell,gfx in STOCK.items():
        x,z=cell
        p=GEO/f"{PREFIX}_l1_{x}_{z}.obj"
        tiles[cell],seams[cell]=load(p,cell,gfx,palette_count)
        total+=sum(ctr.total() for ctr in tiles[cell].values())
        if cell in ((0,2),(1,2)):
            old=(GEO/f"{PREFIX}_{x}_{z}.obj").read_bytes()
            assert p.read_bytes().split(b"\n",1)[1]==old.split(b"\n",1)[1]
        if cell in ((1,3),(2,3)):
            assert any("Southern_dispatch_finished_slabs" in name for name in tiles[cell])
    assert 27_000<total<45_000,total

    # Pair by local triangle coordinates and material, not appearance.
    for x,z in ((0,0),(0,1),(1,0),(1,1)):
        t1={n[7:]:v for n,v in tiles[x,z].items() if n.startswith("Unit_1_") and "redirected" not in n}
        t2={n[7:]:v for n,v in tiles[x+2,z].items() if n.startswith("Unit_2_") and "redirected" not in n}
        assert t1==t2,((x,z),len(t1),len(t2),set(t1)^set(t2))
        assert len(t1)>=5,(x,z)

    # Roofs must actually reach the next piece, not only the flat ground.
    for x in (0,2):
        roof=[n for n in tiles[x,1] if "standing-seam_pitched_roof" in n]
        assert roof
        for n in roof:
            a=seams[x,1][n,"east"]
            b=seams[x+1,1][n,"west"]
            assert len(a&b)>=3,(x,n,a,b)
    assert (0,3) not in files and (3,3) not in files
    print(f"PASS Steel Mill layout 1: 14 RC1 cells, 2 byte-identical yards, 2 repeated process kits, {total:,} checked triangles")


if __name__=="__main__":
    p=ArgumentParser()
    p.add_argument("--upstream-layout")
    check(p.parse_args())
