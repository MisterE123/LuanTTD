"""Check complete scenery collection and native Luanti exports without Blender."""
import itertools
import math
from pathlib import Path
import struct

ROOT = Path(__file__).resolve().parents[1]
ASSETS = ["house_0", "house_1", "house_2", "house_3", "town",
          "tree_0", "tree_1", "tree_2", "tree_3", "mine", "farm", "mill", "factory"]
model_path = ROOT/"mods/bayline/models"
palette = (ROOT/"mods/bayline/textures/bl_scenery_palette.png").read_bytes()
assert palette.startswith(b"\x89PNG\r\n\x1a\n")
assert struct.unpack(">II",palette[16:24]) == (256,8)

for stem in ASSETS:
    assert (ROOT/f"art/scenery_{stem}.blend").stat().st_size > 20_000
    model = model_path/f"bl_scenery_{stem}.obj"
    chunks = [line.split() for line in model.read_text().splitlines() if line and not line.startswith("#")]
    vertices = [(-float(x),float(y),float(z)) for kind,x,y,z in (c for c in chunks if c[0]=="v")]
    uv = [tuple(map(float,c[1:])) for c in chunks if c[0]=="vt"]
    sides = [c[1:] for c in chunks if c[0]=="f"]
    projections = [set(v[i] for v in vertices) for i in range(3)]
    assert len(vertices)>225 and len(sides)>400, (stem,"assets are not token cubes")
    assert all(len(f)==3 for f in sides), (stem,"native triangulation")
    assert all(0<u<1 and v==.5 and math.isclose(64*u-.5,round(64*u-.5),abs_tol=.0001)
               for u,v in uv), (stem,"palette sampling")
    assert len(uv)>=3, (stem,"authored swatches")
    lo,hi=-.5,(.5 if stem.startswith("tree") else 1.5)
    for i in (0,2):
        assert min(projections[i])>=lo and max(projections[i])<=hi, (stem,i,"horizontal footprint")
    assert -.508 <= min(projections[1]) <= -.499, (stem,"grounded base")
    assert .20 <= max(projections[1]) <= 1.6, (stem,"height")
    for f in itertools.chain.from_iterable(sides):
        v,u,n=map(int,f.split("/"))
        assert 1<=v<=len(vertices) and 1<=u<=len(uv) and n>0

print(f"PASS: {len(ASSETS)} original scenery models; native units, grounded bases, triangulation and color swatches")
