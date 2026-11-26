#!/usr/bin/env python3
"""Check native mesh footprints after Luanti's OBJ coordinate reflection."""
from pathlib import Path

base=Path("mods/luanttd_core/models")


def points(mask):
    with (base/f"bl_canal_dike_{mask}.obj").open() as model:
        return [(-float(x),float(y),round(float(z)+1,4)) for tag,x,y,z in
            (line.split() for line in model if line.startswith("v "))]


def extent(mask):
    return [(min(xs),max(xs)) for xs in zip(*points(mask))]


# The model anchors at even X/odd Z; after reflection and translation the
# cardinal walls must lie against the same tile boundaries as RC1 offsets.
for i,axis in enumerate((0,2,0,2)):
    bounds=extent(1<<i)
    span=bounds[axis]
    assert bounds[2-axis]==(-.5,1.5),bounds
    if i in (0,3):
        assert span==(-.5,-.34),bounds
    else:
        assert span==(1.34,1.5),bounds

for i,(signx,signz) in enumerate(((-1,1),(1,1),(1,-1),(-1,-1))):
    bounds=extent(256<<i)
    for axis,sign in ((0,signx),(2,signz)):
        lo,hi=bounds[axis]
        assert hi-lo<.12
        assert (lo if sign<0 else hi)==(-.5 if sign<0 else 1.5),bounds

count=0
for path in base.glob("bl_canal_dike_*.obj"):
    mask=int(path.stem.rsplit("_",1)[-1])
    bounds=extent(mask)
    assert all(-.5<=lo<=hi<=1.5 for lo,hi in (bounds[0],bounds[2])),bounds
    assert bounds[1][0]<-.5<bounds[1][1] # meet below animated water, emerge above
    count+=1
assert count==46
print("PASS 46 stock dike models: correctly mirrored cardinal walls and diagonal corners fit the designated Luanti subnode")
