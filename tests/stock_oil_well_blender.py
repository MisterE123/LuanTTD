"""Load oil wells .blend; verify actual frame and rigid linkage motion."""
from math import cos, hypot, pi, sin
from pathlib import Path
import sys

import bpy
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/"tools"))
import build_stock_oil_well_art as A

s=bpy.context.scene
assert (s.frame_start,s.frame_end,s.frame_current)==(1,49,1)
models=[obj for obj in s.objects if obj.name.startswith("Well ") and " move " in obj.name]
assert len(models)==50
assert all(o.data.shape_keys and len(o.data.shape_keys.key_blocks)==12 for o in models)
heads=[o for o in models if "recognizable curved solid horsehead" in o.name]
assert len(heads)==5
def samples(frame):
    s.frame_set(frame)
    ctx=bpy.context.evaluated_depsgraph_get()
    return [[v.co.copy() for v in o.evaluated_get(ctx).data.vertices] for o in heads]
start=samples(1)
end=samples(49)
assert all((a-b).length<1e-6 for A0,B0 in zip(start,end) for a,b in zip(A0,B0))
lengths=[]
for f in range(1,49,4):
    side=samples(f)
    for j,(i,z) in enumerate(A.LAYOUT):
        lengths.extend([v.z for v in side[j]])
        assert all(-.46<v.x-2*i<1.48 and -.46<v.y-2*z<1.48 for v in side[j])
for sh in range(1,5):
    assert abs(start[sh][0].z-start[sh-1][0].z)>.0004
assert max(lengths)-min(lengths)>.45
x,z,y=A.PIVOT
for i in range(240):
    theta,(cx,cy)=A.pose(.78+i*pi/120)
    px=x-A.REAR_RADIUS*cos(theta)
    py=y-A.REAR_RADIUS*sin(theta)
    assert abs(hypot(px-cx,py-cy)-A.LINK)<1e-8
print("STOCK_OIL_WELL_RIG_PASS: five phase-offset mechanisms, 12 poses, 240 constant-length link samples, exact closing frame.")
