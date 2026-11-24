#!/usr/bin/env python3
"""Grounding, winding, bank compatibility and slope joins for native rock art."""
from collections import Counter
from math import isclose, sqrt
from pathlib import Path
import sys

from PIL import Image, ImageChops

sys.path.insert(0,str(Path(__file__).resolve().parents[1]/"tools"))
from build_stock_rocky_water_art import (
    APRON, MASKS, MOD, RAPIDS, REPO, SEA, SWATCHES,
    asset_files, batch, cross, height_field, old_bank,
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
foam_count=0
for name,parts,shift in batch():
    path=MOD/"models"/f"bl_{name}.obj"
    xyz,uv,faces=inspect_obj(path)
    is_shore=name.startswith("rocky_coastal")
    is_rapid=name.startswith("river_")
    shape=int(name.rsplit("_",1)[1]) if is_shore or is_rapid else 0
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
    assert all(-1.5<=x-shift<=.5 and -.5<=z<=1.5 for x,y,z in xyz),(name,"extends beyond its tile")
    for p in parts[1 if is_shore else 0:]:
        if "foam" in p.name.lower() or "Froth" in p.name:
            foam_count+=1
            assert is_rapid and all(abs(y-support(x,z)-.0135)<1e-8 for x,y,z in p.points)
            assert all(cross(*(p.points[j] for j in f))[1]>0 and k in (6,7) for f,k in p.faces)
            assert p.points[-1][1]<p.points[0][1],(name,"froth is not oriented downstream")
            continue
        solid(p)
        assert len(p.points)==30
        assert all(y<=support(x,z)-.10 for x,y,z in p.points[:7]),(name,"unattached footing")
        assert all(y>support(x,z) for x,y,z in p.points[7:28]),(name,"invalid rocky surface")
        if is_shore:
            x,y,z=p.points[-1]
            assert support(x,z)<=SEA+.75 and y>support(x,z)+.08
        if not is_shore and not is_rapid:
            assert max(y for _,y,_ in p.points)>SEA+.08
            assert all(y<SEA-APRON for _,y,_ in p.points[:7]),"detached even at the maximum native wave depression"
    assert len(faces)<=375,(name,"model became too expensive for repeated tiles")
for i in range(4):
    old=Image.open(MOD/"textures"/f"bl_original_coast_{i}.png").convert("RGB")
    new=Image.open(MOD/"textures"/f"bl_rocky_coast_{i}.png").convert("RGB")
    assert not ImageChops.difference(old,new.crop((0,0,96,32))).getbbox()
    for j,(_,hex) in enumerate(SWATCHES): assert new.getpixel((98+4*j,15))==tuple(bytes.fromhex(hex))
assert foam_count>=48 and (REPO/"art"/"stock_rocky_water.blend").stat().st_size>80_000
print(f"PASS original 16 coast slopes, level open-water rocks, 4 native rapid overlays; {total_faces:,} ground-matched triangles, {foam_count} downhill wakes, original shore atlas unchanged")
