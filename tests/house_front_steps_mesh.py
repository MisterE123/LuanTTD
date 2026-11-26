"""Independent authored geometry check for all curb and handedness combinations."""
from pathlib import Path
root=Path(__file__).resolve().parents[1]/"mods/luanttd_core/models"
anchors=((0,0),(1,0),(1,1),(0,1))
for key in range(1,9):
    d=(key-1)%4+1
    dx,dz=anchors[d-1]
    vertices=[]
    heights=[]
    for ln in (root/f"bl_town_front_steps_{key}.obj").read_text().splitlines():
        if ln.startswith("v "):
            x,y,z=map(float,ln[2:].split())
            vertices.append((x,y,z))
            x,z=-x+dx,z+dz
            ext={1:-.5-z,2:x-1.5,3:z-1.5,4:-.5-x}[d]
            assert -.000001 <= ext <= .317001 and -1.5 <= y <= -.5, (key,x,y,z)
        elif ln.startswith("f "):
            face=[vertices[int(i.split("/")[0])-1] for i in ln[2:].split()]
            if len({p[1] for p in face})==1:
                a,b,c=face[:3]
                assert (b[2]-a[2])*(c[0]-a[0])-(b[0]-a[0])*(c[2]-a[2])>0, key
                heights.append(a[1])
    assert len(heights)==7 and all(abs(y-(-1.5+(i+1)/7))<.000001 for i,y in enumerate(heights))
print("PASS stairs show seven outward upward-facing treads with no road-lane intrusion")
