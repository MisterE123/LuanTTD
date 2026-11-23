"""Verify packaged site models and construction-specific geometry limits."""
from pathlib import Path
from hashlib import sha256
import math
import re

root=Path(__file__).resolve().parents[1]
mod=root/"mods/luanttd_core"
sources={p.stem:p for p in (root/"art/stock_construction").glob("*.blend")}
meshes={p.stem[3:]:p for p in (mod/"models").glob("bl_town_site_*.obj")}
assert len(sources)==len(meshes)==66 and sources.keys()==meshes.keys()
assert all(x.stat().st_size>10000 for x in sources.values())

def geom(p):
    v,uv,f,n=[],[],[],[]
    for row in p.read_text().splitlines():
        if not row or row.startswith("#"): continue
        tag,*params=row.split()
        assert tag not in ("mtllib","usemtl")
        if tag=="v": v.append(tuple(map(float,params)))
        if tag=="vt": uv.append(tuple(map(float,params)))
        if tag=="vn": n.append(tuple(map(float,params)))
        if tag=="f": f.append([tuple(map(int,k.split("/"))) for k in params])
    assert len(v)>20 and len(f)>48 and len(set(uv))>=2,p
    assert math.isclose(min(y for x,y,z in v),-.5,abs_tol=.0002),p
    assert all(-.5001<=-x<=1.5001 and -.5001<=z<=1.5001 and -.501<=y<=3.22 for x,y,z in v),p
    assert all(0<=round(u*64-.5)<45 and math.isclose(u*64-.5,round(u*64-.5),abs_tol=.0001) and w==.5 for u,w in uv),p
    assert all(1<=a<=len(v) and 1<=b<=len(uv) and 1<=c<=len(n) for face in f for a,b,c in face),p
    assert all(len(face)==3 for face in f)
    return v

def top(vertices):
    return max(y for _,y,_ in vertices)+.5

bounds={}
hashes=set()
for name,p in sorted(meshes.items()):
    b=geom(p)
    bounds[name]=top(b)
    geo=b"\n".join(s for s in p.read_bytes().splitlines() if s.startswith(b"v "))
    signature=sha256(geo).digest()
    assert signature not in hashes,f"Duplicate construction geometry at {name}"
    hashes.add(signature)
# Prepared lots have no invented raised objects. The original alternative
# #06 never grows a tall gable frame prematurely, and the modern #24 has
# real tall uprights rather than a prefab cottage-shaped stand-in.
for name in ("town_site_bare","town_site_paved","town_site_1497_0","town_site_1519_0"):
    assert bounds[name]<.07,(name,bounds[name])
assert bounds["town_site_1503_1504"]<.46
assert .85<bounds["town_site_bare_1445"]<1.25
assert bounds["town_site_1548_1549"]>2.30
assert bounds["town_site_1562_1563"]>2.25
# Houses already wholly constructed have exactly the same roof height
# in their source-matching unlandscaped phase as in the mature geometry.
for key,height in bounds.items():
    if key.startswith("town_site_shell_"):
        suffix=key.removeprefix("town_site_shell_")
        complete=geom(mod/"models"/f"bl_town_stock_{suffix}.obj")
        assert math.isclose(height,top(complete),abs_tol=.00002),(key,height,top(complete))
print("PASS 66 distinct Blender/native construction assets, ground bounds, no early props, and unchanged shell heights")
