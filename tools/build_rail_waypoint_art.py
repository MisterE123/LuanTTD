#!/usr/bin/env python3
"""Original enamel railway boards, not passenger facilities or platform meshes."""
from pathlib import Path
from PIL import Image
from math import sqrt

base = Path(__file__).resolve().parents[1] / "mods/bayline"
palette = ["716c60","94998b","666354","244c54","277985","efe1ad","294149","aeb5a6"]
im = Image.new("RGB",(len(palette)*8,8))
for i,col in enumerate(palette):
    im.paste(tuple(int(col[j:j+2],16) for j in (0,2,4)),(i*8,0,(i+1)*8,8))
im.save(base/"textures/bl_rail_waypoint_palette.png",optimize=True)
for axis in (0,1):
    vertices,faces=[],[]
    # Authored in across/along-track coordinates about the tile centre.
    # The node's anchor is the southeastern quarter at x,z = 2*tile+1.
    def vert(u,h,v):
        x,z=(u,v) if axis==1 else (v,-u)
        result=(.5-x,h-.5,-.5+z)
        vertices.append(result)
        return len(vertices)
    def box(x0,y0,z0,x1,y1,z1,col,top=None):
        q=[vert(x,y,z) for y in (y0,y1) for z in (z0,z1) for x in (x0,x1)]
        for k,ids in enumerate(((0,2,3,1),(4,5,7,6),(0,1,5,4),(2,6,7,3),(0,4,6,2),(1,3,7,5))):
            # Luanti inverts X on OBJ import; reverse for the authored space.
            row=[q[i] for i in ids[::-1]]
            faces.append((row,top if k==1 and top is not None else col))
    def lettering(cx,z0,z1):
        # A routed W in the cream enamel. Five small bevel-free metal bars.
        points=[(-.152,.531),(-.092,.388),(-.028,.496),(.034,.388),(.127,.531)]
        for (x0,y0),(x1,y1) in zip(points,points[1:]):
            d=sqrt((x1-x0)**2+(y1-y0)**2)
            u,w=(y1-y0)*.016/d,(x0-x1)*.016/d
            for z,rev in ((z0,True),(z1,False)):
                # opposing faces are legible from both approaches.
                mirror=-1 if rev else 1
                q=[vert(cx+x*mirror,y,z) for x,y in ((x0+u,y0+w),(x1+u,y1+w),(x1-u,y1-w),(x0-u,y0-w))]
                faces.append((q if z==z0 else q[::-1],5))
    for cx,d in ((-.66,-.18),(.66,.18)):
        box(cx-.11,-.55,d-.12,cx+.11,.046,d+.12,0,1)
        box(cx-.033,.042,d-.033,cx+.033,.60,d+.033,2,7)
        box(cx-.25,.31,d-.043,cx+.25,.60,d+.043,6,7)
        box(cx-.226,.332,d-.047,cx+.226,.579,d+.047,4,7)
        lettering(cx,d-.049,d+.049)
        for x in (cx-.19,cx+.19):
            for z in (d-.050,d+.050):
                box(x-.013,.555,z-.002,x+.013,.575,z+.002,7)
    lines=["# Original LuanTTD railway waypoint sign and footings."]
    lines += [f"vt {(i+.5)/len(palette):.6f} 0.5" for i in range(len(palette))]
    lines += [f"v {x:.5f} {y:.5f} {z:.5f}" for x,y,z in vertices]
    for q,col in faces:
        lines.append("f "+" ".join(f"{j}/{col+1}" for j in q))
    (base/f"models/bl_rail_waypoint_{axis}.obj").write_text("\n".join(lines)+"\n")
