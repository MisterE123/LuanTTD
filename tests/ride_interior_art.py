#!/usr/bin/env python3
"""Verify regenerated moving-vehicle media, eye calibration and true openings."""
from hashlib import sha256
from importlib.util import module_from_spec, spec_from_file_location
from math import isclose, isfinite
from pathlib import Path
import struct
import subprocess
import sys

root = Path(__file__).resolve().parents[1]
builder = root / "tools/build_ride_interiors.py"
spec = spec_from_file_location("ride_art", builder)
art = module_from_spec(spec)
spec.loader.exec_module(art)
media = root / "mods/luanttd_core"
basenames = {
    "bus": "bl_ride_bus_interior",
    "coach": "bl_ride_train_interior",
    "cab": "bl_ride_train_cab",
}
assets = [media / f"{folder}/{name}.{ext}"
          for name in basenames.values()
          for folder, ext in (("models", "obj"), ("textures", "png"))]
digests = [sha256(p.read_bytes()).digest() for p in assets]
subprocess.run([sys.executable, str(builder)], check=True)
assert digests == [sha256(p.read_bytes()).digest() for p in assets], "Generated art is not current"

def sub(a,b):
    return tuple(u-v for u,v in zip(a,b))

def dot(a,b):
    return sum(u*v for u,v in zip(a,b))

def cross(a,b):
    x,y,z=a; u,v,w=b
    return y*w-z*v,z*u-x*w,x*v-y*u

def ray_distance(p, d, tris):
    distances = []
    for a,b,c in tris:
        q,r=sub(b,a),sub(c,a); h=cross(d,r)
        det=dot(q,h)
        if abs(det)<1e-9: continue
        f=1/det; s=sub(p,a); u=f*dot(s,h)
        if not 0<=u<=1: continue
        qx=cross(s,q); v=f*dot(d,qx)
        if v<0 or u+v>1: continue
        t=f*dot(r,qx)
        if t>1e-7: distances.append(t)
    return min(distances,default=float("inf"))

for kind, name in basenames.items():
    points=[]; triangles=[]; normals=[]; uvs=[]
    for line in (media / "models" / (name + ".obj")).read_text().splitlines():
        parts=line.split()
        if not parts: continue
        if parts[0]=="v":
            x,y,z=map(float,parts[1:]); points.append((-x/10,y/10,z/10))
        if parts[0]=="vn":
            i,j,k=map(float,parts[1:]); normals.append((-i,j,k))
            assert isclose(i*i+j*j+k*k,1,abs_tol=.00001)
        if parts[0]=="vt":
            uv=tuple(map(float,parts[1:])); uvs.append(uv)
            assert len(uv)==2 and all(0<u<1 for u in uv)
        if parts[0]=="f":
            assert len(parts)==4
            refs=[tuple(int(i)-1 for i in f.split("/")) for f in parts[1:]][::-1]
            a,b,c=[points[i] for i,_,_ in refs]
            assert all(i>=0 and uv>=0 and n>=0 and uv<len(uvs) and n<len(normals) for i,uv,n in refs)
            assert dot(cross(sub(b,a),sub(c,a)),normals[refs[0][2]])>0, "OBJ winding disagrees with normal"
            triangles.append((a,b,c))
    assert len(triangles)<4100
    eye=art.EYES[kind]
    for direction in ((0,0,1),(0,0,-1),(1,0,0),(-1,0,0)):
        dx,dy,dz=direction
        # Some passenger rays naturally pick up real nearby seat backs. Test
        # several small view offsets around eye (camera can naturally freelook).
        hit=min(ray_distance(eye,(dx,0,dz),triangles),1.0)
        rays=[(dx+.055*i if dz else dx,dy+j*.05,dz+.055*i if dx else dz)
              for i in range(-4,5) for j in range(-1,3)]
        assert sum(not isfinite(ray_distance(eye,r,triangles)) for r in rays)>=3,(kind,direction,hit)
    assert ray_distance(eye,(0,-1,0),triangles)<.40, "Missing floor/seat"
    assert ray_distance(eye,(0,1,0),triangles)<.25, "Missing ceiling"
    png=(media / "textures" / (name+".png")).read_bytes()
    assert struct.unpack(">IIBBBBB",png[16:29])[2:4]==(8,2),"Openings must not depend on alpha"
    print(f"PASS {kind}: {len(triangles)} triangles, four actual apertures, normals and RGB atlas")
