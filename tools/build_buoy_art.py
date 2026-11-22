#!/usr/bin/env python3
"""Original 3D navigational buoy for LuanTTD's harbor set."""
from math import cos, pi, sin
from pathlib import Path
from PIL import Image

base = Path(__file__).resolve().parents[1] / "mods/luanttd_core"
colours = ["8a4930", "dda749", "f2c554", "b86f36", "f0e5aa", "273c41", "4f6267", "ffeab1"]
palette=Image.new("RGB",(8*len(colours),8))
for i,colour in enumerate(colours):
    palette.paste(tuple(int(colour[j:j+2],16) for j in (0,2,4)),(i*8,0,i*8+8,8))
palette.save(base/"textures/bl_ship_buoy_palette.png",optimize=True)

# Anchored at the even/even node above water. The larger hull partly
# overlaps the water surface to remain firmly set with moving waves.
vertices,faces=[],[]
def ring(radius,height,count=12):
    q=[]
    for i in range(count):
        a=i*2*pi/count
        vertices.append((-.5+radius*cos(a),height-.5,.5+radius*sin(a)))
        q.append(len(vertices))
    return q
def bands(rows):
    outline=[ring(r,h) for r,h,_ in rows]
    for a,b,row in zip(outline,outline[1:],rows):
        for j in range(len(a)):
            k=(j+1)%len(a)
            faces.append(([a[j],b[j],b[k],a[k]],row[2]))
    faces.append((outline[0],rows[0][2]))
    faces.append((outline[-1][::-1],rows[-1][2]))
bands([(.14,-.17,0),(.31,-.10,0),(.34,.03,3),(.33,.115,1),(.25,.18,2),(.17,.19,2)])
bands([(.105,.183,5),(.097,.225,6),(.062,.455,6),(.052,.496,5)])
bands([(.144,.46,5),(.141,.484,4),(.130,.549,4),(.138,.565,5),(.095,.594,5)])
bands([(.072,.58,6),(.073,.608,7),(.055,.65,7),(.041,.672,5),(.03,.688,6)])
lines=["# LuanTTD original yellow navigational buoy, fixed waterline anchor."]
lines += [f"vt {(i+.5)/len(colours):.6f} 0.5" for i in range(len(colours))]
lines += [f"v {x:.5f} {y:.5f} {z:.5f}" for x,y,z in vertices]
lines += ["f "+" ".join(f"{j}/{c+1}" for j in f) for f,c in faces]
(base/"models/bl_ship_buoy.obj").write_text("\n".join(lines)+"\n")
