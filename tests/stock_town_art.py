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
# Cabin is exported on the same node anchor, with no foundation geometry.
assert (root/"art"/"town_lift_04.blend").stat().st_size > 20000
cab = mod/"models"/"bl_town_stock_04_lift.obj"
vertices=[tuple(map(float,line.split()[1:])) for line in cab.read_text().splitlines() if line.startswith("v ")]
assert len(vertices)>50
assert all(-.095 < x < .17 and -.40 < y < -.16 and 1.20 < z < 1.37 for x,y,z in vertices)
office = (mod/"models"/"bl_town_stock_04.obj").read_text()
shaft_ceiling = 1.5605 # underside of the exported crown frame
assert any(line.startswith("v ") and abs(float(line.split()[2])-shaft_ceiling)<1e-6
           for line in office.splitlines())
assert max(y for _,y,_ in vertices)+36*.0475 < shaft_ceiling-.02
alternate={0x06:(2,),0x18:(1,2,3),0x1a:(1,2,3)}
for id,looks in alternate.items():
    for look in looks:
        source=list((root/"art").glob(f"town_stock_{id:02x}v{look}_*.blend"))
        assert len(source)==1 and source[0].stat().st_size>20000
        check(mod/"models"/f"bl_town_stock_{id:02x}_{look}.obj",280)
for size,count in [(12,2),(22,4)]:
    for i in range(count):
        detail=[check(mod/"models"/f"bl_town_stock_stage_{size}_{s}_{i}.obj",70) for s in range(3)]
        assert detail[0] < detail[1] < detail[2]
# Read the venue relief from +Z, where decreasing native X is screen-right.
# Both name boards straddle a tile seam, so test combined glyphs, not a chunk.
def venue_letter_widths(id, front_z):
    intervals=[]
    for i in (1,3):
        geometry=(mod/"models"/f"bl_town_stock_{id:02x}_{i}.obj").read_text().splitlines()
        vertices=[tuple(map(float,row.split()[1:])) for row in geometry if row.startswith("v ")]
        for row in geometry:
            if not row.startswith("f "): continue
            face=[vertices[int(v.split("/")[0])-1] for v in row.split()[1:]]
            if all(math.isclose(z,front_z,abs_tol=.000001) for x,y,z in face):
                screen_x=[x-2*(i//2) for x,_,_ in face]  # OBJ import reverses X.
                intervals.append((min(screen_x),max(screen_x)))
    merged=[]
    for lo,hi in sorted(intervals):
        if merged and lo<=merged[-1][1]+.000001:
            merged[-1]=(merged[-1][0],max(hi,merged[-1][1]))
        else:
            merged.append((lo,hi))
    return [round(hi-lo,4) for lo,hi in merged]

football=venue_letter_widths(0x14,1.4272)
assert len(football)==8 and football[0]<football[-1]==football[-2] and football[1]==football[2],football
athletics=venue_letter_widths(0x20,1.4292)
assert len(athletics)==9 and athletics[6]==min(athletics) and athletics[1]==athletics[5],athletics
print(f"PASS: {len(new_mounts)} distinct editable roots and {sum(map(len,alternate.values()))} residential alternates checked on the native 2×2 anchor, {len(all_mounts)}/{len(source_ids)} RC1 Temperate roots mounted")
