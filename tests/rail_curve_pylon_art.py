"""Check exported mast foot/contact coordinates and the true quarter-track clearance."""
from pathlib import Path
from math import hypot, atan2, cos, sin, pi

ROOT=Path(__file__).resolve().parent.parent
MODELS=ROOT/"mods/luanttd_core/models"
EDGES=((0,8),(8,16),(16,8),(8,0))
DX=(-2,-4,-2,0,2,4,2,0)
DZ=(-2,0,2,4,2,0,-2,-4)
CASES={(0,4,0):(4,), (0,6,0):(5,), (1,0,0):(3,), (1,5,1):(5,), (1,6,1):(5,),
       (2,0,1):(3,), (2,2,0):(4,), (2,7,0):(4,), (3,2,1):(4,), (3,4,1):(2,)}
# All six canonical centerline pairs.
PORTS=((0,2),(1,3),(0,3),(1,2),(2,3),(0,1))
MID=tuple(((x-8)/8,(z-8)/8) for x,z in EDGES)
for (edge,pole,slot),paths in CASES.items():
    name=f"bl_rail_curve_pylon_{edge}_{pole}_{slot}.obj"
    data=(MODELS/name).read_text()
    vertex=[]
    for line in data.splitlines():
        if line.startswith("v "):
            x,h,z=map(float,line.split()[1:])
            vertex.append((-x-.5+(1 if slot==0 else 0),z-.5+(1 if slot==1 else 0),h+1.5))
    assert len(vertex)>80
    min_y=min(h for x,z,h in vertex)
    assert abs(min_y)<1e-8
    cx,cz=EDGES[edge]
    px,pz=(cx+DX[pole]-8)/8,(cz+DZ[pole]-8)/8
    ground=[(x,z) for x,z,h in vertex if abs(h)<1e-8]
    assert abs(px-(min(x for x,z in ground)+max(x for x,z in ground))/2)<1e-5
    assert abs(pz-(min(z for x,z in ground)+max(z for x,z in ground))/2)<1e-5
    cx,cz=(cx-8)/8,(cz-8)/8
    assert any(hypot(x-cx,z-cz)<.013 and .899<h<.917 for x,z,h in vertex)
    for k in paths:
        a,b=(MID[d] for d in PORTS[k])
        ox,oz=a[0]+b[0],a[1]+b[1]
        lo=atan2(a[1]-oz,a[0]-ox)
        end=atan2(b[1]-oz,b[0]-ox)
        turn=pi/2 if (end-lo)%(2*pi)<pi else -pi/2
        def point(t):
            return ox+cos(lo+turn*t),oz+sin(lo+turn*t)
        # Checked for the tightest true quarter curves as well as the
        # center-to-center straightened path, not just grid boundaries.
        samples=[point(j/1000) for j in range(1001)]
        samples.extend((a[0]+(b[0]-a[0])*j/1000,a[1]+(b[1]-a[1])*j/1000) for j in range(1001))
        clear=min(hypot(x-px,z-pz) for x,z in samples)
        assert clear>.26,(name,k,clear)
print("PASS 10 original curve pylons: stock footing positions, wire-height clamps, and centerline clearance")
