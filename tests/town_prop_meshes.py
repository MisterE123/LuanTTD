"""Check native geometry, material compatibility, and no parcel overhang."""
from pathlib import Path
import math

ROOT = Path(__file__).resolve().parents[1]
NAMES = {"market": (.78,.85), "shop": (1.30,1.44), "green": (.90,1.01)}

def inspect():
    for key, (height_min, height_max) in NAMES.items():
        assert (ROOT/f"art/town_{key}.blend").stat().st_size>20_000
        obj = ROOT/f"mods/bayline/models/bl_town_{key}.obj"
        pos, tex, triangles = [], [], []
        for line in obj.read_text().splitlines():
            if line.startswith("v "):
                x,y,z=map(float,line.split()[1:])
                pos.append((-x,y,z)) # Luanti OBJ changes handedness.
            elif line.startswith("vt "):
                u,v=map(float,line.split()[1:])
                assert 0 < u < 1 and v==.5
                index=u*64-.5
                assert 0<=round(index)<45 and math.isclose(index,round(index),abs_tol=.0001)
                tex.append(u)
            elif line.startswith("f "):
                face = line.split()[1:]
                assert len(face)==3
                triangles.append([tuple(map(int, corner.split("/"))) for corner in face])
        assert len(pos)>700 and len(triangles)>1000 and len(set(tex))>=8, key
        assert all(-.5<=x<=1.5 and -.5<=z<=1.5 for x,y,z in pos), key
        assert -.503<=min(y for _,y,_ in pos)<=-.499, key
        assert height_min <= max(y for _,y,_ in pos)+.5 <= height_max, key
        assert all(1<=v<=len(pos) and 1<=u<=len(tex) and n>0
                   for face in triangles for v,u,n in face), key

        incompatible={"usemtl","mtllib"}
        assert all(not line or line.startswith("#") or line.split()[0] not in incompatible
                   for line in obj.read_text().splitlines()), key
    print("PASS: 3 detailed native civic parcel meshes fit the shared 2×2 anchor and scenery palette")

if __name__=="__main__":
    inspect()
