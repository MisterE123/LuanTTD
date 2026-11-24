#!/usr/bin/env python3
"""Grounding, winding, bank compatibility and slope joins for native rock art."""
from collections import Counter
from math import hypot, isclose, sqrt
from pathlib import Path
import sys

from PIL import Image, ImageChops

sys.path.insert(0,str(Path(__file__).resolve().parents[1]/"tools"))
from build_stock_rocky_water_art import (
    MASKS, MOD, RAPIDS, REPO, SEA, SWATCHES,
    asset_files, batch, cross, height_field, old_bank, open_water, rotated, slab,
)


def inspect_obj(path):
    xyz,uv,normals,faces=[],[],[],[]
    for line in path.read_text().splitlines():
        tag,*args=line.split()
        if tag=="v": xyz.append(tuple(map(float,args)))
        elif tag=="vt": uv.append(tuple(map(float,args)))
        elif tag=="vn":
            n=tuple(map(float,args))
            assert abs(sum(x*x for x in n)-1)<3e-7,(path,n)
            normals.append(n)
        elif tag=="f":
            f=[tuple(int(n)-1 for n in vertex.split("/")) for vertex in args]
            assert len(f)==3 and all(0<=i<len(xyz) and 0<=t<len(uv) and 0<=n<len(normals) for i,t,n in f)
            attrs = cross(*(xyz[v[0]] for v in f))
            length=sqrt(sum(a*a for a in attrs))
            assert length>1e-8
            assert all(sum(x*y for x,y in zip(attrs,normals[n]))/length>.999995 for _,_,n in f)
            faces.append(f)
    return xyz,uv,faces


def solid(part):
    edges=Counter()
    volume6=0
    for face,k in part.faces:
        assert 0<=k<6
        a,b,c=[part.points[i] for i in face]
        volume6 += sum(p*q for p,q in zip(a,cross((0,0,0),b,c)))
        for u,v in zip(face,face[1:]+face[:1]): edges[u,v]+=1
    assert all(q==1 and edges[v,u]==1 for (u,v),q in edges.items()),part.name
    assert volume6>0,part.name


for path,expected in asset_files():
    assert path.read_bytes()==expected,(path.name,"not reproduced")

assert MASKS==(1,2,3,4,6,7,8,9,11,12,13,14,23,27,29,30)
assert RAPIDS==(3,6,9,12)
total_faces=0
submerged=0
for name,parts,shift in batch():
    path=MOD/"models"/f"bl_{name}.obj"
    xyz,uv,faces=inspect_obj(path)
    is_shore=name.startswith("rocky_coastal")
    is_rapid=name.startswith("river_")
    shape=int(name.removeprefix("rocky_coastal_bank_").split("_")[0]) if is_shore else int(name.rsplit("_",1)[1]) if is_rapid else 0
    support=height_field(shape) if shape else lambda x,z:SEA
    total_faces+=len(faces)
    if is_shore:
        base=old_bank(shape)
        assert len(parts)>=4
        assert xyz[:len(base.points)]==base.points,"source bank moved"
        assert all(isclose(v,o,abs_tol=1e-8) and isclose(u,b*.75,abs_tol=1e-8)
                   for (u,v),(b,o) in zip(uv,base.uv)), "Source bank UV atlas rescale is not exact."
        assert all(t<=.5 for t,_ in uv[:len(base.uv)]), "ordinary bank still has no opaque water layer"
        assert [tuple(q[0] for q in f) for f in faces[:len(base.faces)]] == [f for f,_ in base.faces]
    assert not shift==1 or is_rapid
    if not is_shore:
        assert all(-1.5<=x-shift<=.5 and -.5<=z<=1.5 for x,y,z in xyz),(name,"extends beyond its tile")
    else:
        for p in parts:
            skirt=.17 if p.name.startswith("Shingle toe") else 0
            assert all(-1.5-skirt<=x<=.5+skirt and -.5-skirt<=z<=1.5+skirt for x,y,z in p.points),p.name
        toes=[p for p in parts if p.name.startswith("Shingle toe")]
        assert all(min(y for _,y,_ in p.points)<SEA<max(y for _,y,_ in p.points) for p in toes)
    if is_shore:
        assert any(min(y for _,y,_ in p.points)<SEA-.01 and max(y for _,y,_ in p.points)>SEA+.045
                   for p in parts[1:]),(name,"rocks don't straddle the tide line")
    for p in parts[1 if is_shore else 0:]:
        solid(p)
        ceiling=max(y for _,y,_ in p.points)
        if is_rapid:
            limits=[y-support(x,z) for x,y,z in p.points]
            assert min(limits)<-.25 and max(limits)>.06,(name,p.name,"not a riverbed protrusion",limits)
        else:
            width=max(hypot(a[0]-b[0],a[2]-b[2]) for a in p.points for b in p.points)
            thickness=ceiling-min(y for _,y,_ in p.points)
            assert thickness < .65*width or (is_shore and thickness<.77*width),(name,p.name,width,thickness)
            if p.name.startswith("Submerged"):
                submerged+=1
                assert SEA-.405<=ceiling<=SEA-.080,(name,p.name,ceiling)
            elif not is_shore:
                assert SEA+.06<ceiling<SEA+.21 and min(y for _,y,_ in p.points)>=SEA-.117
    assert len(faces)<=850,(name,"model became too expensive for repeated tiles")
for i in range(4):
    old=Image.open(MOD/"textures"/f"bl_original_coast_{i}.png").convert("RGB")
    new=Image.open(MOD/"textures"/f"bl_rocky_coast_{i}.png").convert("RGB")
    assert not ImageChops.difference(old,new.crop((0,0,96,32))).getbbox()
    for j,(_,hex) in enumerate(SWATCHES): assert new.getpixel((98+4*j,15))==tuple(bytes.fromhex(hex))
foam=Image.open(MOD/"textures"/"bl_river_foam.png")
assert foam.mode=="RGBA" and foam.getpixel((0,0))[3]==0 and foam.getpixel((7,7))[3]>180
for form in range(4):
    a=open_water(form)
    for group in range((len(a)-3)//4):
        column=a[4*group:4*group+4]
        assert column[0].name.startswith("Exposed")
        for above,below in zip(column,column[1:]):
            # Separate 3D rocks overlap at each level vertically and on both
            # horizontal axes, instead of stretching a common column.
            for j in range(3):
                u,v=[p[j] for p in above.points],[p[j] for p in below.points]
                assert min(max(u),max(v))>max(min(u),min(v)),(form,group,j)
        assert min(y for _,y,_ in column[-1].points)<SEA-.68
    for p in a:
        assert all(isclose(a,b,abs_tol=1e-8) for u,v in zip(p.points,rotated(p,4).points) for a,b in zip(u,v))
assert submerged>=240 and (REPO/"art"/"stock_rocky_water.blend").stat().st_size>80_000
print(f"PASS 32 fixed-bank variants, 16 rotated skerry variants, 4 closed riverbed formations; {submerged} submerged bodies, {total_faces:,} triangles")
