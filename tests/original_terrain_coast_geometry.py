#!/usr/bin/env python3
"""Check the clipped Original-mode tide datum and watertight tile coverage."""
from pathlib import Path
import importlib.util
import math

root = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("art", root/"tools/build_original_coast_art.py")
art = importlib.util.module_from_spec(spec)
spec.loader.exec_module(art)


def parse(path):
    points, uv, faces = [], [], []
    for s in path.read_text().splitlines():
        if s.startswith("v "):
            points.append(tuple(map(float, s.split()[1:])))
        elif s.startswith("vt "):
            uv.append(tuple(map(float, s.split()[1:])))
        elif s.startswith("f "):
            faces.append([tuple(int(i)-1 for i in part.split("/")) for part in s.split()[1:]])
    return points, uv, faces


def near(a,b):
    assert math.isclose(a,b,rel_tol=0,abs_tol=2e-7),(a,b)


def verify(mask):
    path=art.ROOT/"models"/f"bl_original_coast_{mask}.obj"
    points,uv,faces=parse(path)
    area=[0.,0.,0.]
    for face in faces:
        assert len(face)==3
        triangles=[points[i] for i,_ in face]
        bands={math.floor(uv[j][0]*3) for _,j in face}
        assert len(bands)==1
        band=bands.pop()
        normal=art.normals_2d(*triangles)
        assert normal<0
        area[band]+=-normal/2
        for x,y,z in triangles:
            assert -.5-1<=x<=.5 and -.5<=z<=1.5
            if band==2:
                near(y,art.SEA)
            elif band==1:
                assert art.SEA-1e-7<=y<=art.SHINGLE+1e-7
            else:
                assert y>=art.SHINGLE-1e-7
    near(sum(area),4.)
    if mask:
        assert all(n>0 for n in area)
    else:
        near(area[2],4.)


for mask in (0,*art.MASKS):
    verify(mask)
print("PASS exact tile coverage and coplanar sea across 17 original shore meshes")
