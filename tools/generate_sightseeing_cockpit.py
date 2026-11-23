"""Generate the original windowed interior of the small sightseeing car."""
from math import cos, pi, sin
from pathlib import Path
from PIL import Image

root = Path(__file__).resolve().parents[1] / "mods/luanttd_core"
vertices, faces = [], []
palette = [
    (159, 38, 33), (108, 36, 31), (59, 54, 44), (76, 75, 69),
    (31, 35, 37), (160, 155, 127), (36, 43, 46), (89, 100, 98),
    (126, 91, 57), (198, 209, 202), (55, 117, 117), (186, 91, 55),
]

def face(points, color):
    start = len(vertices)+1
    vertices.extend(points)
    faces.append((list(range(start, len(vertices)+1)), color))

def box(x0,x1,y0,y1,z0,z1,c):
    v=[(x,y,z) for z in (z0,z1) for y in (y0,y1) for x in (x0,x1)]
    for ix in ((1,0,2,3),(4,5,7,6),(0,4,6,2),(5,1,3,7),(2,6,7,3),(5,4,0,1)):
        face([v[i] for i in ix],c)

def mix(a,b,t):
    return tuple(x+t*(y-x) for x,y in zip(a,b))

def pillars(a,b,c,d,body=.10,sill=.13,header=.10):
    """A structural frame around a truly empty, non-coplanar aperture."""
    inner=[mix(mix(a,b,body),mix(d,c,body),sill),
           mix(mix(a,b,1-body),mix(d,c,1-body),sill),
           mix(mix(d,c,1-body),mix(a,b,1-body),header),
           mix(mix(d,c,body),mix(a,b,body),header)]
    outer=[a,b,c,d]
    for i,col in enumerate((2,0,5,0)):
        j=(i+1)%4
        face([outer[i],outer[j],inner[j],inner[i]],col)

low=[(-1.075,1.70,-1.59),(1.075,1.70,-1.59),(1.06,1.70,1.71),(-1.06,1.70,1.71)]
high=[(-.792,2.75,-1.23),(.792,2.75,-1.23),(.775,2.76,.68),(-.775,2.76,.68)]
for i in range(4):
    j=(i+1)%4
    # Longer side windows give a clear look at the actual streets.
    pillars(low[i],low[j],high[j],high[i],.075 if i%2 else .095,.10,.09)
    a,b=low[i],low[j]
    face([a,b,(b[0],.88,b[2]),(a[0],.88,a[2])],0 if i%2 else 2)
face(high[::-1],5)
box(-1.02,1.02,.77,.83,-1.62,1.80,2)
# External edges visible through the open glass (hood and rear deck).
face([(-1.07,1.665,1.71),(1.07,1.665,1.71),(1.01,1.526,2.99),(-1.01,1.526,2.99)],0)
face([(-1.045,1.66,-1.59),(-.98,1.56,-2.82),(.98,1.56,-2.82),(1.045,1.66,-1.59)],0)
# Padded dash, instrument cluster and center vents.
box(-1.00,1.00,1.44,1.72,1.05,1.65,4)
box(-.97,.97,1.68,1.76,1.15,1.58,3)
box(.17,.74,1.72,1.865,1.25,1.34,6)
for x in (.28,.47,.65):
    box(x-.031,x+.031,1.787,1.814,1.232,1.250,9)
for x in (-.41,-.3,-.19,-.08,.03):
    box(x-.028,x+.028,1.59,1.655,1.027,1.043,7)
for x in (-.41,-.25,-.09):
    box(x-.027,x+.027,1.48,1.54,1.025,1.040,10 if x==-.25 else 11)
# Steering wheel: near ring pitched toward the driver's eye.
ring=[]
for i in range(20):
    ang=i*2*pi/20
    ring.append([(.45+(r*cos(ang)),1.67+r*sin(ang),.83-.36*r*sin(ang)) for r in (.32,.245)])
for i in range(20):
    j=(i+1)%20
    face([ring[i][0],ring[j][0],ring[j][1],ring[i][1]],4)
box(.325,.575,1.625,1.73,.80,.87,4)
box(.422,.479,1.4,1.675,.79,.87,4)
box(.36,.54,1.64,1.706,.784,.807,7)
# Two seat cushions and contrast-stitched backs. The driver eye is ahead of
# the front left headrest; no geometry crosses its camera or the apertures.
for x in (-.45,.45):
    box(x-.255,x+.255,.9,1.11,-.80,.44,8)
    box(x-.277,x+.277,1.05,2.02,-1.19,-1.075,3)
    box(x-.166,x+.166,2.02,2.29,-1.24,-1.12,2)
    box(x-.22,x+.22,.98,1.126,-.79,.35,8)
box(-.9,.9,.87,1.1,-1.53,-.91,8)
box(-.94,.94,1.02,1.6,-1.54,-1.39,3)
# Interior rear-view and side mirrors (fixed reflecting material swatches).
box(-.25,.25,2.56,2.665,.48,.532,4)
box(-.20,.2,2.582,2.64,.464,.486,7)
for x in (-1,1):
    box(min(1.01*x,1.25*x),max(1.01*x,1.25*x),1.71,1.80,1.20,1.37,0)
    box(min(1.07*x,1.24*x),max(1.07*x,1.24*x),1.738,1.78,1.18,1.205,7)
# Original stitched arm rests and brushed metal door pulls.
for x in (-1,1):
    box(min(.93*x,1.02*x),max(.93*x,1.02*x),1.35,1.45,-.45,.56,3)
    box(min(.91*x,1.02*x),max(.91*x,1.02*x),1.55,1.59,.31,.62,9)
out=["# Original sightseeing cabin; windows are real openings. +Z nose, 10 units per node.",
     "o LuanTTD_Sightseeing_Cockpit"]
# Origin at the driver's eye column: Luanti's OBJ loader reflects X.
out.extend("v %.5f %.5f %.5f" % (x-.45,y,z+1.0) for x,y,z in vertices)
out.extend("vt %.5f .5"%((i+.5)/16) for i in range(len(palette)))
out.extend("f "+" ".join(f"{i}/{c+1}" for i in ids) for ids,c in faces)
(root/"models/bl_sightseeing_car_interior.obj").write_text("\n".join(out)+"\n")
im=Image.new("RGB",(128,8))
for i,col in enumerate(palette):
    im.paste(col,(i*8,0,(i+1)*8,8))
im.save(root/"textures/bl_sightseeing_car_interior_atlas.png",optimize=True)
