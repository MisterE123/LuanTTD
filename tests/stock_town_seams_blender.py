"""Blender-native seam audit.

blender -b -t 2 --python-exit-code 1 --python tests/stock_town_seams_blender.py
"""
import sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/"tools"))
from build_stock_town_art import init, join_into_native, MULTI_ASSETS, MULTI_SIZE, construction
from mathutils import Vector
base=ROOT/"mods/luanttd_core/models"
def mesh_area(file):
    v=[]
    sizes=[]
    for l in file.read_text().splitlines():
        s=l.split()
        if not s:
            continue
        if s[0]=="v":v.append(Vector(map(float,s[1:])))
        if s[0]=="f":
            a,b,c=[v[int(item.split('/')[0])-1] for item in s[1:]]
            sizes.append((b-a).cross(c-a).length*.5)
    return sum(sizes)
def check(w,d,key,fn):
    init()
    fn()
    original=join_into_native()
    original.data.calc_loop_triangles()
    total=sum(x.area for x in original.data.loop_triangles)
    exported=sum(mesh_area(base/f"bl_{key}_{j+i*2}.obj") for i in range(w) for j in range(d))
    error=abs(total-exported)/total
    print(f"{key}: reference area {total:.5f}, partition {exported:.5f}, relative error {error:.6g}")
    assert error<.00003
for id,(_,fn) in MULTI_ASSETS.items():
    check(*MULTI_SIZE[id],f"town_stock_{id:02x}",fn)
for w,d in set(MULTI_SIZE.values()):
    for s in range(3):
        check(w,d,f"town_stock_stage_{w}{d}_{s}",lambda:construction(w,d,s))
