"""Check authored wildlife exports, coherent animation frames and runtime origins."""
from collections import Counter
from math import degrees, isfinite, sqrt
from pathlib import Path
from struct import unpack
from zlib import decompress

root = Path(__file__).resolve().parents[1]
mod = root / "mods" / "luanttd_core"
originals = ("whale", "porpoise", "seagull", "eagle", "fox")
variants = ("seagull_wing_up", "seagull_wing_down", "eagle_wing_up",
            "eagle_wing_down", "fox_stride")

def parse(name):
    path = mod / "models" / f"bl_wildlife_{name}.obj"
    verts, uv, normals, faces, groups = [], [], [], [], []
    for line in path.read_text().splitlines():
        kind, _, values = line.partition(" ")
        if kind in ("v", "vt", "vn"):
            result = tuple(map(float, values.split()))
            assert all(isfinite(c) for c in result)
            {"v": verts, "vt": uv, "vn": normals}[kind].append(result)
        if kind == "f":
            faces.append(tuple(tuple(int(i)-1 for i in f.split("/")) for f in values.split()))
        if kind == "g":
            groups.append(values)
    assert 400<=len(verts)<=4200 and 350<=len(faces)<=4000
    assert len(groups)>=10 and len(set(groups))>=6
    assert len(normals)>=len(verts)*.88 and all(.999 < sum(x*x for x in n) < 1.001 for n in normals)
    assert all(0<c<1 for pair in uv for c in pair)
    assert len({t for f in faces for _,t,_ in f})>=7
    edges=Counter()
    for f in faces:
        assert len(f)>=3 and len({v for v,_,_ in f})==len(f)
        assert all(0<=v<len(verts) and 0<=t<len(uv) and 0<=n<len(normals) for v,t,n in f)
        us=[v for v, _, _ in f]
        for a,b in zip(us,us[1:]+us[:1]):
            edges[min(a,b),max(a,b)] += 1
    assert set(edges.values())=={2},name
    return verts, uv, faces, groups

def extent(points,axis):
    return min(p[axis] for p in points),max(p[axis] for p in points)

data={name:parse(name) for name in originals+variants}
for name,length in (("whale",39.27),("porpoise",10.28)):
    verts,_,_,_=data[name]
    assert extent(verts,1)[0] < -.65 and extent(verts,1)[1] > .40
    lo,hi=extent(verts,2)
    assert abs((hi-lo)-length)<.14
    assert lo<0.0<hi

for name,width in (("seagull",7.06),("eagle",11.025)):
    verts,uv,faces,grp=data[name]
    lo,hi=extent(verts,0)
    assert abs(hi-lo-width)<.02
    for i,(suffix,sign) in enumerate((("_wing_up",1),("_wing_down",-1))):
        alt,uv2,faces2,grp2=data[name+suffix]
        assert len(alt)==len(verts) and uv2==uv and faces2==faces and grp2==grp
        tip_delta=[sign*(q[1]-p[1]) for p,q in zip(verts,alt) if abs(p[0])> .40*width]
        assert min(tip_delta)>width*.08 and max(tip_delta)<width*.29
        assert all(p==q for p,q in zip(verts[:14*8],alt[:14*8])), "Flap moved torso"

fox,_,faces,grp=data["fox"]
alt,_,faces2,grp2=data["fox_stride"]
assert len(fox)==len(alt) and faces==faces2 and grp==grp2
assert abs(extent(fox,1)[0])<.01 and abs(extent(alt,1)[0])<.01
assert all(p==q for p,q in zip(fox[:14*9],alt[:14*9]))
assert max(abs(a[2]-b[2]) for a,b in zip(fox,alt))>.45
assert max(p[1] for p in fox)>4

atlas=(mod/"textures"/"bl_wildlife_atlas.png").read_bytes()
assert atlas.startswith(b"\x89PNG\r\n\x1a\n")
width,height,depth,style,*_=unpack("!IIBBBBB",atlas[16:29])
assert (width,height,depth,style)==(128,128,8,2)
data_size=unpack("!I",atlas[33:37])[0]
assert atlas[37:41]==b"IDAT"
rgb=decompress(atlas[41:41+data_size])
row_size=3*width+1
colors={rgb[y*row_size+1+x*3:y*row_size+4+x*3] for x in range(8,128,16) for y in range(8,128,16)}
assert len(colors)>=40
src=(root/"art"/"wildlife.blend")
assert 90_000 < src.stat().st_size < 3_000_000
print("PASS original wildlife: five species, closed meshes, shared painted atlas, wing/stride poses and correct runtime origins")
