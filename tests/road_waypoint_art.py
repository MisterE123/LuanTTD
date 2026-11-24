"""Road waypoint signs stay on both shoulders and expose outward mesh faces."""
from pathlib import Path
from collections import defaultdict
from math import isclose

p = Path(__file__).resolve().parents[1]
assert (p/"art/road_waypoint.blend").read_bytes().startswith(b"BLENDER")
assert len((p/"mods/luanttd_core/textures/bl_road_waypoint_atlas.png").read_bytes())>100

def difference(a,b):
    return tuple(x-y for x,y in zip(a,b))

def cross(a,b):
    return (a[1]*b[2]-a[2]*b[1],a[2]*b[0]-a[0]*b[2],a[0]*b[1]-a[1]*b[0])

def dot(a,b):
    return sum(x*y for x,y in zip(a,b))

for axis in range(2):
    lines=(p/f"mods/luanttd_core/models/bl_road_waypoint_{axis}.obj").read_text().splitlines()
    xyz=[tuple(map(float,s.split()[1:])) for s in lines if s.startswith("v ")]
    faces=[[int(v.split("/")[0])-1 for v in s.split()[1:]] for s in lines if s.startswith("f ")]
    lut=defaultdict(set)
    for i,face in enumerate(faces):
        for v in face:
            lut[v].add(i)
    seen=set()
    solids,paint,named_shoulders=0,0,set()
    for j,face in enumerate(faces):
        if j in seen:
            continue
        stack=[j]; group=set()
        while stack:
            k=stack.pop()
            if k in group:
                continue
            group.add(k)
            for v in faces[k]:
                stack.extend(lut[v]-group)
        seen |= group
        if len(group)==1:
            paint+=1
            continue
        group_vertices={v for k in group for v in faces[k]}
        assert len(group)==6 and len(group_vertices)==8
        middle=tuple(sum(xyz[v][d] for v in group_vertices)/8 for d in range(3))
        # Native model origin: node anchors at southeastern tile corner.
        lateral=middle[0]-.5 if axis==1 else middle[2]+.5
        assert .63<abs(lateral)<.91
        named_shoulders.add(lateral>0)
        for k in group:
            a,b,c,*_=faces[k]
            normal=cross(difference(xyz[b],xyz[a]),difference(xyz[c],xyz[a]))
            assert dot(normal,difference(xyz[a],middle))>1e-7
        solids+=1
    assert solids==10 and paint==20 and named_shoulders=={False,True}
    assert isclose(max(y for _,y,_ in xyz),.088,abs_tol=.001)
print("PASS both original road waypoint axes: 20 closed outward solids and 40 double-sided enamel markings")
