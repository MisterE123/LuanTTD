#!/usr/bin/env python3
"""Check texture repeat, diagonal furrows, stock fence profiles and height fit."""
from pathlib import Path
from statistics import mean
import struct
from io import BytesIO
from zipfile import ZipFile,ZIP_DEFLATED
import zlib

ROOT=Path(__file__).resolve().parents[1]
M=ROOT/"mods/bayline/models"
T=ROOT/"mods/bayline/textures"


def load(path):
    raw=path.read_bytes()
    assert raw[:8]==b"\x89PNG\r\n\x1a\n"
    w,h,depth,col=struct.unpack_from(">IIBB",raw,16)
    assert (depth,col)==(8,2)
    ptr=8
    body=b""
    while ptr<len(raw):
        n=struct.unpack_from(">I",raw,ptr)[0]
        if raw[ptr+4:ptr+8]==b"IDAT":body+=raw[ptr+8:ptr+8+n]
        ptr+=n+12
    decoded=zlib.decompress(body)
    pitch=1+3*w
    assert len(decoded)==pitch*h
    assert all(decoded[i*pitch]==0 for i in range(h))
    rows=[[tuple(decoded[i*pitch+1+3*j:i*pitch+4+3*j]) for j in range(w)] for i in range(h)]
    return w,h,rows


def vdiff(a,b):
    return sum(abs(x-y) for x,y in zip(a,b)) / 3


def rgba_checks(path):
    w,h,rows=load(path)
    assert (w,h)==(64,64)
    def jump(x,z):
        return mean(vdiff(rows[i][j],rows[(i+z)%h][(j+x)%w]) for i in range(h) for j in range(w))
    left=mean(vdiff(r[0],r[-1]) for r in rows)
    top=mean(vdiff(rows[0][j],rows[-1][j]) for j in range(w))
    near=mean([jump(1,0),jump(0,1)])
    # Tiled boundaries have no more discontinuity than their neighboring
    # texels. Test at all stages, with no dim "frame" that would outline tiles.
    assert max(left,top)<=near*1.35,(path,left,top,near)
    # Sampling one equal U+V diagonal follows a ridge, not another row.
    assert jump(5,5)<.58*jump(5,-5),(path,jump(5,5),jump(5,-5))
    assert len({p for r in rows for p in r})>20
    return rows


def mesh(path,materials):
    groups={}
    pts=[]
    n=f=0
    for line in path.read_text().splitlines():
        if line.startswith("o "):
            vs=groups.setdefault(line[2:],[])
        if line.startswith("v "):
            a,h,z=map(float,line.split()[1:]);p=(-.1*a,.1*h,.1*z)
            pts.append(p);vs.append(p)
        if line.startswith("vt "):
            n+=1
        if line.startswith("f "):
            assert " " in line[2:].strip()
            for t in line.split()[1:]:
                v,c,u=map(int,t.split("/"))
                assert 0<v<=len(pts) and 0<c<=materials and u>0
            f+=1
    assert n==materials and f>45
    return pts,groups


def test():
    items=[T/f"bl_farm_field_{stage}.png" for stage in range(9)]
    stages=[rgba_checks(path) for path in items]
    peaks=[max(p[1]-p[0] for row in rows for p in row) for rows in stages]
    assert peaks[3]>16 and peaks[4]>15 and max(peaks[0],peaks[6],peaks[7])<0,peaks
    assert len({path.read_bytes() for path in items})==9
    for mask in tuple(range(15))+(23,27,29,30):
        orig=(M/f"bl_land_{mask}.obj").read_text().splitlines()[1:]
        lifted=M/f"bl_farm_land_{mask}.obj";items.append(lifted)
        rows=lifted.read_text().splitlines()[1:]
        assert len(orig)==len(rows)
        for old,new in zip(orig,rows):
            if old.startswith("v "):
                _,x,y,z=old.split();_,X,Y,Z=new.split()
                assert X==x and Z==z and abs(float(Y)-float(y)-.004)<1e-9
            else:
                assert old==new  # same stock crease, UV and winding
    atlas=T/"bl_farm_fence_atlas.png";items.append(atlas)
    w,h,_=load(atlas);assert h==8 and w%8==0
    labels=["dense_individually_shaped_leaves","continuous_rough_split_rail","weathered_taut_strand",
            "dense_individually_shaped_leaves","dense_individually_shaped_leaves","chipped_interlocking_limestone_block"]
    widths={}
    for style,label in enumerate(labels,1):
        path0=M/f"bl_farm_fence_{style}_0.obj"
        path1=M/f"bl_farm_fence_{style}_1.obj";items.extend((path0,path1))
        a,l=mesh(path0,w//8); b,_=mesh(path1,w//8)
        assert any(label in k for k in l)
        assert len(a)==len(b)
        for (x,h,z),(xx,hh,zz) in zip(a,b):
            assert -.000001<=1-abs(x) and abs(z)<.225
            assert abs(xx-x)<.000001 and abs(zz-z)<.000001
            # Grade pivots vertical upright details at their X-center;
            # angled horizontal rails rise exactly with both terrain corners.
            assert abs((hh-h)-(.5+.5*x))<.079,(style,x,h,hh)
        assert min(x for x,h,z in a)<=-.965 and max(x for x,h,z in a)>=.965
        assert min(h for x,h,z in a)<.05 and .17<max(h for x,h,z in a)<.361
        widths[style]=max(abs(z) for x,h,z in a)
    assert widths[4]>1.35*widths[1]>1.8*widths[5]
    for stage in (5,6,8):
        path=M/f"bl_farm_field_detail_{stage}.obj";items.append(path)
        a,l=mesh(path,w//8)
        assert min(h for x,h,z in a)>=0
        assert all(max(abs(x),abs(z))<.971 and h<.17 for x,h,z in a)
        label="straw_bale" if stage==8 else "mature_barley_seed_heads"
        assert any(label in k for k in l)
    assert (ROOT/"art/stock_temperate_field_boundaries.blend").stat().st_size>100000
    buf=BytesIO()
    with ZipFile(buf,"w",compression=ZIP_DEFLATED,compresslevel=9) as z:
        for path in items:z.write(path,path.name)
    print(f"STOCK_FIELD_ART_PASS: 9 seamless diagonal textures, 19 exact raised stock masks, 12 slope-fit fence meshes, 3 sparse physical crops; {len(buf.getvalue())/1024:.1f} KiB runtime compressed.")


if __name__=="__main__":test()
