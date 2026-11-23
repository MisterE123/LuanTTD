"""Check editable sources/native exports, exact source root order and native footing."""
import math
from pathlib import Path
import re

root=Path(__file__).resolve().parents[1]
mod=root/"mods/luanttd_core"
manifest=(mod/"stock_town_art.lua").read_text()
specs=(mod/"openttd/town_growth_houses.lua").read_text()
source_ids={int(key,16) for key in re.findall(r"{0x([0-9A-F]+),",specs)}
all_mounts={int(key,16) for key in re.findall(r"\[0x([0-9A-F]+)\]=",manifest)}
new_mounts={int(key,16) for key in re.findall(r"\[0x([0-9A-F]+)\]=\{[^\n]*asset=true",manifest)}
assert all_mounts <= source_ids and len(source_ids)==31
objects=set()
parts={0x07:2,0x14:4,0x20:4,0x28:4}
def check(asset,minimum):
    assert asset.is_file()
    geometry=asset.read_text()
    if "_stage_" not in asset.name:
        assert geometry not in objects
        objects.add(geometry)
    v,uv,n,f=[],[],[],[]
    for row in geometry.splitlines():
        parts=row.split()
        if not parts: continue
        op,*p=parts
        assert op not in {"usemtl","mtllib"}
        if op=="v":
            x,y,z=map(float,p)
            v.append((-x,y,z))
        elif op=="vt":
            u,t=map(float,p)
            palette_index=u*64-.5
            assert 0 <= round(palette_index)<45 and math.isclose(palette_index,round(palette_index),abs_tol=.0001) and t==.5
            uv.append(u)
        elif op=="vn":
            normal=tuple(map(float,p)); assert math.isclose(math.hypot(*normal),1,rel_tol=.0001)
            n.append(normal)
        elif op=="f":
            assert len(p)==3
            f.append([tuple(map(int,a.split("/"))) for a in p])
    assert len(set(uv))>=(4 if "_stage_" in asset.name else 6) and len(v)>=minimum and len(f)>=minimum*1.4,(asset,len(v),len(f),len(set(uv)))
    assert all(-.5<=x<=1.5 and -.5<=z<=1.5 and -.501<=y<=3.2 for x,y,z in v),asset
    assert math.isclose(min(y for _,y,_ in v),-.5,abs_tol=.001),asset
    assert all(1<=a<=len(v) and 1<=b<=len(uv) and 1<=c<=len(n) for face in f for a,b,c in face),asset
    return len(f)

for id in new_mounts:
    blend=list((root/"art").glob(f"town_stock_{id:02x}_*.blend"))
    assert len(blend)==1 and blend[0].stat().st_size > 20000
    count=parts.get(id)
    if count:
        for i in range(count):
            check(mod/"models"/f"bl_town_stock_{id:02x}_{i}.obj",110)
    else:
        check(mod/"models"/f"bl_town_stock_{id:02x}.obj",280)
for size,count in [(12,2),(22,4)]:
    for i in range(count):
        detail=[check(mod/"models"/f"bl_town_stock_stage_{size}_{s}_{i}.obj",70) for s in range(3)]
        assert detail[0] < detail[1] < detail[2]
print(f"PASS: {len(new_mounts)} distinct editable meshes checked on the native 2×2 anchor, {len(all_mounts)}/{len(source_ids)} RC1 Temperate roots mounted")
